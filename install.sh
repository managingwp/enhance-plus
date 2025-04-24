#!/usr/bin/env bash
# This script installs enhance-plus
REPO_URL="https://github.com/managingwp/enhance-plus.git"
REPO_DIR="/usr/local/sbin/enhance-plus"

# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "Please run as root"
    exit 1
fi

# Check if the directory already exists
if [[ -d $REPO_DIR ]]; then
    echo "Directory $REPO_DIR already exists. Please remove it first."
    exit 1
else
    # Clone the repository
    git clone $REPO_URL $REPO_DIR
    if [[ $? -ne 0 ]]; then
        echo "Failed to clone the repository"
        exit 1
    fi
fi

