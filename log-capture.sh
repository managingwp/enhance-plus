#!/bin/env bash
SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
[[ $EUID -ne 0 ]] && echo "Please run as root" && exit 1
CMD="$1"
FORCE=0

_running () { echo -e "\e[1;34m${*}\e[0m"; }
_running2 () { echo -e "\e[1;30m-- ${*}\e[0m"; }
_success () { echo -e "\e[1;32m${*}\e[0m"; }
_error () { echo -e "\e[1;31m${*}\e[0m"; }

_usage() {
    echo "Invalid argument: $CMD"
    echo "Usage: $0 <install|uninstall>"    
    echo
    echo "Commands:"
    echo "  install   Install the enhance-log-capture service and logrotate configuration"
    echo "  uninstall Remove the enhance-log-capture service and logrotate configuration"
    echo
    echo "Options:"
    echo "  -h, --help Show this help message"
    echo "  -f, --force Force the installation or uninstallation"
    echo
    echo "Example: $0 install"
    exit 1
}

_install_service () {
    cp "${SCRIPT_PATH}/$SYSTEMD_FILE" "$SYSTEMD_FILE_PATH"
    sudo systemctl daemon-reexec
    sudo systemctl enable --now $SYSTEMD_FILE
    sudo systemctl start $SYSTEMD_FILE
}
_uninstall_service() {
    sudo systemctl stop enhance-log-capture.service
    sudo systemctl disable enhance-log-capture.service
    sudo rm -f $SYSTEMD_FILE_PATH
}

_install_logrotate() {
    cp "${SCRIPT_PATH}/$LOGROTATE_FILE" "$LOGROTATE_FILE_PATH"
    sudo chmod 644 $LOGROTATE_FILE_PATH
}

_pre-flight () {
    # -- Check if inotifywait is installed
    if ! command -v inotifywait &> /dev/null; then
        _error "inotifywait could not be found, please install inotify-tools"
        _loading2 "Installing inotify-tools"
        sudo apt-get install -y inotify-tools
        if [[ $? -ne 0 ]]; then
            _error "Failed to install inotify-tools"
            exit 1
        fi
    fi    
}

_running "Installing enhance-log-capture"
SYSTEMD_FILE="enhance-log-capture.service"
SYSTEMD_FILE_PATH="/etc/systemd/system/enhance-log-capture.service"
LOGROTATE_FILE="enhance-log-capture.logrotate"
LOGROTATE_FILE_PATH="/etc/logrotate.d/enhance-log-capture"

# -- Args
while [[ $# -gt 0 ]]; do
    case $1 in
        install|uninstall)
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

# -- Install
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
        # -- Check md5 hash
        HASH_SYSTEMD_FILE=$(md5sum "$SCRIPT_PATH/$SYSTEMD_FILE" | awk '{print $1}')
        HASH_SYSTEMD_FILE_PATH=$(md5sum "$SYSTEMD_FILE_PATH" | awk '{print $1}')
        if [[ $HASH_SYSTEMD_FILE != $HASH_SYSTEMD_FILE_PATH ]]; then
            _running2 "File $SYSTEMD_FILE_PATH exists, but the hash does not match, installing"
            _install_service
        else
            _running2 "File $SYSTEMD_FILE_PATH exists, and the hash matches, skipping to next step"
        fi        
    fi
    
    # -- Logrotate configuration
    _running "Installing logrotate configuration."
    if [[ ! -f $LOGROTATE_FILE_PATH ]]; then
        _running2 "Installing logrotate configuration $LOGROTATE_FILE at $LOGROTATE_FILE_PATH"
        _install_logrotate
    elif [[ $FORCE == 1 ]]; then
        _running2 "Force installing logrotate configuration $LOGROTATE_FILE at $LOGROTATE_FILE_PATH"
        _install_logrotate
    else
        # -- Check md5 hash
        HASH_LOGROTATE_FILE=$(md5sum "$SCRIPT_PATH/$LOGROTATE_FILE" | awk '{print $1}')
        HASH_LOGROTATE_FILE_PATH=$(md5sum "$LOGROTATE_FILE_PATH" | awk '{print $1}')
        if [[ $HASH_LOGROTATE_FILE != $HASH_LOGROTATE_FILE_PATH ]]; then
            _running2 "File $LOGROTATE_FILE_PATH exists, but the hash does not match, installing"
            _install_logrotate
        else
            _running2 "File $LOGROTATE_FILE_PATH exists, and the hash matches, skipping to next step"
        fi
    fi

    _success "* Installation complete *"
# -- Uninstall
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

    if [[ -f $LOGROTATE_FILE_PATH ]]; then
        _running2 "Removing $LOGROTATE_FILE at $LOGROTATE_FILE_PATH"
        sudo rm -f $LOGROTATE_FILE_PATH
    elif [[ $FORCE == 1 ]]; then
        _running2 "Force removing $LOGROTATE_FILE at $LOGROTATE_FILE_PATH"
        sudo rm -f $LOGROTATE_FILE_PATH
    else
        _running2 "Logrotate configuration not found at $LOGROTATE_FILE_PATH, skipping"
    fi

    exit 0


else
    echo "Invalid command: $CMD"
    _usage
    exit 1
fi
