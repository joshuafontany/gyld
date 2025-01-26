#!/bin/bash

# Domains to secure
DOMAINS=("gyld.app" "www.gyld.app" "gyld.social" "www.gyld.social")
EMAIL="your-email@example.com"

# Function to install Certbot and dependencies
install_certbot() {
    echo "Installing Certbot and NGINX plugin..."
    sudo apt update
    sudo apt install -y certbot python3-certbot-nginx
}

# Function to obtain SSL certificates
obtain_certificates() {
    echo "Obtaining SSL certificates for domains: ${DOMAINS[*]}"
    sudo certbot --nginx -d "${DOMAINS[@]}" --email "$EMAIL" --agree-tos --no-eff-email --redirect
}

# Function to set up automatic renewal
setup_renewal() {
    echo "Setting up automatic renewal..."
    sudo systemctl enable certbot.timer
    sudo systemctl start certbot.timer
    echo "Testing renewal..."
    sudo certbot renew --dry-run
}

# Function to update NGINX configuration
update_nginx_config() {
    echo "Updating NGINX configuration for SSL..."
    sudo sed -i 's/listen 80;/listen 443 ssl;/' /etc/nginx/sites-available/gyld
    sudo sed -i "s|ssl_certificate .*|ssl_certificate /etc/letsencrypt/live/${DOMAINS[0]}/fullchain.pem;|" /etc/nginx/sites-available/gyld
    sudo sed -i "s|ssl_certificate_key .*|ssl_certificate_key /etc/letsencrypt/live/${DOMAINS[0]}/privkey.pem;|" /etc/nginx/sites-available/gyld
    sudo systemctl restart nginx
}

# Execute functions
install_certbot
obtain_certificates
setup_renewal
update_nginx_config

echo "SSL certificate setup completed successfully."
