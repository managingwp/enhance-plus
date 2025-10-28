# Tasks
## 1. Figure out a way to keep the log file entries in order, for human reading.
## 2. Duplicate Entries in Log — ✅ RESOLVED
Duplicates were caused by re-reading the whole file on each MODIFY event. We now only append new bytes and filter adjacent duplicates.

Resolution (enhance-log-capture/enhance-log-capture-inotify.sh):
- Process on CLOSE_WRITE,MOVED_TO (not raw MODIFY) to avoid mid-write reads.
- Track per-source byte offsets in /var/run/enhance-log-capture so each byte is processed exactly once.
- Coalesce bursts with a short 100ms delay before reading new bytes.
- Adjacent de-dup filter drops identical consecutive lines within a small window (DEDUP_WINDOW_SEC, default 1s).
- Handle truncation: if the source shrinks, the offset resets to 0.

Tunables (env):
- WATCH_DIR (default /var/local/enhance/webserver_logs/)
- ARCHIVE_DIR (default /var/log/webserver_logs)
- ADD_DATE=0|1 (include date in dest file name)
- DEDUP_WINDOW_SEC (default 1; set 0 to disable adjacent de-dup)
- OFFSETS_DIR (default /var/run/enhance-log-capture)

Result: duplicate lines from rapid successive writes are eliminated while real repeated requests still appear if spaced outside the de-dup window.


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
