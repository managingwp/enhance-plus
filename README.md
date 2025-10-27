# enhance-plus
This repository is a collection of scripts and tools to help manage the enhance platform. It is not an official part of the enhance platform, but rather a collection of tools that have been developed to help manage the platform.

## log-capture

Retain and rotate web server log files on the enhance platform. Why? If a site is attacked or there is a sudden change in resource usage, the web server logs can be invaluable in diagnosing the issue.
* Utilizes systemd and a bash script with inotifywait to capture logs before they're truncated to /var/log/webserver_logs
* Utilizes logrotate to compress and move logs to /var/log/webserver_logs_archive

[log-capture/README.md](log-capture/README.md)

## goaccess
Generate web server log reports using goaccess. Why? GoAccess provides a real-time web log analyzer and interactive viewer that runs in a terminal or through a browser.
* Utilizes goaccess to generate HTML reports from web server logs stored in /var/log/webserver_logs_archive
* Reports are stored in /var/www/enhance-goaccess-reports and can be accessed via a web browser within the default vhost for the server.

# Caveats/Issues
* Some logs entries might be missed due to the log file being rotated.
* The log entries might be out of order.
