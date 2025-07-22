#!/bin/env bash
# enhance-log-capture-rename.sh - Script to rename and archive log files based on UUID to domain mapping
# This script is intended to be run as a postrotate script in logrotate configuration.
# =============================================================================
# -- Variables
# =============================================================================
MODE=""
DRY_RUN=0
USE_ARCHIVE=0
ACTIVE_DIR="/var/log/webserver_logs"
ARCHIVE_DIR="/var/log/webserver_logs_archive"

# ==============================================================================
# -- Functions
# ==============================================================================
_running () { echo -e "\e[1;34m${*}\e[0m"; }
_running2 () { echo -e "\e[1;30m-- ${*}\e[0m"; }
_success () { echo -e "\e[1;32m${*}\e[0m"; }
_warning () { echo -e "\e[1;33m${*}\e[0m"; }
_error () { echo -e "\e[1;31m${*}\e[0m"; }
_usage() {
    echo "Usage: $0 <rename|dryrun> [-a]"
    echo
    echo "Commands:"
    echo "  rename   Rename and archive log files based on UUID to domain mapping"
    echo "  dryrun   Show what would be done without making any changes"
    echo
    echo "Options:"
    echo "  -a       Move files to archive directory (default: rename in current directory)"
    echo
    echo "Examples:"
    echo "  $0 rename        # Rename files in current directory"
    echo "  $0 rename -a     # Rename and move files to archive directory"
    echo "  $0 dryrun -a     # Show what would be done with archive option"
    exit 1
}
# =====================================
# -- Pre-flight checks
# ======================================
_pre_flight() {
    # -- Check if the active directory exists
    if [ ! -d "$ACTIVE_DIR" ]; then
        _error "Active directory $ACTIVE_DIR does not exist."
        exit 1
    fi

    # -- Confirm command enhance-cli is installed
    if ! command -v enhance-cli &> /dev/null; then
        echo "enhance-cli could not be found. Please install it first."
        exit 1
    fi
}

# =====================================
# -- Rename log files
# ======================================
_rename_log_files() {
    # This should be your mapping from UUID → domain
    # Ideally load from a file or a DB in production

    # -- Determine target directory
    if [[ $USE_ARCHIVE == 1 ]]; then
        TARGET_DIR="$ARCHIVE_DIR"
        _running "Moving files to archive directory: $TARGET_DIR"
        # -- Create archive directory if it doesn't exist
        if [ ! -d "$TARGET_DIR" ]; then
            _running2 "Creating archive directory: $TARGET_DIR"
            mkdir -p "$TARGET_DIR"
        fi
    else
        TARGET_DIR="$ACTIVE_DIR"
        _running "Renaming files in current directory: $TARGET_DIR"
    fi

    # -- File Format is /var/log/webserver_logs/ff5a1958-0e43-4584-8de8-466a24542582.log-20250421
    LOG_FILES=($(\ls "$ACTIVE_DIR"/*.log-* 2>/dev/null))
    # -- Count logfiles to process into variable
    LOG_FILE_COUNT=${#LOG_FILES[@]}
    if [ $LOG_FILE_COUNT -eq 0 ]; then
        _warning "No log files found in $ACTIVE_DIR"
        exit 0
    fi
    
    _running "Processing $LOG_FILE_COUNT log files"
    for FILE in "${LOG_FILES[@]}"; do
        # Example file name /var/log/webserver_logs/ff5a1958-0e43-4584-8de8-466a24542582.log-20250421
        FILENAME=$(basename "$FILE")
        # Extract UUID and date part
        UUID=${FILENAME%%.log-*}
        DATE_PART=${FILENAME##*.log-}

        # -- Get the domain from enhance-cli
        _running2 "Getting domain for UUID: $UUID"
        DOMAIN=$(enhance-cli --quiet -c site "$UUID" 2>/dev/null)
        if [ $? -ne 0 ]; then
            _warning "enhance-cli get-domain failed for UUID:$UUID"
            continue
        fi

        if [[ -z "$DOMAIN" ]]; then
            DOMAIN="$UUID-broken"
        fi
        
        # -- Construct new filename with domain instead of UUID
        NEW_FILENAME="${DOMAIN}.log-${DATE_PART}"
        NEW_FILE_PATH="$TARGET_DIR/$NEW_FILENAME"
        
        # -- Handle duplicate filenames
        if [ -e "$NEW_FILE_PATH" ]; then
            _running2 "Filename $NEW_FILE_PATH already exists, adding a number to the end"
            # Add a number to the end of the filename if it already exists
            i=1
            while [ -e "$NEW_FILE_PATH" ]; do
                NEW_FILENAME="${DOMAIN}.log-${DATE_PART}-$i"
                NEW_FILE_PATH="$TARGET_DIR/$NEW_FILENAME"
                ((i++))
            done
        fi
        
        # -- Move/rename the file
        if [[ $DRY_RUN == 1 ]]; then
            if [[ $USE_ARCHIVE == 1 ]]; then
                _running2 "Would move $FILE to $NEW_FILE_PATH"
            else
                _running2 "Would rename $FILE to $NEW_FILE_PATH"
            fi
        else
            mv "$FILE" "$NEW_FILE_PATH"
            if [ $? -ne 0 ]; then
                _error "Failed to rename $FILE to $NEW_FILE_PATH"
                continue
            fi
            _success "Renamed $FILE to $NEW_FILE_PATH"
        fi
    done
}


# ==============================================================================
# -- Main Execution
# ==============================================================================

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        rename|dryrun)
            if [[ -z "$MODE" ]]; then
                MODE="$1"
            else
                _error "Multiple commands specified"
                _usage
            fi
            shift
            ;;
        -a|--archive)
            USE_ARCHIVE=1
            shift
            ;;
        -h|--help)
            _usage
            ;;
        *)
            _error "Unknown option: $1"
            _usage
            ;;
    esac
done

# Check if mode was specified
if [[ -z "$MODE" ]]; then
    _error "No command specified"
    _usage
fi

# Run pre-flight checks
_pre_flight

# Execute based on mode
if [[ "$MODE" == "rename" ]]; then
    _rename_log_files    
elif [[ "$MODE" == "dryrun" ]]; then
    DRY_RUN=1
    _rename_log_files    
else
    _error "Invalid mode: $MODE"
    _usage
fi