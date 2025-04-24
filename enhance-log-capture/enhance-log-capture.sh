#!/bin/bash

WATCH_DIR="/var/local/enhance/webserver_logs/"
ARCHIVE_DIR="/var/log/webserver_logs"
# -- Add date to the filename, you can't use logrotate.
# -- You would need to use enhance-log-capture-compress.sh to compress the logs.
# -- This is a workaround to avoid using logrotate.
ADD_DATE="0"

mkdir -p "$ARCHIVE_DIR"

inotifywait -m -e modify --format "%w%f" "$WATCH_DIR" | while read FILE
do
    BASENAME=$(basename "$FILE")
    UUID="${BASENAME%%.*}"  # Get UUID before the first dot or extension
    DATE=$(date +%Y%m%d)
    [[ "$ADD_DATE" -eq "1" ]] && DEST="$ARCHIVE_DIR/${UUID}_${DATE}.log" || DEST="$ARCHIVE_DIR/${UUID}.log"    

    # Append new data to daily file
    cat "$FILE" >> "$DEST"

    echo "Appended $FILE to $DEST"
done
