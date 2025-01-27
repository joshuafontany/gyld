#!/bin/bash

# deploy_nginx_config.sh
# Usage: bash deploy_nginx_config.sh [dev|production]

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

########################################
# 1) MAIN SERVER BLOCK FOR PRIMARY/WWW
########################################
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
# We'll map each subdomain to an incrementing port: 8081, 8082, ...
# (or any scheme you prefer)
PORT_BASE=8081
SUBDOMAIN_CONFIG=""
IFS=' ' read -ra SUBDOMAIN_ARRAY <<< "$SUBDOMAINS"
for SUBDOMAIN in "${SUBDOMAIN_ARRAY[@]}"; do

  SUBDOMAIN_HTTP_BLOCK="server {
      listen 80;
      server_name $SUBDOMAIN;

      location / {
          proxy_pass http://127.0.0.1:${PORT_BASE};
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
      server_name $SUBDOMAIN;

      ssl_certificate /etc/letsencrypt/live/$PRIMARY_DOMAIN/fullchain.pem;
      ssl_certificate_key /etc/letsencrypt/live/$PRIMARY_DOMAIN/privkey.pem;

      location / {
          proxy_pass http://127.0.0.1:${PORT_BASE};
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
  PORT_BASE=$((PORT_BASE+1))
done

########################################
# 3) COMBINE & WRITE FINAL NGINX CONFIG
########################################
echo "Creating $NGINX_CONFIG_FILE with combined configuration..."
sudo 
