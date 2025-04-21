#!/bin/env bash
echo "Installing enhance-log-capture"
SYSTEMD_FILE="/etc/systemd/system/enhance-log-capture.service"
LOGROTATE_FILE="/etc/logrotate.d/enhance-log-capture"

echo "- Installing systemd service"
if [[ ! -f $SYSTEMD_FILE ]]; then
    echo "-- File $SYSTEMD_FILE does not exist, installing"
    cp enhance-log-capture.service /etc/systemd/system/enhance-log-archive.service
    sudo systemctl daemon-reexec
    sudo systemctl enable --now enhance-log-archive.service
 else
    echo "-- File $SYSTEMD_FILE already exists, skipping to next step"    
fi

echo "- Installing logrotate configuration"
if [[ ! -f $LOGROTATE_FILE ]]; then
    echo "-- Installing logrotate configuration"
    cp enhance-log-capture.logrotate /etc/logrotate.d/enhance-log-capture
else
    echo " -- File $LOGROTATE_FILE already exists, skipping to next step"
fi

echo "* Installation complete *"