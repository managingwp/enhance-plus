#!/bin/bash

ARCHIVE_DIR="/var/log/webserver_logs"
TARGET_DATE=$(date -d "1 days ago" +%Y%m%d)

find "$ARCHIVE_DIR" -type f -name "*_${TARGET_DATE}.log" -exec gzip {} \;