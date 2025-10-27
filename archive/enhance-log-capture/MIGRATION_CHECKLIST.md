# Migration Checklist: May 2025 → August 2025

Use this checklist to safely migrate from the older enhance-log-capture (May 2025) to the newer log-capture (August 2025) on your single server.

---

## Pre-Migration Assessment

- [ ] **Document Current Setup**
  - [ ] Take note of current installation path
  - [ ] Document any custom cron jobs
  - [ ] Note any modifications to scripts
  - [ ] Capture current systemd service status: `sudo systemctl status enhance-log-capture.service`

- [ ] **Check System Requirements**
  - [ ] Confirm running as root or with sudo: `whoami`
  - [ ] Verify systemd is available: `systemctl --version`
  - [ ] Confirm logrotate is installed: `which logrotate`
  - [ ] Check inotifywait is available: `which inotifywait`

- [ ] **Verify Current State**
  - [ ] Check service is running: `sudo systemctl is-active enhance-log-capture.service`
  - [ ] Review current logs: `ls -la /var/log/webserver_logs/`
  - [ ] Check logrotate config: `ls -la /etc/logrotate.d/enhance-log-capture`
  - [ ] Note any recent rotation activity: `tail -n 20 /var/log/syslog | grep logrotate`

---

## Pre-Migration Backups

- [ ] **Backup Current Configuration**
  ```bash
  sudo cp /etc/systemd/system/enhance-log-capture.service \
          /etc/systemd/system/enhance-log-capture.service.bak.may2025
  
  sudo cp /etc/logrotate.d/enhance-log-capture \
          /etc/logrotate.d/enhance-log-capture.bak.may2025
  ```

- [ ] **Backup Current Installation** (if not in git)
  ```bash
  cp -r /path/to/current/enhance-log-capture /backup/enhance-log-capture.may2025
  ```

- [ ] **Verify Backups**
  ```bash
  ls -la /etc/systemd/system/enhance-log-capture.service.bak.may2025
  ls -la /etc/logrotate.d/enhance-log-capture.bak.may2025
  ```

---

## Dependency Check & Installation

- [ ] **Check Required Dependencies**
  - [ ] `jq` installed: `which jq` (if not: `sudo apt-get install jq`)
  - [ ] `enhance-cli` NOT required for August version
  - [ ] Verify `gzip` available: `which gzip`

- [ ] **Install Missing Dependencies** (if needed)
  ```bash
  # For Ubuntu/Debian
  sudo apt-get update
  sudo apt-get install -y jq
  
  # For CentOS/RHEL
  sudo yum install -y jq
  ```

- [ ] **Verify jq Installation**
  ```bash
  jq --version
  echo '{"test": "data"}' | jq .
  ```

---

## Code Preparation

- [ ] **Obtain New Version**
  - [ ] Pull latest from git: `cd /path/to/repo && git pull origin main`
  - [ ] Or clone fresh: `git clone https://github.com/managingwp/enhance-plus.git`

- [ ] **Verify New Files Present**
  ```bash
  ls -la log-capture/log-capture.sh
  ls -la log-capture/enhance-log-capture-rename.sh
  ls -la log-capture/enhance-log-capture.logrotate
  ls -la goaccess/enhance-goaccess-report.sh
  ```

- [ ] **Make Scripts Executable**
  ```bash
  chmod +x log-capture/log-capture.sh
  chmod +x log-capture/enhance-log-capture-rename.sh
  chmod +x log-capture/enhance-log-capture.sh
  ```

- [ ] **Review Documentation**
  - [ ] Read: `DIFF.md` (comprehensive changes)
  - [ ] Read: `QUICK_REFERENCE.md` (quick summary)
  - [ ] Read: `COMPARISON.md` (side-by-side)
  - [ ] Read: `log-capture/README.md` (setup instructions)

---

## Pre-Migration Testing

- [ ] **Test New Rename Script in Dry-Run Mode**
  ```bash
  sudo ./log-capture/enhance-log-capture-rename.sh dryrun -d
  ```
  - [ ] Script runs without errors
  - [ ] Output shows correct domain mappings
  - [ ] No actual files are modified

- [ ] **Verify JSON Mapping**
  ```bash
  ls -la /var/local/enhance/appcd/*/website.json
  jq '.mapped_domains' /var/local/enhance/appcd/*/website.json
  ```

- [ ] **Test Logrotate Configuration** (dry-run)
  ```bash
  sudo logrotate -d /path/to/new/log-capture/enhance-log-capture.logrotate
  ```

---

## Uninstall Old Version

- [ ] **Stop the Service**
  ```bash
  sudo systemctl stop enhance-log-capture.service
  sudo systemctl status enhance-log-capture.service  # Verify stopped
  ```

- [ ] **Disable Service**
  ```bash
  sudo systemctl disable enhance-log-capture.service
  ```

- [ ] **Remove Old Service File**
  ```bash
  sudo rm -f /etc/systemd/system/enhance-log-capture.service
  ```

- [ ] **Reload Systemd**
  ```bash
  sudo systemctl daemon-reload
  ```

- [ ] **Remove Old Logrotate (if desired)**
  ```bash
  # Back it up first!
  sudo cp /etc/logrotate.d/enhance-log-capture /tmp/enhance-log-capture.old
  sudo rm -f /etc/logrotate.d/enhance-log-capture
  ```

- [ ] **Verify Removal**
  ```bash
  ls -la /etc/systemd/system/enhance-log-capture.service  # Should not exist
  ls -la /etc/logrotate.d/enhance-log-capture           # Should not exist (or old)
  sudo systemctl is-active enhance-log-capture.service  # Should be "inactive"
  ```

---

## Install New Version

- [ ] **Run New Installer**
  ```bash
  cd /path/to/new/log-capture
  sudo ./log-capture.sh install
  ```

- [ ] **Monitor Installation Output**
  - [ ] No errors reported
  - [ ] Service file path substitution successful
  - [ ] Logrotate file path substitution successful

- [ ] **Verify Installation**
  ```bash
  ls -la /etc/systemd/system/enhance-log-capture.service
  ls -la /etc/logrotate.d/enhance-log-capture
  ```

- [ ] **Check Service Status**
  ```bash
  sudo systemctl status enhance-log-capture.service
  sudo systemctl is-active enhance-log-capture.service  # Should be "active"
  ```

---

## Post-Migration Verification

- [ ] **Verify Service Running**
  ```bash
  sudo systemctl status enhance-log-capture.service
  sudo journalctl -u enhance-log-capture.service -n 20
  ```

- [ ] **Check Log Capture**
  - [ ] Logs appear in `/var/log/webserver_logs/`
  - [ ] File timestamps are recent
  - [ ] File sizes are reasonable

- [ ] **Test Manual Rotation** (if safe on your system)
  ```bash
  # Force a test rotation
  sudo logrotate -f /etc/logrotate.d/enhance-log-capture
  ```

- [ ] **Verify Rotation Log**
  ```bash
  tail -f /var/log/webserver_logs/rotation.log
  ```

- [ ] **Check File Compression**
  ```bash
  ls -la /var/log/webserver_logs_archive/
  # Should see .gz files, not bare .log files
  ```

- [ ] **Test Rename Script**
  ```bash
  sudo ./log-capture/enhance-log-capture-rename.sh dryrun -a
  # Should show domain-based names
  ```

---

## Cron Job Updates

- [ ] **Update Cron References** (if applicable)
  - [ ] Find old references: `grep -r "elc-install" /etc/cron* /var/spool/cron/*`
  - [ ] Update paths in cron jobs to use `log-capture.sh` instead
  - [ ] Verify cron syntax: `crontab -l` (for user crons)

- [ ] **Update Any Scripts Calling Old Installer**
  - [ ] Search: `grep -r "elc-install" /usr/local/bin /opt`
  - [ ] Replace with `log-capture.sh` path
  - [ ] Test updated scripts

---

## Optional: Install GoAccess Analytics (August 2025 Feature)

- [ ] **Install GoAccess** (if desired)
  ```bash
  sudo apt-get install -y goaccess
  goaccess --version
  ```

- [ ] **Install htpasswd** (if protecting reports)
  ```bash
  sudo apt-get install -y apache2-utils
  which htpasswd
  ```

- [ ] **Test GoAccess Script**
  ```bash
  sudo ./goaccess/enhance-goaccess-report.sh -c process -d /var/www/reports
  ```

- [ ] **Set Up GoAccess Cron Job** (if desired)
  ```bash
  sudo ./goaccess/enhance-goaccess-report.sh -c install-cron -d /var/www/reports
  ```

---

## Performance Monitoring (Post-Migration)

- [ ] **Monitor CPU/Memory**
  ```bash
  top -p $(pgrep -f enhance-log-capture.sh)
  ```

- [ ] **Check Log Rotation Timing**
  ```bash
  # Review last few rotations
  tail -n 50 /var/log/webserver_logs/rotation.log
  ```

- [ ] **Verify UUID→Domain Mapping Speed**
  ```bash
  time sudo ./log-capture/enhance-log-capture-rename.sh dryrun
  # Should be very fast (< 1 second)
  ```

- [ ] **Check Disk Space**
  ```bash
  df -h /var/log/
  du -sh /var/log/webserver_logs*
  ```

---

## Troubleshooting

If you encounter issues during migration, refer to these sections:

- [ ] **Service Won't Start**
  - Check: `sudo journalctl -u enhance-log-capture.service -n 50 -e`
  - Verify paths: `cat /etc/systemd/system/enhance-log-capture.service`
  - Re-run installer: `sudo ./log-capture.sh install -f`

- [ ] **Rotation Fails**
  - Check: `sudo logrotate -d /etc/logrotate.d/enhance-log-capture`
  - Verify permissions: `ls -la /var/log/webserver_logs/`
  - Check rotation.log: `tail -f /var/log/webserver_logs/rotation.log`

- [ ] **Rename Script Errors**
  - Enable debug: `sudo ./log-capture/enhance-log-capture-rename.sh dryrun --debug`
  - Verify JSON files: `ls /var/local/enhance/appcd/*/website.json`
  - Check jq: `jq --version`

- [ ] **jq Not Found**
  - Install: `sudo apt-get install -y jq`
  - Verify: `which jq && jq --version`

- [ ] **Path Issues**
  - Re-run installer: `cd /new/location && sudo ./log-capture.sh install`
  - Check paths: `grep ExecStart /etc/systemd/system/enhance-log-capture.service`

---

## Final Verification Checklist

- [ ] Service is running
- [ ] Logs are being captured
- [ ] Rotation is working
- [ ] Files are being renamed correctly
- [ ] Files are being compressed
- [ ] Archive directory has compressed files
- [ ] Old directory is backed up
- [ ] Documentation is accessible
- [ ] No error messages in journalctl
- [ ] Rotation audit log is being written
- [ ] Performance is acceptable

---

## Rollback Plan (If Needed)

If migration fails or causes issues:

- [ ] **Stop New Service**
  ```bash
  sudo systemctl stop enhance-log-capture.service
  ```

- [ ] **Restore Old Configuration**
  ```bash
  sudo cp /etc/systemd/system/enhance-log-capture.service.bak.may2025 \
          /etc/systemd/system/enhance-log-capture.service
  
  sudo cp /etc/logrotate.d/enhance-log-capture.bak.may2025 \
          /etc/logrotate.d/enhance-log-capture
  ```

- [ ] **Restore Old Scripts** (if needed)
  ```bash
  cp -r /backup/enhance-log-capture.may2025 /path/to/old/location
  ```

- [ ] **Reload and Restart**
  ```bash
  sudo systemctl daemon-reload
  sudo systemctl enable enhance-log-capture.service
  sudo systemctl start enhance-log-capture.service
  ```

- [ ] **Verify Rollback**
  ```bash
  sudo systemctl status enhance-log-capture.service
  sudo journalctl -u enhance-log-capture.service -n 20
  ```

---

## Post-Migration Documentation

- [ ] Update internal documentation with new path
- [ ] Document any custom configurations
- [ ] Store backup locations in a safe place
- [ ] Share migration notes with team
- [ ] Archive this checklist with date completed

---

## Sign-Off

- **Migration Date**: _________________
- **Completed By**: _________________
- **Verified By**: _________________
- **Notes**: _________________________________________________

---

## Additional Resources

- Full comparison: See `DIFF.md`
- Quick reference: See `QUICK_REFERENCE.md`
- Side-by-side comparison: See `COMPARISON.md`
- Installation guide: See `log-capture/README.md`
- GoAccess setup: See `goaccess/` folder

**Status**: ✅ Migration Complete / ❌ Migration Rolled Back

