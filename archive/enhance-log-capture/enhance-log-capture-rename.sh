#!/bin/env bash
ACTIVE_DIR="/var/log/webserver_logs"
ARCHIVE_DIR="/var/log/webserver_logs_archive"
DRY_RUN=0

function _usage () {
    echo "Usage: $0 <rename|dryrun|archive>"
    echo
    echo "rename: Rename and move log files to archive directory"
    echo "dryrun: Show what would be done without making any changes"
    echo "archive: Move log files to archive directory without renaming"
}

function _log () {
    local message="$1"
    local level="$2"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [$level] $message" | logger -t enhance-log-capture
}

# =====================================
# -- Process command line arguments
# =====================================
MODE="$1"
if [[ -z "$MODE" ]]; then
    _usage
    echo "Error: No mode specified. Use 'rename' or 'dryrun'."
    exit 1
elif [[ "$MODE" == "rename" ]]; then
    log "Running in rename mode"    
elif [[ "$MODE" == "dryrun" ]]; then
    log "Running in dryrun mode"
    MODE="rename"
    DRY_RUN=1
elif [[ "$MODE" == "archive" ]]; then
    log "Running in archive mode"
    MODE="archive"
    DRY_RUN=0
else
    echo "Invalid mode. Use 'rename' or 'dryrun'."
    exit 1
fi

# =====================================
# -- Confirm command enhance-cli is installed
# =====================================
if ! command -v enhance-cli &> /dev/null; then
    _log "Error: enhance-cli could not be found. Please install it first."
    exit 1
fi

# =====================================
# This should be your mapping from UUID → domain
# Ideally load from a file or a DB in production
# =====================================
# -- File Format is /var/log/webserver_logs/ff5a1958-0e43-4584-8de8-466a24542582.log-20250421.renamed
LOG_FILES=($(\ls "$ACTIVE_DIR"/*.log-*.renamed 2>/dev/null))
# -- Count logfiles to process into variable
LOG_FILE_COUNT=${#LOG_FILES[@]}
if [ $LOG_FILE_COUNT -eq 0 ]; then
    log "No log files found in $ACTIVE_DIR"
    exit 0
fi
log "Found $LOG_FILE_COUNT log files in $ACTIVE_DIR"

# -- Run rename
if [[ $MODE == "rename" ]]; then
    echo "Processing $LOG_FILE_COUNT log files in $ACTIVE_DIR to be renamed."
    for FILE in "${LOG_FILES[@]}"; do
        # Example file name /var/log/webserver_logs/ff5a1958-0e43-4584-8de8-466a24542582.log-20250421.renamed
        FILENAME=$(basename "$FILE")
        # Extract UUID and date part
        UUID=${FILENAME%%.log-*}
        DATE_PART=${FILENAME##*.log-}

        # -- Get the domain from enhance-cli
        echo "Getting domain for UUID: $UUID"
        DOMAIN=$(enhance-cli --quiet -c site "$UUID" 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "Error: enhance-cli get-domain failed for UUID:$UUID"
            continue
        fi

        if [[ -z "$DOMAIN" ]]; then
            DOMAIN="$UUID-broken"
        fi
        
        # -- Construct new filename with domain instead of UUID
        # domain.com-20250421.log
        NEW_FILENAME="${DOMAIN}.log-${DATE_PART}"
        NEW_FILE_PATH="$ARCHIVE_DIR/$NEW_FILENAME"
        
        # -- Handle duplicate filenames
        if [ -e "$NEW_FILE_PATH" ]; then
            echo "Filename $NEW_FILE_PATH already exists, adding a number to the end"
            # Add a number to the end of the filename if it already exists
            i=1
            while [ -e "$NEW_FILE_PATH" ]; do
                NEW_FILENAME="${DOMAIN}.log-${DATE_PART}-$i"
                NEW_FILE_PATH="$ARCHIVE_DIR/$NEW_FILENAME"
                ((i++))
            done
        fi
        
        # -- Move/rename the file
        [[ $DRY_RUN == 1 ]] && echo "Would move $FILE to $NEW_FILE_PATH" || mv "$FILE" "$NEW_FILE_PATH"
        if [ $? -ne 0 ]; then
            echo "Error: Failed to rename $FILE to $NEW_FILE_PATH"
            continue
        fi
        echo "Renamed $FILE to $NEW_FILE_PATH"
        echo "======================================="
    done
elif [[ $MODE == "archive" ]]; then
    echo "Archiving log files from $ACTIVE_DIR to $ARCHIVE_DIR"
    # -- Move all log files to archive directory
    for FILE in "${LOG_FILES[@]}"; do
        NEW_FILE_PATH="$ARCHIVE_DIR/$(basename "$FILE")"
        [[ $DRY_RUN == 1 ]] && echo "Would move $FILE to $NEW_FILE_PATH" || mv "$FILE" "$NEW_FILE_PATH"
        if [ $? -ne 0 ]; then
            echo "Error: Failed to move $FILE to $NEW_FILE_PATH"
            continue
        fi
        echo "Moved $FILE to $NEW_FILE_PATH"
    done
else
    _usage
fi
