# Tasks
1. Figure out a way to keep the log file entries in order, for human reading.

# Completed
2. ✅ When running an install, if files already exist check if they are the same, and if so skip overwrite them.
   - COMPLETED in log-capture.sh (August 2025)
   - Implementation: MD5 hash comparison for both .service and logrotate files
   - Location: log-capture/log-capture.sh lines 78-106 (service) and 86-102 (logrotate)
   - Behavior:
     * If file doesn't exist: Install normally
     * If file exists and hash matches: Skip installation (no restart needed)
     * If file exists and hash differs: Install with warning
     * If -f/--force flag: Always install regardless of existing files
   - Usage: `sudo ./log-capture.sh install [-f]`
   - Prevents unnecessary systemd restarts and logrotate reloads
