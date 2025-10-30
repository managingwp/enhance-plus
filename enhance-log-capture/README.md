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

## Configuration
You can customize the log directories by creating a configuration file:

```bash
# Copy the example configuration
cp enhance-log-capture.conf.example enhance-log-capture.conf

# Edit the configuration file to customize directories
nano enhance-log-capture.conf
```

Available configuration options:
- `ACTIVE_DIR` - Directory where active log files are stored (default: `/var/log/webserver_logs`)
- `ARCHIVE_DIR` - Directory where archived/rotated log files are stored (default: `/var/log/webserver_logs_archive`)
- `ARCHIVE_ENABLE` - Enable or disable moving rotated files to archive directory (default: `0` = disabled, `1` = enabled). When enabled, rotated log files are moved to `ARCHIVE_DIR` after rotation. When disabled, files remain in `ACTIVE_DIR`.
- `LOG_RENAME` - Enable or disable logging of rename operations (default: `1` = enabled, `0` = disabled)
- `SYMLINK_ENABLE` - Enable or disable symlink creation from domain names to UUID log files (default: `0` = disabled, `1` = enabled)

**Note:** The `enhance-log-capture.conf` file is Git-ignored, so your local configuration won't be committed to the repository.

### Symlink Feature
When `SYMLINK_ENABLE=1` is set in the configuration, the script will automatically create symlinks from human-readable domain names to UUID-based log files. This makes it much easier to locate and access log files for specific domains.

**Example:**
```bash
# Enable symlinks in configuration
echo "SYMLINK_ENABLE=1" >> enhance-log-capture.conf

# The script will create symlinks like:
# example.com.log -> e2b4585e-b25d-4e05-b93f-4f2edcd81a35.log
# testsite.org.log -> ff5a1958-0e43-4584-8de8-466a24542582.log
```

**Benefits:**
- Easy to find logs by domain name without looking up UUIDs
- Works with existing tools and scripts
- Symlinks are automatically managed and updated
- Minimal overhead and disk space usage

**Testing:**
```bash
# Test symlink creation in dry-run mode
./enhance-log-capture-rename.sh dryrun

# Create symlinks for real
./enhance-log-capture-rename.sh rename
```

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

1.  Check service status
```sudo systemctl status enhance-log-capture.service```

2. View live service logs
```sudo journalctl -u enhance-log-capture.service -f```

3. Check if service is running
```sudo systemctl is-active enhance-log-capture.service```

4. View log file locations
```
ls -la /var/log/webserver_logs/          # Rotated logs
ls -la /var/log/webserver_logs_archive/  # Archive logs
ls -la /var/local/enhance/webserver_logs/ # Source logs (monitored)
```

5. Test logrotate configuration
```sudo logrotate -d /etc/logrotate.d/enhance-log-capture```
