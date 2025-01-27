#!/usr/bin/env bash
#
# remove_subdomain.sh
# Usage: ./remove_subdomain.sh <subdomainName>
#
# - Removes the corresponding subdomain from .env + .env.production
# - Removes or archives wikis/<subdomain> + data/<subdomain>
# - Removes the Docker Compose service block
# - Optionally re-numbers ports if you want to keep them consecutive
#

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

# 1) Confirm subdomain is present
function subdomain_exists_in_env() {
  local envFile="$1"
  local subdomain="$2"
  if grep -E "^SUBDOMAINS=" "$envFile" | grep -qw "$subdomain"; then
    return 0
  else
    return 1
  fi
}

if ! subdomain_exists_in_env "$ENV_DEV_FILE" "$SUBDOMAIN" && \
   ! subdomain_exists_in_env "$ENV_PROD_FILE" "$SUBDOMAIN"; then
  echo "WARNING: Subdomain '$SUBDOMAIN' not found in .env or .env.production. Proceeding anyway."
fi

echo "Subdomain to remove: '$SUBDOMAIN'"
echo "This will affect $WIKI_SUBDOMAIN_PATH, $DATA_SUBDOMAIN_PATH, and $DOCKER_COMPOSE_FILE."

# 2) Prompt to confirm
read -p "Are you sure you want to remove subdomain '$SUBDOMAIN'? (y/N) " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "Aborting."
  exit 1
fi

# 3) Remove from .env and .env.production
function remove_subdomain_from_env() {
  local envFile="$1"
  local subdomain="$2"

  # For dev, subdomain is subdomain.gyld.local
  # For prod, subdomain is subdomain.gyld.app
  if [[ "$envFile" == ".env" ]]; then
    local domainExt=".gyld.local"
  else
    local domainExt=".gyld.app"
  fi
  local fqdn="$subdomain$domainExt"

  if grep -E "^SUBDOMAINS=" "$envFile" >/dev/null; then
    sed -i.bak "s/\b${fqdn}\b//g" "$envFile"
    # Remove double-spaces if they appear
    sed -i.bak 's/  / /g' "$envFile"
    rm -f "$envFile.bak"
  fi
}

remove_subdomain_from_env "$ENV_DEV_FILE" "$SUBDOMAIN"
remove_subdomain_from_env "$ENV_PROD_FILE" "$SUBDOMAIN"

# 4) Remove or archive wikis/<subdomain>, data/<subdomain>
#    You may want to do a `mv` to some backup location instead of `rm -rf`
if [[ -d "$WIKI_SUBDOMAIN_PATH" || -d "$DATA_SUBDOMAIN_PATH" ]]; then
  echo "Removing $WIKI_SUBDOMAIN_PATH and $DATA_SUBDOMAIN_PATH..."
  rm -rf "$WIKI_SUBDOMAIN_PATH"
  rm -rf "$DATA_SUBDOMAIN_PATH"
else
  echo "Warning: $WIKI_SUBDOMAIN_PATH or $DATA_SUBDOMAIN_PATH not found. Skipping."
fi

# 5) Remove Docker Compose service block
#    We look for a block named:
#       subdomain:
#         container_name: mws_subdomain
#       ...
#    We'll remove from 'subdomain:' down to the next unindented line or 'networks:'
cp "$DOCKER_COMPOSE_FILE" "$DOCKER_COMPOSE_FILE.bak"

echo "Removing service block for subdomain '$SUBDOMAIN' from $DOCKER_COMPOSE_FILE..."

awk -v sd="$SUBDOMAIN" '
  BEGIN {skip=0}
  /^ *[^ :]+:$/ {
    # Check if this line is exactly something like "sdm:" or "silat:"
    sub(/^ +/, "", $0)  # Trim leading spaces
    name=$1
    sub(/:$/, "", name)
    if (name == sd) {
      skip=1
      next
    }
  }
  # If skipping, keep skipping until we hit another top-level line or end of file
  skip && /^[^ ]/ { skip=0 }
  !skip { print }
' "$DOCKER_COMPOSE_FILE.bak" > "$DOCKER_COMPOSE_FILE"

# 6) (Optional) Renumber ports
#    If you want to keep them consecutive, parse them in ascending order
#    and reassign them. This can be tricky if you have many subdomains.
#    Example: 8080 (admin) 8081, 8082 -> remove 8081 -> then new subdomain is 8081 again
#    NOTE: This step can break references if your NGINX or other scripts rely on consistent port numbering.
#    We’ll demonstrate a naive approach below. If you prefer not to renumber, remove this step.

echo
read -p "Renumber ports in $DOCKER_COMPOSE_FILE to close gaps? (y/N) " RENUM
if [[ "$RENUM" == "y" || "$RENUM" == "Y" ]]; then
  echo "Renumbering external ports in ascending order starting from 8080..."
  # We'll gather existing ports that map to 8080 inside the container
  # Then sort them, then reassign them in ascending order again.
  MAPFILE=($(grep -oE '[0-9]+:8080' "$DOCKER_COMPOSE_FILE" | awk -F: '{print $1}' | sort -n))
  # e.g. MAPFILE might be (8080 8082 8083)
  # We want them to become 8080, 8081, 8082, etc.
  # We'll do a quick pass. We must be careful to not reassign the same port to multiple lines at once.
  i=0
  newPort=8080
  cp "$DOCKER_COMPOSE_FILE" "$DOCKER_COMPOSE_FILE.tmp"
  for oldPort in "${MAPFILE[@]}"; do
    # replace only the FIRST occurrence in a line "oldPort:8080"
    sed -i.bak "0,/$oldPort:8080/s//$newPort:8080/" "$DOCKER_COMPOSE_FILE.tmp"
    ((newPort++))
  done
  mv "$DOCKER_COMPOSE_FILE.tmp" "$DOCKER_COMPOSE_FILE"
  rm -f "$DOCKER_COMPOSE_
