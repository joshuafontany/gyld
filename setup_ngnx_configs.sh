#!/bin/bash

# Define project directory
PROJECT_DIR=~/github/gyld
NGINX_CONFIG_DIR="$PROJECT_DIR/nginx-configs"

# Create nginx-configs directory if it doesn't exist
mkdir -p $NGINX_CONFIG_DIR

# Create NGINX configuration for local development
cat <<EOL > $NGINX_CONFIG_DIR/nginx.dev.conf
server {
    listen 80;
    server_name gyld.local;

    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location /auth {
        proxy_pass http://localhost:2583;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOL

# Create NGINX configuration for production deployment
cat <<EOL > $NGINX_CONFIG_DIR/nginx.prod.conf
server {
    listen 80;
    server_name gyld.app;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location /auth {
        proxy_pass http://127.0.0.1:2583;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    listen 443 ssl;
    ssl_certificate /etc/letsencrypt/live/gyld.app/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/gyld.app/privkey.pem;
}
EOL

echo "NGINX configurations have been created in $NGINX_CONFIG_DIR"
