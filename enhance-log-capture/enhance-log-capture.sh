#!/bin/env bash
# log-capture.sh - Script to manage the enhance-log-capture service and logrotate configuration
# This script requires root privileges to run.

# =============================================================================
# -- Variables
# =============================================================================
VERSION="$(cat "$(dirname "$(readlink -f "$0")")/VERSION")"
SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
SYSTEMD_FILE="enhance-log-capture.service"
SYSTEMD_SERVICE_NAME="enhance-log-capture.service"
SYSTEMD_FILE_PATH="/etc/systemd/system/enhance-log-capture.service"
LOGROTATE_FILE="enhance-log-capture.logrotate"
LOGROTATE_FILE_PATH="/etc/logrotate.d/enhance-log-capture"


[[ $EUID -ne 0 ]] && echo "Please run as root" && exit 1
CMD="$1"
FORCE=0

# =============================================================================
# -- Functions
# =============================================================================

_running () { echo -e "\e[1;34m${*}\e[0m"; }
_running2 () { echo -e "\e[1;30m-- ${*}\e[0m"; }
_success () { echo -e "\e[1;32m${*}\e[0m"; }
_warning () { echo -e "\e[1;33m${*}\e[0m"; }
_error () { echo -e "\e[1;31m${*}\e[0m"; }

# =====================================
# -- Usage
# =====================================
_usage() {    
    echo "Usage: $0 <install|uninstall|logrotate>"    
    echo
    echo "Commands:"
    echo "  install                 - Install the enhance-log-capture service and logrotate configuration"
    echo "  uninstall               - Remove the enhance-log-capture service and logrotate configuration"
    echo "  logrotate               - Install only the logrotate configuration"
    echo "  check-logrotate         - Check the status of the logrotate, via journalctl"
    echo
    echo "Options:"
    echo "  -h, --help Show this help message"
    echo "  -f, --force Force the installation or uninstallation"
    echo
    echo "Examples:"
    echo "  $0 install    # Install both service and logrotate"
    echo "  $0 logrotate  # Install only logrotate configuration"
    echo
    echo "Version: $VERSION"
    exit 1
}

# ======================================
# -- Install Service
# ======================================
_install_service () {
    # Create a temporary service file with the correct path    
    sed "s|SERVICE_SCRIPT_PATH_PLACEHOLDER|${SCRIPT_PATH}|g" "${SCRIPT_PATH}/$SYSTEMD_FILE" > "/tmp/$(basename $SYSTEMD_FILE)"
    cp "/tmp/$(basename $SYSTEMD_FILE)" "$SYSTEMD_FILE_PATH"
    rm "/tmp/$(basename $SYSTEMD_FILE)"
    _running2 "Service file created at $SYSTEMD_FILE_PATH"
    _running2 "Reloading systemd daemon"
    sudo systemctl daemon-reload
    _running2 "Enabling and starting service $SYSTEMD_SERVICE_NAME"
    sudo systemctl enable $SYSTEMD_SERVICE_NAME
    sudo systemctl start $SYSTEMD_SERVICE_NAME
}

# =======================================
# -- Uninstall Service
# =======================================
_uninstall_service() {
    sudo systemctl stop $SYSTEMD_SERVICE_NAME
    sudo systemctl disable $SYSTEMD_SERVICE_NAME
    sudo rm -f $SYSTEMD_FILE_PATH
}

# =======================================
# -- Install Logrotate with checks
# =======================================
_install_logrotate_with_checks() {
    _running "Installing logrotate configuration."
    if [[ ! -f $LOGROTATE_FILE_PATH ]]; then
        _running2 "Installing logrotate configuration $LOGROTATE_FILE at $LOGROTATE_FILE_PATH"
        _install_logrotate
    elif [[ $FORCE == 1 ]]; then
        _running2 "Force installing logrotate configuration $LOGROTATE_FILE at $LOGROTATE_FILE_PATH"
        _install_logrotate
    else
        # -- Check md5 hash - use a temp file to compare since we modify the source during install
        TEMP_LOGROTATE=$(mktemp)
        sed "s|LOGROTATE_SCRIPT_PATH_PLACEHOLDER|${SCRIPT_PATH}|g" "${SCRIPT_PATH}/$LOGROTATE_FILE" > "$TEMP_LOGROTATE"
        HASH_LOGROTATE_FILE=$(md5sum "$TEMP_LOGROTATE" | awk '{print $1}')
        HASH_LOGROTATE_FILE_PATH=$(md5sum "$LOGROTATE_FILE_PATH" | awk '{print $1}')
        rm -f "$TEMP_LOGROTATE"
        
        if [[ $HASH_LOGROTATE_FILE != $HASH_LOGROTATE_FILE_PATH ]]; then
            _warning "File $LOGROTATE_FILE_PATH exists, but the hash does not match, installing"
            _install_logrotate
        else
            _running2 "File $LOGROTATE_FILE_PATH exists, and the hash matches, skipping"
        fi
    fi
    
    # Show logrotate information
    echo
    _running "Logrotate Information:"
    _running2 "Configuration file: $LOGROTATE_FILE_PATH"
    _running2 "Log files rotated: /var/log/webserver_logs/*.log"
    _running2 "Rotated files moved to: /var/log/webserver_logs_archive/"
    _running2 "Test logrotate: sudo logrotate -d $LOGROTATE_FILE_PATH"
    _running2 "Force logrotate: sudo logrotate -f $LOGROTATE_FILE_PATH"
    echo
}

# =======================================
# -- Install Logrotate
# =======================================
_install_logrotate() {
    _running2 "Installing logrotate configuration $LOGROTATE_FILE at $LOGROTATE_FILE_PATH"    
    # Create a temporary logrotate file with the correct path
    sed "s|LOGROTATE_SCRIPT_PATH_PLACEHOLDER|${SCRIPT_PATH}|g" "${SCRIPT_PATH}/$LOGROTATE_FILE" > "/tmp/$(basename $LOGROTATE_FILE)"
    cp "/tmp/$(basename $LOGROTATE_FILE)" "$LOGROTATE_FILE_PATH"
    rm "/tmp/$(basename $LOGROTATE_FILE)"
    sudo chmod 644 $LOGROTATE_FILE_PATH
}

# =======================================
# -- Uninstall Logrotate
# =======================================
_uninstall_logrotate() {
    if [[ -f $LOGROTATE_FILE_PATH ]]; then
        _running2 "Removing $LOGROTATE_FILE at $LOGROTATE_FILE_PATH"
        sudo rm -f $LOGROTATE_FILE_PATH
    elif [[ $FORCE == 1 ]]; then
        _running2 "Force removing $LOGROTATE_FILE at $LOGROTATE_FILE_PATH"
        sudo rm -f $LOGROTATE_FILE_PATH
    else
        _running2 "Logrotate configuration not found at $LOGROTATE_FILE_PATH, skipping"
    fi
}

# =======================================
# -- Pre-flight checks
# =======================================
_pre-flight () {
    # -- Check if inotifywait is installed
    if ! command -v inotifywait &> /dev/null; then
        _warning "inotifywait could not be found, trying to install inotify-tools"
        _running2 "Installing inotify-tools"
        sudo apt-get install -y inotify-tools
        if [[ $? -ne 0 ]]; then
            _error "Failed to install inotify-tools"
            exit 1
        fi
    fi    
}

# =============================================================================
# -- Main script logic
# =============================================================================
while [[ $# -gt 0 ]]; do
    case $1 in
        install|uninstall|logrotate)
            CMD="$1"
            shift
            ;;        
        -h|--help)
            _usage
            exit 0
            ;;
        -f|--force)
            FORCE=1
            shift
            ;;
        *)
            echo "Invalid argument: $1"
            _usage
            exit 1
            ;;
    esac
done

_pre-flight
_running "Running from $SCRIPT_PATH"
# =============================================================
# -- Install
# =============================================================
if [[ $CMD == "install" ]]; then    
    # -- Systemd service
    _running "Installing systemd service"
    if [[ ! -f $SYSTEMD_FILE_PATH ]]; then
        _running2 "File $SYSTEMD_FILE_PATH does not exist, installing"
        _install_service
    elif [[ $FORCE == 1 ]]; then
        _running2 "Force installing systemd service"
        _install_service
    else
        # -- Check md5 hash - use a temp file to compare since we modify the source during install
        TEMP_SYSTEMD=$(mktemp)
        sed "s|SERVICE_SCRIPT_PATH_PLACEHOLDER|${SCRIPT_PATH}|g" "${SCRIPT_PATH}/$SYSTEMD_FILE" > "$TEMP_SYSTEMD"
        HASH_SYSTEMD_FILE=$(md5sum "$TEMP_SYSTEMD" | awk '{print $1}')
        HASH_SYSTEMD_FILE_PATH=$(md5sum "$SYSTEMD_FILE_PATH" | awk '{print $1}')
        rm -f "$TEMP_SYSTEMD"
        
        if [[ $HASH_SYSTEMD_FILE != $HASH_SYSTEMD_FILE_PATH ]]; then
            _warning "File $SYSTEMD_FILE_PATH exists, but the hash does not match, installing"
            _install_service
        else
            _running2 "File $SYSTEMD_FILE_PATH exists, and the hash matches, skipping to next step"
        fi        
    fi
    
    # -- Logrotate configuration
    _install_logrotate_with_checks

    _success "* Installation complete *"
    echo
    _running "Service Management Commands:"
    _running2 "Check Service status       sudo systemctl status enhance-log-capture.service"
    _running2 "View Service logs          sudo journalctl -u enhance-log-capture.service -f"
    _running2 "Check Service Enabled      sudo systemctl is-active enhance-log-capture.service"
    echo
    _running "Log File Locations:"
    _running2 "Source logs:       /var/local/enhance/webserver_logs/"
    _running2 "Archive logs:      /var/log/webserver_logs/"
    _running2 "Rotated logs       /var/log/webserver_logs_archive/"
    echo
# =============================================================
# -- Uninstall
# =============================================================
elif [[ $CMD == "uninstall" ]]; then
    _running "Uninstalling $SYSTEMD_FILE at $SYSTEMD_FILE_PATH"
    if [[ -f $SYSTEMD_FILE_PATH ]]; then
        _running2 "Removing systemd service"
        _uninstall_service
    elif [[ $FORCE == 1 ]]; then
        _running2 "Force removing systemd service"
        _uninstall_service
    else
        _running2 "Systemd service not found at $SYSTEMD_FILE_PATH, skipping"
    fi

    _uninstall_logrotate

    exit 0
# =============================================================
# -- Logrotate only
# =============================================================
elif [[ $CMD == "logrotate" ]]; then
    _running "Installing logrotate configuration only"
    _install_logrotate_with_checks    
elif [[ $CMD == "check-logrotate" ]]; then
    _running "Checking logrotate status via journalctl"
    _running2 "Use Ctrl+C to exit the log view"
    echo
    sudo journalctl -u logrotate -f
# =============================================================
# -- Invalid command
else
    echo "Invalid command: $CMD"
    _usage
    exit 1
fi
