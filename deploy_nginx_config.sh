#!/bin/bash

# deploy_nginx_config.sh
# Usage: bash deploy_nginx_config.sh [dev|production]
#
# Reads port mappings from docker-compose.yml for each subdomain.

set -e

# Load environment variables (if they're not already loaded, ensure you call with dotenvx run)
: "${PRIMARY_DOMAIN:?Need to set PRIMARY_DOMAIN}"
: "${WWW_DOMAIN:?Need to set WWW_DOMAIN}"
: "${SUBDOMAINS:?Need to set SUBDOMAINS}"
: "${SSL_EMAIL:?Need to set SSL_EMAIL}" # used by certbot, not mandatory for dev but we keep it consistent

ENVIRONMENT="$1"
if [ -z "$ENVIRONMENT" ]; then
  echo "Usage: $0 [dev|production]"
  exit 1
fi

DOCKER_COMPOSE_FILE="docker-compose.yml"

# NGINX config paths
NGINX_AVAILABLE_DIR=/etc/nginx/sites-available
NGINX_ENABLED_DIR=/etc/nginx/sites-enabled
NGINX_CONFIG_FILE=$NGINX_AVAILABLE_DIR/gyld

# Create directories if they don't exist
sudo mkdir -p "$NGINX_AVAILABLE_DIR" "$NGINX_ENABLED_DIR"

# Make sure NGINX is installed
if ! command -v nginx >/dev/null 2>&1; then
  echo "NGINX is not installed. Please install it first."
  exit 1
fi

echo "Deploying NGINX configuration for environment: $ENVIRONMENT"
echo "Primary Domain: $PRIMARY_DOMAIN"
echo "WWW Domain: $WWW_DOMAIN"
echo "Subdomains: $SUBDOMAINS"
echo "Reading port mappings from $DOCKER_COMPOSE_FILE"

########################################
# FUNCTION to parse docker-compose.yml
# for the host port mapping under each subdomain service
########################################
# We look for a service block named, for example:
#   sdm:
#     ports:
#       - "8081:8080"
#
# Then extract the "8081" portion.
function get_host_port_from_compose() {
  local subdomainService="$1"
  local dcFile="$2"
  # default/empty if not found
  local hostPort=""

  # AWK logic:
  # 1. Find a line starting at column 0 with "<subdomainService>:" (like "sdm:")
  # 2. Switch on "found=1" once we enter that block
  # 3. For each subsequent line, if we see a line matching "[0-9]+:8080" we extract the number
  # 4. Stop searching once we hit another top-level line (another service) or networks:
  #
  # We'll store the captured port in hostPort and return it.
  hostPort=$(
    awk -v sd="$subdomainService" '
      BEGIN {found=0}
      # A top-level line with "sd:" (no indentation) or "sd:" with indentation=0
      # or "sd:" preceded by up to 2 spaces is enough for YAML. Adjust as needed.
      # We remove trailing colon to compare.
      /^[^ ]/ {
        # If already found=1 and we see a new top-level line, we stop.
        if(found==1) { exit }
        # Check if this is the line matching subdomain:
        # e.g. "sdm:" => name=sdm
        # If it matches, set found=1
        split($1, arr, ":")
        if(arr[1] == sd) {
          found=1
        }
        next
      }
      # If we are in the block for subdomain service, look for port lines
      found==1 && /[0-9]+:8080/ {
        match($0, /"([0-9]+):8080"/, m)
        if(m[1] != "") {
          print m[1]
          exit
        }
      }
    ' "$dcFile"
  )
  echo "$hostPort"
}

########################################
# 1) MAIN SERVER BLOCK FOR PRIMARY/WWW
########################################

# We assume the "admin" container is on 8080 internally -> 8080 externally
# or you can parse it from Docker Compose if you like. For simplicity, we
# hardcode the admin wiki as 127.0.0.1:8080 in this script.
MAIN_HTTP_BLOCK="server {
    listen 80;
    server_name $PRIMARY_DOMAIN $WWW_DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}"

# For production, also define SSL block (listening on 443)
MAIN_HTTPS_BLOCK=""
if [ "$ENVIRONMENT" = "production" ]; then
MAIN_HTTPS_BLOCK="server {
    listen 443 ssl;
    server_name $PRIMARY_DOMAIN $WWW_DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$PRIMARY_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$PRIMARY_DOMAIN/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}"
fi

########################################
# 2) SUBDOMAIN SERVER BLOCKS
########################################
SUBDOMAIN_CONFIG=""
IFS=' ' read -ra SUBDOMAIN_ARRAY <<< "$SUBDOMAINS"

for FULL_SUBDOMAIN in "${SUBDOMAIN_ARRAY[@]}"; do
  # We assume the subdomain "sdm.gyld.local" or "sdm.gyld.app" => the service is named "sdm"
  # Trim off everything after the first dot to get "sdm"
  SUBDOMAIN_SERVICE_NAME=$(echo "$FULL_SUBDOMAIN" | cut -d '.' -f 1)

  # Fetch the "host port" from docker-compose
  HOST_PORT=$(get_host_port_from_compose "$SUBDOMAIN_SERVICE_NAME" "$DOCKER_COMPOSE_FILE")
  if [[ -z "$HOST_PORT" ]]; then
    echo "Warning: Could not find a port mapping for '$SUBDOMAIN_SERVICE_NAME' in $DOCKER_COMPOSE_FILE."
    echo "Skipping subdomain block for $FULL_SUBDOMAIN."
    continue
  fi

  SUBDOMAIN_HTTP_BLOCK="server {
      listen 80;
      server_name $FULL_SUBDOMAIN;

      location / {
          proxy_pass http://127.0.0.1:${HOST_PORT};
          proxy_set_header Host \$host;
          proxy_set_header X-Real-IP \$remote_addr;
          proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      }
  }"

  # For production, add SSL block for each subdomain
  SUBDOMAIN_HTTPS_BLOCK=""
  if [ "$ENVIRONMENT" = "production" ]; then
  SUBDOMAIN_HTTPS_BLOCK="server {
      listen 443 ssl;
      server_name $FULL_SUBDOMAIN;

      ssl_certificate /etc/letsencrypt/live/$PRIMARY_DOMAIN/fullchain.pem;
      ssl_certificate_key /etc/letsencrypt/live/$PRIMARY_DOMAIN/privkey.pem;

      location / {
          proxy_pass http://127.0.0.1:${HOST_PORT};
          proxy_set_header Host \$host;
          proxy_set_header X-Real-IP \$remote_addr;
          proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      }
  }"
  fi

  SUBDOMAIN_CONFIG="$SUBDOMAIN_CONFIG
$SUBDOMAIN_HTTP_BLOCK
$SUBDOMAIN_HTTPS_BLOCK
"
done

########################################
# 3) COMBINE & WRITE FINAL NGINX CONFIG
########################################
echo "Creating $NGINX_CONFIG_FILE with combined configuration..."

sudo bash -c "cat > $NGINX_CONFIG_FILE" <<EOF
# Generated by deploy_nginx_config.sh for $ENVIRONMENT
# Main domain + WWW
$MAIN_HTTP_BLOCK
$MAIN_HTTPS_BLOCK

# Subdomains
$SUBDOMAIN_CONFIG
EOF

# Symlink into sites-enabled
sudo ln -sf "$NGINX_CONFIG_FILE" "$NGINX_ENABLED_DIR/gyld"

# Validate and reload
echo "Testing NGINX configuration..."
sudo nginx -t
echo "Reloading NGINX..."
sudo systemctl reload nginx

echo "NGINX configuration applied successfully for environment=$ENVIRONMENT."
