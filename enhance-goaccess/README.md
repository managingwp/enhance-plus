# enhance-goaccess
Retain and rotate web server log files on the enhance platform. Why? If a site is attacked or there is a sudden change in resource usage, the web server logs can be invaluable in diagnosing the issue.

* Utilizes systemd and a bash script with inotifywait to capture logs before they're truncated to /var/log/webserver_logs
* Utilizes logrotate to compress and move logs to /var/log/webserver_logs_archive

# Caveats/Issues
* Some logs entries might be missed due to the log file being rotated.
* The log entries might be out of order.

# Install
This is an example install. You will want to be logged in as root.
1. `cd /usr/local/sbin`
2. `git clone https://github.com/managingwp/enhance-plus.git`
3. `cd enhance-plus`
4. `./log-capture.sh install`

# Cron Examples
```
# Cron job for GoAccess report generation
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# Run GoAccess report generation every hour
0 * * * * root /usr/local/sbin/enhance-plus/goaccess/enhance-goaccess.sh -c process -d /var/www/ead638d9-5611-4253-a298-4668c8eb8387/public_html >> /var/log/enhance-goaccess-report.log 2>&1
# Run historical report generation every day at midnight
0 0 * * * root /usr/local/sbin/enhance-plus/goaccess/enhance-goaccess.sh -c historical -d /var/www/ead638d9-5611-4253-a298-4668c8eb8387/public_html >> /var/log/enhance-goaccess-report.log 2>&1
# Run index generation every hour
0 * * * * root /usr/local/sbin/enhance-plus/goaccess/enhance-goaccess.sh -c index -d /var/www/ead638d9-5611-4253-a298-4668c8eb8387/public_html >> /var/log/enhance-goaccess-report.log 2>&1
```