# enhance-log-capture
Retain and rotate web server log files on the enhance platform. Why? If a site is attacked or there is a sudden change in resource usage, the web server logs can be invaluable in diagnosing the issue.

* Utilizes systemd and a bash script with inotifywait to capture logs before they're truncated to /var/log/webserver_logs
* Utilizes logrotate to compress and move logs to /var/log/webserver_logs_archive

## Caveats/Issues
* Some logs entries might be missed due to the log file being rotated.
* The log entries might be out of order.

## Install
This is an example install. You will want to be logged in as root.
1. `cd /usr/local/sbin`
2. `git clone https://github.com/managingwp/enhance-plus.git`
3. `cd enhance-plus/enhance-log-capture`
4. `./enhance-log-capture.sh install`

## Usage
```bash
# Install both service and logrotate configuration
./enhance-log-capture.sh install

# Install only logrotate configuration (without monitoring service)s
./enhance-log-capture.sh logrotate

# Uninstall everything
./enhance-log-capture.sh uninstall

# Force reinstall
./enhance-log-capture.sh install -f
```

## Monitoring and Troubleshooting
After installation, use these commands to monitor the service:

```bash
# Check service status
sudo systemctl status enhance-log-capture.service

# View live service logs
sudo journalctl -u enhance-log-capture.service -f

# Check if service is running
sudo systemctl is-active enhance-log-capture.service

# View log file locations
ls -la /var/log/webserver_logs/          # Archive logs
ls -la /var/log/webserver_logs_archive/  # Rotated logs
ls -la /var/local/enhance/webserver_logs/ # Source logs (monitored)
```