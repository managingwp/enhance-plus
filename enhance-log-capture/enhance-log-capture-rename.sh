#!/bin/env bash
MODE="$1"
if [[ -z "$MODE" ]]; then
    echo "Usage: $0 <rename|dryrun>"
    exit 1
elif [[ "$MODE" == "rename" ]]; then
    DRY_RUN=0
elif [[ "$MODE" == "dryrun" ]]; then
    DRY_RUN=1
else
    echo "Invalid mode. Use 'rename' or 'dryrun'."
    exit 1
fi
ACTIVE_DIR="/var/log/webserver_logs"
ARCHIVE_DIR="/var/log/webserver_logs_archive"
# -- Confirm command enhance-cli is installed
if ! command -v enhance-cli &> /dev/null; then
    echo "enhance-cli could not be found. Please install it first."
    exit 1
fi

# This should be your mapping from UUID → domain
# Ideally load from a file or a DB in production

# -- File Format is /var/log/webserver_logs/ff5a1958-0e43-4584-8de8-466a24542582.log-20250421
LOG_FILES=($(\ls "$ACTIVE_DIR"/*.log-* 2>/dev/null))
# -- Count logfiles to process into variable
LOG_FILE_COUNT=${#LOG_FILES[@]}
if [ $LOG_FILE_COUNT -eq 0 ]; then
    echo "No log files found in $ACTIVE_DIR"
    exit 0
fi
# -- Create archive directory if it doesn't exist
if [ ! -d "$ARCHIVE_DIR" ]; then
    echo "Creating archive directory: $ARCHIVE_DIR"
    mkdir -p "$ARCHIVE_DIR"
fi
echo "Processing $LOG_FILE_COUNT log files in $ACTIVE_DIR to be renamed and moved to $ARCHIVE_DIR"
for FILE in "${LOG_FILES[@]}"; do
    # Example file name /var/log/webserver_logs/ff5a1958-0e43-4584-8de8-466a24542582.log-20250421
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
