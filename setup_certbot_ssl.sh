#!/bin/bash

# Domains to secure (array)
DOMAINS=(${SSL_DOMAINS:-"gyld.app www.gyld.app"})
EMAIL="${SSL_EMAIL:-gyld.app@example.com}"

install_certbot() {
    ...
}

obtain_certificates() {
    echo "Obtaining SSL certificates for domains: ${DOMAINS[*]}"
    sudo certbot --nginx -d "${DOMAINS[@]}" \
        --email "$EMAIL" \
        --agree-tos \
        --no-eff-email \
        --redirect
}

setup_renewal() {
    ...
}

update_nginx_config() {
    # Use the first domain in DOMAINS to set the certificate path
    local main_domain="${DOMAINS[0]}"
    ...
    sudo sed -i "s|ssl_certificate .*$|ssl_certificate /etc/letsencrypt/live/${main_domain}/fullchain.pem;|" /etc/nginx/sites-available/gyld
    sudo sed -i "s|ssl_certificate_key .*$|ssl_certificate_key /etc/letsencrypt/live/${main_domain}/privkey.pem;|" /etc/nginx/sites-available/gyld
    ...
}

install_certbot
obtain_certificates
setup_renewal
update_nginx_config

echo "SSL certificate setup completed successfully."
