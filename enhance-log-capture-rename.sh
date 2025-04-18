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

# -- File Format is d8568b84-f024-468a-9d73-4b3f0abc8bb6.log-20231001.gz
LOG_FILES=($(\ls "$ACTIVE_DIR"/*.log.gz 2>/dev/null))
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
    # Example file name 051f4c48-f47f-4374-b9ea-ccd44e76e6ff_20250417.log.gz
    FILENAME=$(basename "$FILE")
    # strip _date.log.gz
    UUID=$(echo "$FILENAME" | cut -d_ -f1)  # strip .log.gz
    DATE_PART=$(echo "$FILENAME" | cut -d_ -f2 | cut -d. -f1) # strip .log.gz
    echo "== Processing file: $FILE - FILENAME: $FILENAME - UUID: $UUID - DATE_PART: $DATE_PART"

    # -- Get the domain from enhance-cli
    echo "Getting domain for UUID: $UUID"
    DOMAIN=$(enhance-cli --quiet -c site "$UUID" 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo "Error: enhance-cli get-domain failed for UUID:$UUID"
        continue
    fi
    # -- Rename the file
    NEW_FILENAME="${DOMAIN}_${DATE_PART}.log.gz"
    if [ -e "$NEW_FILE_PATH" ]; then
        _echo "Filename $NEW_FILE_PATH already exists, adding a timestamp"
        TIMESTAMP=$(date +%Y%m%d%H%M%S)
        NEW_FILENAME="${DOMAIN}_${DATE_PART}_${TIMESTAMP}.log.gz"        
    fi
    NEW_FILE_PATH="$ARCHIVE_DIR/$NEW_FILENAME"
    [[ $DRY_RUN == 1 ]] && echo "Would move $FILE to $NEW_FILE_PATH" || mv "$FILE" "$NEW_FILE_PATH"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to rename $FILE to $NEW_FILE_PATH"
        continue
    fi
    echo "Renamed $FILE to $NEW_FILE_PATH"    
    echo "======================================="    
done
