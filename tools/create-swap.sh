#!/usr/bin/env bash
# This script creates a swap file of a specified size and enables it.

_get_memory () {
    local mem_size
    mem_size=$(free -h | awk '/^Mem:/ {print $2}')
    echo "Total memory size: $mem_size"
}

_usage () {
    echo "Usage: $0 <size>"
    echo "Example: $0 2G"    
    _get_memory
    exit 1
}

_create_swap () {
    local swap_size=$1
    local swap_file="/swapfile"

    # Check if the swap file already exists
    if [ -f "$swap_file" ]; then
        echo "Swap file already exists. Please remove it first."
        exit 1
    fi

    # Create the swap file
    sudo fallocate -l "$swap_size" "$swap_file"
    
    # Set the correct permissions
    sudo chmod 600 "$swap_file"
    
    # Set up the swap area
    sudo mkswap "$swap_file"
    
    # Enable the swap file
    sudo swapon "$swap_file"
    
    # Add to fstab for persistence across reboots
    echo "$swap_file none swap sw 0 0" | sudo tee -a /etc/fstab
    
    echo "Swap file of size $swap_size created and enabled."
}

# Check if the user provided a size argument
if [ $# -ne 1 ]; then
    _usage
fi
# Validate the size argument
if [[ ! $1 =~ ^[0-9]+[KMG]$ ]]; then
    echo "Invalid size format. Use K, M, or G for kilobytes, megabytes, or gigabytes."
    _usage
fi
# Call the function to create swap
_create_swap "$1"
# Check if the swap was created successfully
if swapon --show | grep -q "/swapfile"; then
    echo "Swap file created successfully."
else
    echo "Failed to create swap file."
    exit 1
fi
