# enhance-plus
This repository is a collection of scripts and tools to help manage the enhance platform. It is not an official part of the enhance platform, but rather a collection of tools that have been developed to help manage the platform.

# Install
This is an example install. You will want to be logged in as root.
| Branch | One Liner|
|--------|----------|
| main   | `curl -s https://raw.githubusercontent.com/managingwp/enhance-plus/refs/heads/main/install.sh | bash` |
| dev    | `curl -s https://raw.githubusercontent.com/managingwp/enhance-plus/refs/heads/dev/install.sh | bash` |

# log-capture
Retain and rotate web server log files on the enhance platform. Why? If a site is attacked or there is a sudden change in resource usage, the web server logs can be invaluable in diagnosing the issue.
* Utilizes systemd and a bash script with inotifywait to capture logs before they're truncated to /var/log/webserver_logs
* Utilizes logrotate to compress and move logs to /var/log/webserver_logs_archive

You can run the following command to install the enhance-log-capture script:
```
cd /usr/local/bin/enhance-plus/enhance-log-capture
./log-capture.sh install
```

## Caveats/Issues
* Some logs entries might be missed due to the log file being rotated.
* The log entries might be out of order.

