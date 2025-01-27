#!/bin/bash

# deploy_nginx_config.sh
# Usage: bash deploy_nginx_config.sh [dev|production]
#
# Reads port mappings from docker-compose.yml for each subdomain.

set -e

# Load environment variables (ensure you call with dotenvx run)
: "${PRIMARY_DOMAIN:?Need to set PRIMARY_DOMAIN}"
: "${WWW_DOMAIN:?Need to set WWW_DOMAIN}"
: "${SUBDOMAINS:?Need to set SUBDOMAINS}"
: "${SSL_EMAIL:?Need to set SSL_EMAIL}" # Used by certbot, not mandatory for dev but kept for consistency

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

# Ensure NGINX is installed
if ! command -v nginx >/dev/null 2>&1; then
  echo "NGINX is not installed. Please install it first."
  exit 1
fi

# Ensure `yq` is installed for YAML parsing
if ! command -v yq >/dev/null 2>&1; then
  echo "yq command not found. Please install it: sudo apt install yq"
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
function get_host_port_from_compose() {
  local subdomainService="$1"
  local dcFile="$2"

  # Extract the first exposed host port from the docker-compose file using yq
  local hostPort=$(yq e ".services.$subdomainService.ports[0]" "$dcFile" | cut -d':' -f1)

  # If yq returns null or empty, set empty value
  if [[ "$hostPort" == "null" || -z "$hostPort" ]]; then
    echo ""
  else
    echo "$hostPort"
  fi
}

########################################
# 1) MAIN SERVER BLOCK FOR PRIMARY/WWW
########################################

# Hardcoding admin container to 8080
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

# For production, add SSL configuration
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
  # Extract subdomain service name (e.g., "sdm.gyld.local" => "sdm")
  SUBDOMAIN_SERVICE_NAME=$(echo "$FULL_SUBDOMAIN" | cut -d '.' -f 1)

  # Fetch the host port from docker-compose.yml
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

  # For production, add SSL block
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

# Validate and reload NGINX
echo "Testing NGINX configuration..."
sudo nginx -t
echo "Reloading NGINX..."
sudo systemctl reload nginx

echo "NGINX configuration applied successfully for environment=$ENVIRONMENT."
