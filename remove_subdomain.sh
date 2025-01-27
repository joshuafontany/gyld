#!/usr/bin/env bash
#
# remove_subdomain.sh
# Usage: ./remove_subdomain.sh <subdomainName>
#
# Removes subdomain from .env/.env.production, deletes wikis/<subdomain>,
# and removes the service block from docker-compose.yml using yq.

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

WIKI_SUBDOMAIN_PATH="$WIKIS_DIR/$SUBDOMAIN"
DATA_SUBDOMAIN_PATH="$DATA_DIR/$SUBDOMAIN"

echo "Preparing to remove subdomain '$SUBDOMAIN'..."
echo "This will affect .env files, $WIKI_SUBDOMAIN_PATH, $DATA_SUBDOMAIN_PATH, and $DOCKER_COMPOSE_FILE."

read -p "Are you sure? (y/N) " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "Aborting."
  exit 1
fi

# 1) Remove from .env and .env.production
function remove_subdomain_from_env() {
  local envFile="$1"
  local sub="$2"
  if [[ "$envFile" == ".env" ]]; then
    local domainExt=".gyld.local"
  else
    local domainExt=".gyld.app"
  fi
  local fqdn="$sub$domainExt"

  if grep -Eq "^SUBDOMAINS=" "$envFile"; then
    sed -i.bak "s/$fqdn//g; s/  / /g" "$envFile"
    rm -f "$envFile.bak"
  fi
}

remove_subdomain_from_env "$ENV_DEV_FILE" "$SUBDOMAIN"
remove_subdomain_from_env "$ENV_PROD_FILE" "$SUBDOMAIN"

# 2) Remove wikis + data
if [[ -d "$WIKI_SUBDOMAIN_PATH" || -d "$DATA_SUBDOMAIN_PATH" ]]; then
  echo "Removing $WIKI_SUBDOMAIN_PATH and $DATA_SUBDOMAIN_PATH..."
  rm -rf "$WIKI_SUBDOMAIN_PATH" "$DATA_SUBDOMAIN_PATH"
fi

# 3) Remove subdomain from docker-compose.yml using yq
#    The service key in .services is <subdomain>.
cp "$DOCKER_COMPOSE_FILE" "$DOCKER_COMPOSE_FILE.bak"

echo "Removing service '$SUBDOMAIN' from $DOCKER_COMPOSE_FILE..."
yq e "del(.services.\"$SUBDOMAIN\")" "$DOCKER_COMPOSE_FILE" > "${DOCKER_COMPOSE_FILE}.tmp"
mv "${DOCKER_COMPOSE_FILE}.tmp" "$DOCKER_COMPOSE_FILE"

# 4) (Optional) renumber ports
echo
read -p "Renumber ports to close gaps? (y/N) " RENUM
if [[ "$RENUM" =~ ^[yY]$ ]]; then
  echo "Renumbering external ports in ascending order (8080, 8081, 8082...)"
  # We'll gather existing host ports that map to "8080".
  MAPFILE=($(grep -oE '[0-9]+:8080' "$DOCKER_COMPOSE_FILE" | cut -d':' -f1 | sort -n))
  i=0
  newPort=8080
  cp "$DOCKER_COMPOSE_FILE" "$DOCKER_COMPOSE_FILE.tmp"

  for oldPort in "${MAPFILE[@]}"; do
    # Replace only first occurrence "oldPort:8080" -> "newPort:8080"
    sed -i.bak "0,/$oldPort:8080/s//$newPort:8080/" "$DOCKER_COMPOSE_FILE.tmp"
    ((newPort++))
  done

  mv "$DOCKER_COMPOSE_FILE.tmp" "$DOCKER_COMPOSE_FILE"
  rm -f "$DOCKER_COMPOSE_FILE.tmp.bak"
  echo "Renumbering complete."
fi

echo "Done removing '$SUBDOMAIN'."
echo "You can now run 'docker-compose up -d --remove-orphans' to remove the container."
echo "Then re-deploy NGINX config if needed (dev or production)."
