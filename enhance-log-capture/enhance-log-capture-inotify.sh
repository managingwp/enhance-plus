#!/bin/bash

set -o pipefail

WATCH_DIR="${WATCH_DIR:-/var/local/enhance/webserver_logs/}"
ARCHIVE_DIR="${ARCHIVE_DIR:-/var/log/webserver_logs}"
# If set to 1, include date in destination file name
ADD_DATE="${ADD_DATE:-0}"

# De-dup window in seconds for adjacent identical lines
DEDUP_WINDOW_SEC="${DEDUP_WINDOW_SEC:-1}"
# Where we keep per-source offsets so we only append new bytes
OFFSETS_DIR="${OFFSETS_DIR:-/var/run/enhance-log-capture}"
STATE_DIR="${STATE_DIR:-/dev/shm/enhance-log-capture}"

mkdir -p "$ARCHIVE_DIR" "$OFFSETS_DIR" "$STATE_DIR"

# Deduplicate adjacent identical lines within a short window
_dedup_awk() {
    awk -v w="$DEDUP_WINDOW_SEC" '
        BEGIN { last=""; last_t=0 }
        {
            now = systime()
            if ($0 == last && (now - last_t) <= w) next
            print
            last=$0; last_t=now
        }'
}

# Read only the new bytes since last read and append to destination with optional dedup
# Usage: _append_delta_with_dedup <source_file> <dest_file>
_append_delta_with_dedup() {
    local SRC="$1"
    local DEST="$2"
    local key ofile prev size delta size2

    [[ ! -f "$SRC" ]] && return 0

    # Unique key per source path
    key="${SRC//\//_}"
    ofile="$OFFSETS_DIR/$key.offset"

    prev=$(cat "$ofile" 2>/dev/null || echo 0)
    size=$(stat -c%s "$SRC" 2>/dev/null || echo 0)

    # Handle truncation (e.g., when file is rotated/truncated)
    if [[ "$size" -lt "$prev" ]]; then
        prev=0
    fi

    # Nothing new
    if [[ "$size" -le "$prev" ]]; then
        echo "$size" > "$ofile" 2>/dev/null
        return 0
    fi

    delta=$(( size - prev ))

    # Coalesce bursts of writes
    sleep 0.1
    size2=$(stat -c%s "$SRC" 2>/dev/null || echo 0)
    if [[ "$size2" -gt "$size" ]]; then
        size="$size2"
        delta=$(( size - prev ))
    fi

    # Ensure DEST directory exists
    mkdir -p "$(dirname "$DEST")"

    # Read only new bytes and filter adjacent duplicates in-window
    dd if="$SRC" bs=1 skip="$prev" count="$delta" status=none \
        | _dedup_awk >> "$DEST"

    echo "$size" > "$ofile" 2>/dev/null
}

# Process only on CLOSE_WRITE and MOVED_TO to avoid multiple MODIFY triggers
inotifywait -m -e CLOSE_WRITE,MOVED_TO --format "%w%f %e" "$WATCH_DIR" | \
while read -r FILE EVENTS; do
    BASENAME=$(basename "$FILE")
    UUID="${BASENAME%%.*}"  # UUID before first dot
    DATE=$(date +%Y%m%d)
    if [[ "$ADD_DATE" -eq "1" ]]; then
        DEST="$ARCHIVE_DIR/${UUID}_${DATE}.log"
    else
        DEST="$ARCHIVE_DIR/${UUID}.log"
    fi

    case "$EVENTS" in
        *CLOSE_WRITE*|*MOVED_TO*)
            _append_delta_with_dedup "$FILE" "$DEST"
            ;;
        *)
            : # ignore others
            ;;
    esac
done
