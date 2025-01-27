#!/usr/bin/env bash

set -e

TEST_SUBDOMAIN="automatedtest"
ENV_DEV_FILE=".env"
ENV_PROD_FILE=".env.production"
DOCKER_COMPOSE_FILE="docker-compose.yml"
WIKIS_DIR="wikis/$TEST_SUBDOMAIN"
DATA_DIR="data/$TEST_SUBDOMAIN"
DOMAIN_DEV="$TEST_SUBDOMAIN.gyld.local"
DOMAIN_PROD="$TEST_SUBDOMAIN.gyld.app"

# Function to check if a string is in a file
function check_env_file() {
  local envFile="$1"
  local value="$2"
  dotenvx get SUBDOMAINS -f "$envFile" | grep -q "$value"
}

# Step 1: Add the subdomain
echo "Testing subdomain addition..."
bash manage_subdomains.sh add "$TEST_SUBDOMAIN" <<< "y"

# Verify directory creation
if [[ -d "$WIKIS_DIR" && -d "$DATA_DIR" ]]; then
  echo "Directories created successfully."
else
  echo "Directory creation failed."
  exit 1
fi

# Verify .env files contain subdomain
if check_env_file "$ENV_DEV_FILE" "$DOMAIN_DEV" && check_env_file "$ENV_PROD_FILE" "$DOMAIN_PROD"; then
  echo "Environment files updated successfully."
else
  echo "Failed to update environment files."
  exit 1
fi

# Verify docker-compose.yml contains the service
if yq e ".services.$TEST_SUBDOMAIN" "$DOCKER_COMPOSE_FILE" >/dev/null; then
  echo "Docker service added successfully."
else
  echo "Failed to add service in docker-compose.yml."
  exit 1
fi

# Step 2: Remove the subdomain
echo "Testing subdomain removal..."
bash manage_subdomains.sh remove "$TEST_SUBDOMAIN" <<< "y"

# Verify directory removal
if [[ ! -d "$WIKIS_DIR" && ! -d "$DATA_DIR" ]]; then
  echo "Directories removed successfully."
else
  echo "Directory removal failed."
  exit 1
fi

# Verify .env files do not contain subdomain
if ! check_env_file "$ENV_DEV_FILE" "$DOMAIN_DEV" && ! check_env_file "$ENV_PROD_FILE" "$DOMAIN_PROD"; then
  echo "Environment files cleaned up successfully."
else
  echo "Failed to clean up environment files."
  exit 1
fi

# Verify docker-compose.yml service removed
if ! yq e ".services.$TEST_SUBDOMAIN" "$DOCKER_COMPOSE_FILE" >/dev/null 2>&1; then
  echo "Docker service removed successfully."
else
  echo "Failed to remove service from docker-compose.yml."
  exit 1
fi

echo "Subdomain management test passed successfully!"
