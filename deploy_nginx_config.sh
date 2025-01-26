#!/bin/bash

CONFIG_DIR=~/github/gyld/nginx-configs
NGINX_AVAILABLE_DIR=/etc/nginx/sites-available
NGINX_ENABLED_DIR=/etc/nginx/sites-enabled

# Validate input
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 [dev|production]"
    exit 1
fi

# Check if NGINX is installed
if ! command -v nginx &> /dev/null; then
    echo "NGINX is not installed. Please install it first."
    exit 1
fi

# Ensure required directories exist
sudo mkdir -p $NGINX_AVAILABLE_DIR $NGINX_ENABLED_DIR

# Set configuration file based on argument
if [ "$1" == "dev" ]; then
    CONFIG_FILE="nginx.dev.conf"
    DOMAIN="gyld.local"
elif [ "$1" == "production" ]; then
    CONFIG_FILE="nginx.prod.conf"
    DOMAIN="gyld.app"
else
    echo "Invalid argument. Use 'dev' or 'production'."
    exit 1
fi

# Copy the appropriate configuration
echo "Deploying $CONFIG_FILE to NGINX..."

sudo cp $CONFIG_DIR/$CONFIG_FILE $NGINX_AVAILABLE_DIR/gyld
sudo ln -sf $NGINX_AVAILABLE_DIR/gyld $NGINX_ENABLED_DIR/gyld

# Test and restart NGINX
sudo nginx -t && sudo service nginx restart

if [ $? -eq 0 ]; then
    echo "NGINX configuration applied successfully for $DOMAIN."
else
    echo "Error in NGINX configuration. Please check manually."
    exit 1
fi
