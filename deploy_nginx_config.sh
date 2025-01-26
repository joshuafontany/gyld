#!/bin/bash

# Pull in environment variables (if not set, use defaults)
CONFIG_DIR="${CONFIG_DIR:-$HOME/github/gyld/nginx-configs}"
NGINX_AVAILABLE_DIR="${NGINX_AVAILABLE_DIR:-/etc/nginx/sites-available}"
NGINX_ENABLED_DIR="${NGINX_ENABLED_DIR:-/etc/nginx/sites-enabled}"

# Validate input
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 [dev|production]"
    exit 1
fi

ENVIRONMENT="$1"

if [ "$ENVIRONMENT" == "dev" ]; then
    # Use environment variables or fallback to defaults
    CONFIG_FILE="${CONFIG_FILE_DEV:-nginx.dev.conf}"
    DOMAIN="${DOMAIN_DEV:-gyld.local}"
elif [ "$ENVIRONMENT" == "production" ]; then
    CONFIG_FILE="${CONFIG_FILE_PROD:-nginx.production.conf}"
    DOMAIN="${DOMAIN_PROD:-gyld.app}"
else
    echo "Invalid argument. Use 'dev' or 'production'."
    exit 1
fi

echo "Deploying $CONFIG_FILE to NGINX for domain: $DOMAIN"

# Check if NGINX is installed
if ! command -v nginx &> /dev/null; then
    echo "NGINX is not installed. Please install it first."
    exit 1
fi

sudo mkdir -p "$NGINX_AVAILABLE_DIR" "$NGINX_ENABLED_DIR"

# Copy config to sites-available and enable it
sudo cp "$CONFIG_DIR/$CONFIG_FILE" "$NGINX_AVAILABLE_DIR/gyld"
sudo ln -sf "$NGINX_AVAILABLE_DIR/gyld" "$NGINX_ENABLED_DIR/gyld"

# Test and restart NGINX
sudo nginx -t && sudo service nginx restart

if [ $? -eq 0 ]; then
    echo "NGINX configuration applied successfully for $DOMAIN."
else
    echo "Error in NGINX configuration. Please check manually."
    exit 1
fi
