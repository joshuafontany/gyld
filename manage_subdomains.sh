#!/usr/bin/env bash
#
# manage_subdomains.sh
# Usage: ./manage_subdomains.sh add|remove <subdomainName>
#
# This script manages MultiWikiServer subdomains by adding or removing them from:
#   - .env / .env.production (SUBDOMAINS=...)
#   - docker-compose.yml (manages services using yq)
#   - wikis/<subdomain>
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

function update_env_file() {
  local envFile="$1"
  local subdomain="$2"
  local action="$3"
  local domainSuffix="$4"

  current_value=$(dotenvx get SUBDOMAINS -f "$envFile" 2>/dev/null || echo "")
  IFS=' ' read -ra subdomains <<< "$current_value"

  if [[ "$action" == "add" ]]; then
    if [[ " ${subdomains[*]} " =~ " $subdomain.$domainSuffix " ]]; then
      echo "Subdomain already exists in $envFile"
    else
      subdomains+=("$subdomain.$domainSuffix")
    fi
  elif [[ "$action" == "remove" ]]; then
    for i in "${!subdomains[@]}"; do
      if [[ "${subdomains[i]}" == "$subdomain.$domainSuffix" ]]; then
        unset 'subdomains[i]'
      fi
    done
  fi

  new_value="${subdomains[*]}"
  dotenvx set SUBDOMAINS "$new_value" -f "$envFile"
}

case "$COMMAND" in
  add)
    echo "The following changes will be made:"
    echo "- Create directory: $WIKIS_DIR/$SUBDOMAIN"
    echo "- Add service to $DOCKER_COMPOSE_FILE"
    echo "- Append $SUBDOMAIN to SUBDOMAINS in .env and .env.production"

    read -p "Proceed? (y/N) " CONFIRM
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
      echo "Operation canceled."
      exit 1
    fi

    mkdir -p "$WIKIS_DIR/$SUBDOMAIN/tiddlers"

    cat > "$WIKIS_DIR/$SUBDOMAIN/tiddlywiki.info" <<EOF
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

    cat > "$WIKIS_DIR/$SUBDOMAIN/tiddlers/configMultiWikiServerEngine.tid" <<EOF
title: $:/config/MultiWikiServer/Engine
text: better
EOF

    LAST_PORT=$(yq e '.services.*.ports | select(. != null) | .[] | split(":")[0]' "$DOCKER_COMPOSE_FILE" | sort -nr | head -n1)
    NEXT_PORT=$((LAST_PORT + 1))

    echo "Adding service to docker-compose.yml..."
yq eval ".services[\"$SUBDOMAIN\"] = \"$(cat <<EOF
container_name: mws_$SUBDOMAIN
build:
  context: .
  dockerfile: docker/mws/Dockerfile
working_dir: /app/TiddlyWiki5
env_file:
  - .env
environment:
  - HOST=0.0.0.0
  - PORT=8080
  - WIKI_FOLDER=$SUBDOMAIN
volumes:
  - ./wikis/$SUBDOMAIN:/app/TiddlyWiki5/editions/$SUBDOMAIN:rw
ports:
  - $NEXT_PORT:8080
EOF
)\"" -i "$DOCKER_COMPOSE_FILE"

    update_env_file "$ENV_DEV_FILE" "$SUBDOMAIN" "add" "gyld.local"
    update_env_file "$ENV_PROD_FILE" "$SUBDOMAIN" "add" "gyld.app"
    ;;
  remove)
    echo "The following changes will be made:"
    echo "- Remove service block for $SUBDOMAIN from $DOCKER_COMPOSE_FILE"
    echo "- Remove $SUBDOMAIN from SUBDOMAINS in .env and .env.production"
    echo "- Delete directory: $WIKIS_DIR/$SUBDOMAIN"

    read -p "Proceed? (y/N) " CONFIRM
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
      echo "Operation canceled."
      exit 1
    fi

    if yq eval ".services[\"$SUBDOMAIN\"]" "$DOCKER_COMPOSE_FILE" >/dev/null 2>&1; then
        yq eval "del(.services[\"$SUBDOMAIN\"])" -i "$DOCKER_COMPOSE_FILE"
        echo "Docker service removed successfully."
    else
        echo "Service $SUBDOMAIN not found in docker-compose.yml."
    fi
    update_env_file "$ENV_DEV_FILE" "$SUBDOMAIN" "remove" "gyld.local"
    update_env_file "$ENV_PROD_FILE" "$SUBDOMAIN" "remove" "gyld.app"
    rm -rf "$WIKIS_DIR/$SUBDOMAIN"
    ;;
  *)
    echo "Invalid command. Use 'add' or 'remove'."
    exit 1
    ;;
esac

echo "Operation completed successfully!"
echo "You can now run: docker-compose up -d and redeploy NGINX."
