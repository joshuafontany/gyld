#!/bin/bash

# Auto-detect WSL IP address
NGINX_IP=$(hostname -I | awk '{print $1}')
if [[ -z "$NGINX_IP" ]]; then
    echo "Failed to detect WSL IP address."
    exit 1
fi

# Check required environment variables
if [[ -z "$PRIMARY_DOMAIN" || -z "$WWW_DOMAIN" || -z "$SUBDOMAINS" ]]; then
    echo "Missing required environment variables: PRIMARY_DOMAIN, WWW_DOMAIN, SUBDOMAINS"
    exit 1
fi

# Construct domain list
DOMAINS=("$PRIMARY_DOMAIN" "$WWW_DOMAIN")
IFS=' ' read -ra SUBDOMAIN_ARRAY <<< "$SUBDOMAINS"

for sub in "${SUBDOMAIN_ARRAY[@]}"; do
    DOMAINS+=("$sub")
done

# File paths for hosts management
HOSTS_FILE_LINUX="/etc/hosts"
HOSTS_FILE_WIN="/mnt/c/Windows/System32/drivers/etc/hosts"
BACKUP_SUFFIX=".bak"

# Function to add entries to hosts files
add_entries() {
    echo "Updating hosts file for WSL and Windows 11..."
    
    # Backup original files if not already backed up
    if [ ! -f "${HOSTS_FILE_LINUX}${BACKUP_SUFFIX}" ]; then
        sudo cp "$HOSTS_FILE_LINUX" "${HOSTS_FILE_LINUX}${BACKUP_SUFFIX}"
    fi
    
    if [ ! -f "${HOSTS_FILE_WIN}${BACKUP_SUFFIX}" ]; then
        cp "$HOSTS_FILE_WIN" "${HOSTS_FILE_WIN}${BACKUP_SUFFIX}"
    fi

    # Remove old entries first
    remove_entries

    # Add new entries
    for domain in "${DOMAINS[@]}"; do
        echo "$NGINX_IP $domain" | sudo tee -a "$HOSTS_FILE_LINUX" > /dev/null
        echo "$NGINX_IP $domain" >> "$HOSTS_FILE_WIN"
    done

    echo "Hosts files updated successfully!"
}

# Function to remove entries from hosts files
remove_entries() {
    echo "Reverting changes in hosts files..."

    # Restore original hosts files from backup
    if [ -f "${HOSTS_FILE_LINUX}${BACKUP_SUFFIX}" ]; then
        sudo cp "${HOSTS_FILE_LINUX}${BACKUP_SUFFIX}" "$HOSTS_FILE_LINUX"
    fi

    if [ -f "${HOSTS_FILE_WIN}${BACKUP_SUFFIX}" ]; then
        cp "${HOSTS_FILE_WIN}${BACKUP_SUFFIX}" "$HOSTS_FILE_WIN"
    fi

    echo "Hosts files reverted to original state."
}

# Script usage handling
case "$1" in
    set)
        add_entries
        ;;
    unset)
        remove_entries
        ;;
    *)
        echo "Usage: $0 {set|unset}"
        exit 1
        ;;
esac
