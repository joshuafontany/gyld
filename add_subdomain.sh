#!/usr/bin/env bash
#
# add_subdomain.sh
# Usage: ./add_subdomain.sh <subdomainName>
#
# Example: ./add_subdomain.sh sdm
#
# Steps:
#   1. Check subdomain doesn’t already exist in .env/.env.production
#   2. Create wikis/<subdomain> + data/<subdomain>/store
#   3. Parse docker-compose.yml to find next available port mapping
#   4. Insert new service block in docker-compose.yml
#   5. Append subdomain to SUBDOMAINS in .env/.env.production
#   6. Confirm changes with user
#   7. Optionally call "npm run nginx:deploy:dev" or "npm run nginx:deploy:prod"

set -e

SUBDOMAIN="$1"
if [[ -z "$SUBDOMAIN" ]]; then
  echo "Usage: $0 <subdomain>"
  exit 1
fi

# Paths
ENV_DEV_FILE=".env"
ENV_PROD_FILE=".env.production"
DOCKER_COMPOSE_FILE="docker-compose.yml"
WIKIS_DIR="wikis"
DATA_DIR="data"

# 1) Check subdomain doesn’t already exist
function subdomain_exists_in_env() {
  local envFile="$1"
  local subdomain="$2"
  # We look for SUBDOMAINS line and see if it already contains the subdomain
  if grep -E "^SUBDOMAINS=" "$envFile" | grep -qw "$subdomain"; then
    return 0
  else
    return 1
  fi
}

if subdomain_exists_in_env "$ENV_DEV_FILE" "$SUBDOMAIN" || subdomain_exists_in_env "$ENV_PROD_FILE" "$SUBDOMAIN"; then
  echo "ERROR: Subdomain '$SUBDOMAIN' already exists in $ENV_DEV_FILE or $ENV_PROD_FILE."
  exit 1
fi

# 2) Create wikis/<subdomain> + data/<subdomain>/store
WIKI_SUBDOMAIN_PATH="$WIKIS_DIR/$SUBDOMAIN"
DATA_SUBDOMAIN_PATH="$DATA_DIR/$SUBDOMAIN"
if [[ -d "$WIKI_SUBDOMAIN_PATH" || -d "$DATA_SUBDOMAIN_PATH" ]]; then
  echo "ERROR: Directories $WIKI_SUBDOMAIN_PATH or $DATA_SUBDOMAIN_PATH already exist. Aborting."
  exit 1
fi

echo "Creating directory structure for '$SUBDOMAIN'..."
mkdir -p "$WIKI_SUBDOMAIN_PATH"
mkdir -p "$DATA_SUBDOMAIN_PATH/store"

# Optionally, create a bare-bones tiddlywiki.info
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

# 3) Parse docker-compose.yml to find next available external port
# We expect something like "8080:8080", "8081:8080", etc.
echo "Finding next available port in $DOCKER_COMPOSE_FILE..."
LAST_PORT=$(grep -oE '[0-9]{4}:8080' "$DOCKER_COMPOSE_FILE" | awk -F: '{print $1}' | sort -n | tail -1)
if [[ -z "$LAST_PORT" ]]; then
  # If no match found, assume 8080 is used by admin, so we’ll use 8081
  LAST_PORT=8080
fi
NEXT_PORT=$(( LAST_PORT + 1 ))
echo "Latest used port is: $LAST_PORT. Next available is: $NEXT_PORT."

# 4) Insert new service block
SERVICE_NAME="mws_${SUBDOMAIN}"
SERVICE_BLOCK="
  $SUBDOMAIN:
    container_name: mws_${SUBDOMAIN}
    build:
      context: .
      dockerfile: docker/mws/Dockerfile
    command: [ \"node\", \"./tiddlywiki.js\", \"./editions/${SUBDOMAIN}\", \"--mws-listen\" ]
    working_dir: \"/app/TiddlyWiki5\"
    environment:
      - HOST=0.0.0.0
      - PORT=8080
    volumes:
      - ./${WIKIS_DIR}/${SUBDOMAIN}:/app/TiddlyWiki5/editions/${SUBDOMAIN}:ro
      - ./${DATA_DIR}/${SUBDOMAIN}:/app/TiddlyWiki5/editions/${SUBDOMAIN}/store
    ports:
      - \"${NEXT_PORT}:8080\"
    networks:
      - mws_net
"

echo "Will insert the following service block into $DOCKER_COMPOSE_FILE:"
echo "$SERVICE_BLOCK"

# 5) Append subdomain to SUBDOMAINS in .env and .env.production
# Also for both .gyld.local and .gyld.app references
echo "Updating environment files..."
function add_subdomain_to_env_file() {
  local envFile="$1"
  local subdomain="$2"
  # We assume there's a line SUBDOMAINS="sdm.gyld.local silat.gyld.local"
  # We'll insert $subdomain.gyld.local and $subdomain.gyld.app
  local oldLine
  local newLine

  oldLine=$(grep -E "^SUBDOMAINS=" "$envFile" || true)
  if [[ -n "$oldLine" ]]; then
    # Subdomain for .local or .app
    # For dev, we assume .local
    if [[ "$envFile" == ".env" ]]; then
      local domainExt=".gyld.local"
    else
      local domainExt=".gyld.app"
    fi
    newLine=$(echo "$oldLine" | sed "s/\"$/ $subdomain$domainExt\"/")
    sed -i.bak "s|^SUBDOMAINS=.*|$newLine|" "$envFile"
    rm -f "$envFile.bak"
  else
    # If SUBDOMAINS= doesn't exist, create it
    echo "SUBDOMAINS=\"$subdomain.gyld.local\"" >> "$envFile"
  fi
}

add_subdomain_to_env_file "$ENV_DEV_FILE" "$SUBDOMAIN"
add_subdomain_to_env_file "$ENV_PROD_FILE" "$SUBDOMAIN"

# 6) Confirm changes with user
echo
echo "===== REVIEW CHANGES ====="
echo "New directories created: $WIKI_SUBDOMAIN_PATH, $DATA_SUBDOMAIN_PATH"
echo "New Docker Compose block (port $NEXT_PORT) will be appended at the end of $DOCKER_COMPOSE_FILE."
echo "SUBDOMAIN added to $ENV_DEV_FILE and $ENV_PROD_FILE."
read -p "Proceed with these changes? (y/N) " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "Aborting."
  exit 1
fi

# Actually append the service block at the end of the 'services:' section
# We'll insert before 'networks:' if it exists
# or simply append at end if no 'networks:' line
echo "Committing changes to $DOCKER_COMPOSE_FILE..."
# Backup
cp "$DOCKER_COMPOSE_FILE" "$DOCKER_COMPOSE_FILE.bak"

# We use an awk approach to insert the new service block before 'networks:' if found
awk -v block="$SERVICE_BLOCK" '
  /networks:/ {
    print block
  }
  { print }
' "$DOCKER_COMPOSE_FILE.bak" > "$DOCKER_COMPOSE_FILE"

rm -f "$DOCKER_COMPOSE_FILE.bak"

echo "Subdomain '$SUBDOMAIN' added successfully."

# 7) (Optionally) re-deploy or do manual steps
echo
echo "You can now run Docker Compose to spin up the new container, e.g.:"
echo "  docker-compose up -d"
echo
echo "Then re-deploy NGINX config via dev or prod environment:"
echo "  npm run nginx:deploy:dev   # or"
echo "  npm run nginx:deploy:prod"
echo
echo "Done!"
