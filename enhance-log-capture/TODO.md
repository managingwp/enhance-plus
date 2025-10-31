# Tasks

## 4. Move compress code from .logrotate to enhance-log-capture-rename.sh
Currently the .logrotate file has some code, I want to keep the LOGROTATE_SCRIPT_PATH_PLACEHOLDER/enhance-log-capture-rename.sh rename command.

However, the remaining code I'd like to put into a enhance-log-capture-rename.sh as compress and add the appropriate functionality to run during dryrun as -c and also log to rename.run and remove rotation.run

## 5. Create all Command
I would then like to create a new command called all, that will do the symlink, rename and compress all in one shot.

Then I would like the .logrotate postrotate script to to be updated from rename to all.

## 6. Update .logrotate for webserver_logs_archive
Sicne archive logged that are compressed can live in both /var/log/webserver_logs_archive and also potentially in /var/log/webserver_logs_archive/compressed based on the ARC configuration I'd like to update the .logrotate file to handle both locations.

## 7. Update Archive Directory Function
Confirm if this doesn't already exist, if it does then do nothing.

If the archive dir is configured, make sure to check if it exists during install and create it if not and also move existing compressed logs to the new location if they exist as the configuration might be enabled after initial install.

# Completed
## 1. ✅ When running an install, if files already exist check if they are the same, and if so skip overwrite them.
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

## 3. ✅ Keep log entries ordered and intact for human reading
Resolved by preserving full-line boundaries during appends so partial lines are not emitted.

Changes (enhance-log-capture-inotify.sh):
- Buffer per-source delta to a temp file and prepend any previously incomplete tail.
- If the final byte isn’t a newline, keep the trailing partial line in a carry file and emit only complete lines.
- Run complete lines through the adjacent de-dup filter before appending to destination.

Result: lines in the destination log are intact and appear in the correct write order without mid-line breaks, improving human readability.