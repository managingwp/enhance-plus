# Tasks

## Default log file location versus >> to a log file via crontab
* The following is the default cronjob setup, but we should be logging within our script to a default location that can be overriden via command line argument such as --logdir or similar.
* The log files should have time stamps for each line for easier debugging. Such as [YYYY-MM-DD HH:MM:SS] format.

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

# Completed