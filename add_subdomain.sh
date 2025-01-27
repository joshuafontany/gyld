#!/usr/bin/env bash
#
# add_subdomain.sh
# Usage: ./add_subdomain.sh <subdomainName>
#
# This script adds a new MultiWikiServer subdomain to:
#   - .env / .env.production (SUBDOMAINS=...)
#   - docker-compose.yml (as a new service, using yq)
#   - wikis/<subdomain> + wikis/<subdomain>/tiddlers + data/<subdomain>/store
#
# Steps:
#   1. Check subdomain doesn’t already exist in .env/.env.production
#   2. Create the necessary wikis/data directories
#   3. Insert a new service block into docker-compose.yml
#   4. Append the subdomain to SUBDOMAINS in .env + .env.production
#   5. Confirm changes, revert if canceled
#   6. Remind user to run docker-compose up -d + redeploy NGINX

set -e

SUBDOMAIN="$1"
if [[ -z "$SUBDOMAIN" ]]; then
  echo "Usage: $0 <subdomain>"
  exit 1
fi

ENV_DEV_FILE=".env"
ENV_PROD_FILE=".env.production"
DOCKER_COMPOSE_FILE="docker-compose.yml"
WIKIS_DIR="wikis"
DATA_DIR="data"

# 1) Check if subdomain is already in SUBDOMAINS for dev or prod
function subdomain_exists_in_env() {
  local envFile="$1"
  local sd="$2"
  if [[ -f "$envFile" ]]; then
    grep -E "^SUBDOMAINS=" "$envFile" | grep -qw "$sd"
  else
    return 1
  fi
}

if subdomain_exists_in_env "$ENV_DEV_FILE" "$SUBDOMAIN" || subdomain_exists_in_env "$ENV_PROD_FILE" "$SUBDOMAIN"; then
  echo "ERROR: Subdomain '$SUBDOMAIN' already listed in $ENV_DEV_FILE or $ENV_PROD_FILE."
  exit 1
fi

# 2) Create subdomain directories (wikis + data)
WIKI_SUBDOMAIN_PATH="$WIKIS_DIR/$SUBDOMAIN"
DATA_SUBDOMAIN_PATH="$DATA_DIR/$SUBDOMAIN"

if [[ -d "$WIKI_SUBDOMAIN_PATH" || -d "$DATA_SUBDOMAIN_PATH" ]]; then
  echo "ERROR: Directories for '$SUBDOMAIN' already exist."
  exit 1
fi

echo "Creating directory structure for '$SUBDOMAIN'..."
mkdir -p "$WIKI_SUBDOMAIN_PATH/tiddlers"
mkdir -p "$DATA_SUBDOMAIN_PATH/store"

# Create a minimal tiddlywiki.info
cat > "$WIKI_SUBDOMAIN_PATH/tiddlywiki.info" <<EOF
{
  "description": "MWS subdomain: $SUBDOMAIN",
  "plugins": [
    "tiddlywiki/tiddlyweb",
    "tiddlywiki/filesystem",
    "tiddlywiki/multiwikiclient",
    "tiddlywiki/multiwikiserver"
  ],
  "themes": [
    "tiddlywiki/vanilla",
    "tiddlywiki/snowwhite"
  ]
}
EOF

# Create configMultiWikiServerEngine.tid
cat > "$WIKI_SUBDOMAIN_PATH/tiddlers/configMultiWikiServerEngine.tid" <<EOF
title: \$:/config/MultiWikiServer/Engine
text: better
EOF

echo "Created:"
echo "  - $WIKI_SUBDOMAIN_PATH/tiddlywiki.info"
echo "  - $WIKI_SUBDOMAIN_PATH/tiddlers/configMultiWikiServerEngine.tid"
echo "  - $DATA_SUBDOMAIN_PATH/store"

# 3) Determine next available port by scanning existing "XXXX:8080" mappings
echo "Finding next available port in $DOCKER_COMPOSE_FILE..."
LAST_PORT=$(grep -oE '[0-9]{4}:8080' "$DOCKER_COMPOSE_FILE" | cut -d':' -f1 | sort -n | tail -1)
if [[ -z "$LAST_PORT" ]]; then
  # If no match found, default to 8080
  LAST_PORT=8080
fi
NEXT_PORT=$(( LAST_PORT + 1 ))
echo "Latest used port: $LAST_PORT. Next port: $NEXT_PORT"

# Build a temporary YAML snippet with just the subdomain service
TMP_SERVICE_YAML="$(mktemp)"
cat > "$TMP_SERVICE_YAML" <<EOF
$SUBDOMAIN:
  container_name: mws_$SUBDOMAIN
  build:
    context: .
    dockerfile: docker/mws/Dockerfile
  command: ["node", "./tiddlywiki.js", "./editions/$SUBDOMAIN", "--mws-listen"]
  working_dir: "/app/TiddlyWiki5"
  environment:
    - HOST=0.0.0.0
    - PORT=8080
  volumes:
    - "./wikis/$SUBDOMAIN:/app/TiddlyWiki5/editions/$SUBDOMAIN:ro"
    - "./data/$SUBDOMAIN:/app/TiddlyWiki5/editions/$SUBDOMAIN/store"
  ports:
    - "$NEXT_PORT:8080"
  networks:
    - mws_net
EOF

# Backup existing compose
cp "$DOCKER_COMPOSE_FILE" "$DOCKER_COMPOSE_FILE.bak"

# Merge snippet into docker-compose.yml under services, using yq
echo "Merging subdomain '$SUBDOMAIN' into 'services:' with port $NEXT_PORT..."
yq e '.services += load("'"$TMP_SERVICE_YAML"'")' "$DOCKER_COMPOSE_FILE" \
   > "${DOCKER_COMPOSE_FILE}.tmp"

mv "${DOCKER_COMPOSE_FILE}.tmp" "$DOCKER_COMPOSE_FILE"
rm -f "$TMP_SERVICE_YAML"

# 4) Append subdomain to SUBDOMAINS in .env & .env.production
function add_subdomain_to_env() {
  local envFile="$1"
  local sd="$2"

  # If .env => subdomain.gyld.local, else => subdomain.gyld.app
  if [[ "$envFile" == ".env" ]]; then
    local domainExt=".gyld.local"
  else
    local domainExt=".gyld.app"
  fi

  # If SUBDOMAINS= line doesn't exist, create it
  if ! grep -Eq "^SUBDOMAINS=" "$envFile" 2>/dev/null; then
    echo "SUBDOMAINS=\"$sd$domainExt\"" >> "$envFile"
  else
    # If it does, add to the end
    sed -i.bak "s/\"$/ $sd$domainExt\"/" "$envFile"
    rm -f "$envFile.bak"
  fi
}

add_subdomain_to_env "$ENV_DEV_FILE" "$SUBDOMAIN"
add_subdomain_to_env "$ENV_PROD_FILE" "$SUBDOMAIN"

# 5) Confirm changes. If canceled, restore docker-compose.yml
echo
echo "===== REVIEW CHANGES ====="
echo " - Subdomain directories: $WIKI_SUBDOMAIN_PATH, $DATA_SUBDOMAIN_PATH"
echo " - Inserted service '$SUBDOMAIN' in $DOCKER_COMPOSE_FILE with port $NEXT_PORT"
echo " - Added '$SUBDOMAIN.gyld.local' to SUBDOMAINS in $ENV_DEV_FILE"
echo " - Added '$SUBDOMAIN.gyld.app' to SUBDOMAINS in $ENV_PROD_FILE"

read -p "Proceed? (y/N) " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "Aborting. Restoring original $DOCKER_COMPOSE_FILE..."
  mv "$DOCKER_COMPOSE_FILE.bak" "$DOCKER_COMPOSE_FILE"
  # Optionally remove newly created directories if user wants a full rollback
  exit 1
fi

rm -f "$DOCKER_COMPOSE_FILE.bak"

echo
echo "Subdomain '$SUBDOMAIN' added successfully!"
echo "You can now run: docker-compose up -d"
echo "Then redeploy NGINX (e.g. npm run nginx:deploy:dev or npm run nginx:deploy:prod)"
echo

