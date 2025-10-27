# enhance-plus
This repository is a collection of scripts and tools to help manage the enhance platform. It is not an official part of the enhance platform, but rather a collection of tools that have been developed to help manage the platform.

# log-capture
Retain and rotate web server log files on the enhance platform. Why? If a site is attacked or there is a sudden change in resource usage, the web server logs can be invaluable in diagnosing the issue.
* Utilizes systemd and a bash script with inotifywait to capture logs before they're truncated to /var/log/webserver_logs
* Utilizes logrotate to compress and move logs to /var/log/webserver_logs_archive

[log-capture/README.md](log-capture/README.md)