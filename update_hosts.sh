#!/bin/bash

# Define variables
# hostname -I | awk '{print $1}'
NGINX_IP="172.20.44.97"  # Replace with your actual NGINX server IP
DOMAINS=("gyld.local" "www.gyld.local" "sdm.gyld.local" "silat.gyld.local")  # Replace with your app domains
HOSTS_FILE_LINUX="/etc/hosts"
HOSTS_FILE_WIN="/mnt/c/Windows/System32/drivers/etc/hosts"
BACKUP_SUFFIX=".bak"

# Function to add entries to the hosts file
add_entries() {
    echo "Updating hosts file for WSL and Windows 11..."
    
    # Backup the original files if not already backed up
    if [ ! -f "${HOSTS_FILE_LINUX}${BACKUP_SUFFIX}" ]; then
        sudo cp "$HOSTS_FILE_LINUX" "${HOSTS_FILE_LINUX}${BACKUP_SUFFIX}"
    fi
    
    if [ ! -f "${HOSTS_FILE_WIN}${BACKUP_SUFFIX}" ]; then
        cp "$HOSTS_FILE_WIN" "${HOSTS_FILE_WIN}${BACKUP_SUFFIX}"
    fi

    # Add new entries
    for domain in "${DOMAINS[@]}"; do
        echo "$NGINX_IP $domain" | sudo tee -a "$HOSTS_FILE_LINUX" > /dev/null
        echo "$NGINX_IP $domain" >> "$HOSTS_FILE_WIN"
    done

    echo "Hosts files updated successfully!"
}

# Function to remove added entries
remove_entries() {
    echo "Reverting changes in hosts files..."

    # Restore original hosts files from backup
    if [ -f "${HOSTS_FILE_LINUX}${BACKUP_SUFFIX}" ]; then
        sudo mv "${HOSTS_FILE_LINUX}${BACKUP_SUFFIX}" "$HOSTS_FILE_LINUX"
    fi

    if [ -f "${HOSTS_FILE_WIN}${BACKUP_SUFFIX}" ]; then
        mv "${HOSTS_FILE_WIN}${BACKUP_SUFFIX}" "$HOSTS_FILE_WIN"
    fi

    echo "Hosts files reverted to original state."
}

# User interaction
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
