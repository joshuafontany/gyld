#!/usr/bin/env bash
#
# add_subdomain.sh
# Usage: ./add_subdomain.sh <subdomainName>
#
# Steps:
#   1. Check subdomain doesn’t already exist in .env/.env.production
#   2. Create wikis/<subdomain> + data/<subdomain>/store
#   3. Generate a new service block in memory
#   4. Use yq to insert that block into docker-compose.yml
#   5. Append subdomain to SUBDOMAINS in .env/.env.production
#   6. Confirm changes
#   7. (Optional) run docker-compose + redeploy

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

function subdomain_exists_in_env() {
  local envFile="$1"
  local subdomain="$2"
  grep -E "^SUBDOMAINS=" "$envFile" | grep -qw "$subdomain"
}

if subdomain_exists_in_env "$ENV_DEV_FILE" "$SUBDOMAIN" || subdomain_exists_in_env "$ENV_PROD_FILE" "$SUBDOMAIN"; then
  echo "ERROR: Subdomain '$SUBDOMAIN' already in $ENV_DEV_FILE or $ENV_PROD_FILE."
  exit 1
fi

WIKI_SUBDOMAIN_PATH="$WIKIS_DIR/$SUBDOMAIN"
DATA_SUBDOMAIN_PATH="$DATA_DIR/$SUBDOMAIN"
if [[ -d "$WIKI_SUBDOMAIN_PATH" || -d "$DATA_SUBDOMAIN_PATH" ]]; then
  echo "ERROR: Directories already exist for $SUBDOMAIN."
  exit 1
fi

echo "Creating directory structure for '$SUBDOMAIN'..."
mkdir -p "$WIKI_SUBDOMAIN_PATH"
mkdir -p "$DATA_SUBDOMAIN_PATH/store"

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

echo "Created $WIKI_SUBDOMAIN_PATH/tiddlywiki.info"

echo "Finding next available port in $DOCKER_COMPOSE_FILE..."
LAST_PORT=$(grep -oE '[0-9]{4}:8080' "$DOCKER_COMPOSE_FILE" | cut -d':' -f1 | sort -n | tail -1)
if [[ -z "$LAST_PORT" ]]; then
  LAST_PORT=8080
fi
NEXT_PORT=$(( LAST_PORT + 1 ))
echo "Latest used port: $LAST_PORT. Next port: $NEXT_PORT."

# We'll add the service as a YAML structure. With yq, we can insert objects easily.
# For safety, we'll define a temporary YAML file for the subdomain service block.
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

echo "Prepared temporary service block file: $TMP_SERVICE_YAML"

# Insert it under `services:` in docker-compose.yml using yq
echo "Will insert subdomain '$SUBDOMAIN' into $DOCKER_COMPOSE_FILE."

# Backup
cp "$DOCKER_COMPOSE_FILE" "$DOCKER_COMPOSE_FILE.bak"

# Merge the new service into the `.services` object
yq eval-all '
  select(fileIndex == 0) as $main |
  select(fileIndex == 1) as $toMerge |
  $main * {"services": $toMerge}
' "$DOCKER_COMPOSE_FILE" "$TMP_SERVICE_YAML" > "${DOCKER_COMPOSE_FILE}.tmp"

mv "${DOCKER_COMPOSE_FILE}.tmp" "$DOCKER_COMPOSE_FILE"

# 5) Update .env / .env.production
function add_subdomain_to_env() {
  local envFile="$1"
  local sd="$2"
  if [[ "$envFile" == ".env" ]]; then
    local domainExt=".gyld.local"
  else
    local domainExt=".gyld.app"
  fi
  local oldLine
  oldLine=$(grep -E "^SUBDOMAINS=" "$envFile" || true)
  if [[ -z "$oldLine" ]]; then
    echo "SUBDOMAINS=\"$sd$domainExt\"" >> "$envFile"
  else
    sed -i.bak "s|\"$| $sd$domainExt\"|" "$envFile"
    rm -f "$envFile.bak"
  fi
}

add_subdomain_to_env "$ENV_DEV_FILE" "$SUBDOMAIN"
add_subdomain_to_env "$ENV_PROD_FILE" "$SUBDOMAIN"

echo
echo "===== REVIEW CHANGES ====="
echo " - Created $WIKI_SUBDOMAIN_PATH + $DATA_SUBDOMAIN_PATH"
echo " - Inserted service '$SUBDOMAIN' into docker-compose.yml with port $NEXT_PORT"
echo " - Appended '$SUBDOMAIN.gyld.local' to SUBDOMAINS in .env"
echo " - Appended '$SUBDOMAIN.gyld.app' to SUBDOMAINS in .env.production"
read -p "Proceed? (y/N) " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "Aborting (restored original docker-compose.yml)."
  mv "$DOCKER_COMPOSE_FILE.bak" "$DOCKER_COMPOSE_FILE"
  exit 1
fi

rm -f "$DOCKER_COMPOSE_FILE.bak"
rm -f "$TMP_SERVICE_YAML"

echo "Subdomain '$SUBDOMAIN' added successfully."
echo "You can now run 'docker-compose up -d' and re-deploy NGINX."
