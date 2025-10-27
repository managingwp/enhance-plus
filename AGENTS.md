# AGENTS.md

## enhance-log-capture
* This script is used to retain and rotate web server log files on the enhance platform.
* It utilizes systemd and a bash script with inotifywait to capture logs before they're truncated to /var/log/webserver_logs.
* It also utilizes logrotate to compress and move logs to /var/log/webserver_logs_archive