#!/usr/bin/env bash
#
# manage_subdomains.sh
# Usage: ./manage_subdomains.sh add|remove <subdomainName>
#
# This script manages MultiWikiServer subdomains by adding or removing them from:
#   - .env / .env.production (SUBDOMAINS=...)
#   - docker-compose.yml (manages services using yq)
#   - wikis/<subdomain> and data/<subdomain>
#
# Steps:
#   1. Propose changes to the user
#   2. Confirm changes, then proceed
#   3. Add/remove the subdomain
#   4. Ensure docker-compose.yml structure integrity
#   5. Remind user to restart services

set -e

COMMAND="$1"
SUBDOMAIN="$2"
if [[ -z "$COMMAND" || -z "$SUBDOMAIN" ]]; then
  echo "Usage: $0 add|remove <subdomain>"
  exit 1
fi

ENV_DEV_FILE=".env"
ENV_PROD_FILE=".env.production"
DOCKER_COMPOSE_FILE="docker-compose.yml"
WIKIS_DIR="wikis"
DATA_DIR="data"

function subdomain_exists_in_env() {
  local envFile="$1"
  local sd="$2"
  if [[ -f "$envFile" ]]; then
    grep -E "^SUBDOMAINS=" "$envFile" | grep -qw "$sd"
  else
    return 1
  fi
}

case "$COMMAND" in
  add)
    if subdomain_exists_in_env "$ENV_DEV_FILE" "$SUBDOMAIN" || subdomain_exists_in_env "$ENV_PROD_FILE" "$SUBDOMAIN"; then
      echo "ERROR: Subdomain '$SUBDOMAIN' already exists."
      exit 1
    fi

    echo "The following changes will be made:"
    echo "- Create directories: $WIKIS_DIR/$SUBDOMAIN, $DATA_DIR/$SUBDOMAIN"
    echo "- Add service to $DOCKER_COMPOSE_FILE"
    echo "- Append $SUBDOMAIN to SUBDOMAINS in .env and .env.production"

    read -p "Proceed? (y/N) " CONFIRM
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
      echo "Operation canceled."
      exit 1
    fi

    mkdir -p "$WIKIS_DIR/$SUBDOMAIN/tiddlers"
    mkdir -p "$DATA_DIR/$SUBDOMAIN/store"

    LAST_PORT=$(yq e '.services.*.ports | select(. != null) | .[] | split(":")[0]' "$DOCKER_COMPOSE_FILE" | sort -nr | head -n1)
    NEXT_PORT=$((LAST_PORT + 1))

    echo "Adding service to docker-compose.yml..."
    yq eval '.services."'"$SUBDOMAIN"'" = {
      "container_name": "mws_'"$SUBDOMAIN"'",
      "build": {"context": ".", "dockerfile": "docker/mws/Dockerfile"},
      "command": ["node", "./tiddlywiki.js", "./editions/'"$SUBDOMAIN"'", "--mws-listen"],
      "working_dir": "/app/TiddlyWiki5",
      "environment": ["HOST=0.0.0.0", "PORT=8080"],
      "volumes": ["./wikis/'"$SUBDOMAIN"'": "/app/TiddlyWiki5/editions/'"$SUBDOMAIN"'", "./data/'"$SUBDOMAIN"'": "/app/TiddlyWiki5/editions/'"$SUBDOMAIN"'/store"],
      "ports": ["'"$NEXT_PORT"'":8080]
    }' "$DOCKER_COMPOSE_FILE" -i

    for envFile in "$ENV_DEV_FILE" "$ENV_PROD_FILE"; do
      sed -i.bak "s/"$/ $SUBDOMAIN"/" "$envFile"
      rm -f "$envFile.bak"
    done
    ;;

  remove)
    echo "The following changes will be made:"
    echo "- Remove service block for $SUBDOMAIN from $DOCKER_COMPOSE_FILE"
    echo "- Remove $SUBDOMAIN from SUBDOMAINS in .env and .env.production"
    echo "- Delete directories: $WIKIS_DIR/$SUBDOMAIN, $DATA_DIR/$SUBDOMAIN"

    read -p "Proceed? (y/N) " CONFIRM
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
      echo "Operation canceled."
      exit 1
    fi

    yq eval 'del(.services."'"$SUBDOMAIN"'" )' "$DOCKER_COMPOSE_FILE" -i
    for envFile in "$ENV_DEV_FILE" "$ENV_PROD_FILE"; do
      sed -i.bak "/$SUBDOMAIN/d" "$envFile"
      rm -f "$envFile.bak"
    done
    rm -rf "$WIKIS_DIR/$SUBDOMAIN" "$DATA_DIR/$SUBDOMAIN"
    ;;
  *)
    echo "Invalid command. Use 'add' or 'remove'."
    exit 1
    ;;
esac

echo "Operation completed successfully!"
echo "You can now run: docker-compose up -d and redeploy NGINX."
