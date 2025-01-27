#!/bin/bash

# setup_certbot_ssl.sh
# This script configures SSL certificates for production via certbot + nginx

set -e

# Pull from environment (must be loaded by dotenvx or otherwise)
: "${PRIMARY_DOMAIN:?Need to set PRIMARY_DOMAIN}"
: "${WWW_DOMAIN:?Need to set WWW_DOMAIN}"
: "${SUBDOMAINS:?Need to set SUBDOMAINS}"
: "${SSL_EMAIL:?Need to set SSL_EMAIL}"

install_certbot() {
    echo "Installing Certbot and NGINX plugin..."
    sudo apt-get update
    sudo apt-get install -y certbot python3-certbot-nginx
}

obtain_certificates() {
    echo "Building list of domains for Certbot..."

    # Start with primary + www
    DOMAIN_ARGS=("-d" "$PRIMARY_DOMAIN" "-d" "$WWW_DOMAIN")

    # Add each subdomain
    IFS=' ' read -ra SUBDOMAIN_ARRAY <<< "$SUBDOMAINS"
    for SD in "${SUBDOMAIN_ARRAY[@]}"; do
        DOMAIN_ARGS+=("-d")
        DOMAIN_ARGS+=("$SD")
    done

    echo "Requesting certificates for: ${DOMAIN_ARGS[*]}"
    # Now run certbot with all domain args
    sudo certbot --nginx \
      "${DOMAIN_ARGS[@]}" \
      --email "$SSL_EMAIL" \
      --agree-tos \
      --no-eff-email \
      --redirect
}

setup_renewal() {
    echo "Setting up automatic renewal..."
    sudo systemctl enable certbot.timer
    sudo systemctl start certbot.timer
    echo "Testing renewal..."
    sudo certbot renew --dry-run
}

# We'll skip the "update_nginx_config" step because we dynamically generate
# NGINX from environment. But if you do want to forcibly inject cert paths,
# you could do that here. Certbot --nginx typically does it automatically.

install_certbot
obtain_certificates
setup_renewal

echo "SSL certificate setup completed successfully."
