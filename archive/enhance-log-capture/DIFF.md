# Comparison: enhance-log-capture (May 2025) vs log-capture (August 2025)

## Executive Summary

The August 2025 update to the `log-capture` folder represents a significant refactoring and consolidation of the codebase. Key changes include:

1. **Unified Installation Script**: `elc-install.sh` has been replaced with `log-capture.sh` - a more comprehensive installer
2. **Simplified Logrotate Configuration**: Removed dual logrotate config files, consolidated into one with enhanced compression
3. **Enhanced Rename Script**: Complete rewrite with jq-based UUID→domain mapping instead of `enhance-cli` dependency
4. **New GoAccess Integration**: Added `enhance-goaccess-report.sh` for analytics (new feature not in May version)
5. **Better Path Placeholders**: Uses configuration placeholders for dynamic path substitution at install time

---

## Directory Structure Changes

### Files Added (August 2025)
- ✅ `log-capture.sh` - New unified installer script
- ✅ `enhance-goaccess-report.sh` - New GoAccess reporting functionality
- ✅ `README.md` - Installation and usage documentation

### Files Removed (May 2025 → Not in August)
- ❌ `elc-install.sh` - Replaced by `log-capture.sh`
- ❌ `enhance-log-capture-hourly.logrotate` - Removed, functionality merged

### Files Unchanged
- ✅ `enhance-log-capture.sh` - No changes
- ✅ `enhance-log-capture.service` - Minor path updates only

---

## Detailed Changes by File

### 1. Installation Script: `elc-install.sh` → `log-capture.sh`

#### Key Improvements

| Aspect | May 2025 (elc-install.sh) | August 2025 (log-capture.sh) |
|--------|---------------------------|------------------------------|
| **Lines** | ~64 | ~152 |
| **Commands** | `install`, `uninstall` | `install`, `uninstall`, `logrotate`, `check-logrotate` |
| **Path Substitution** | Hardcoded paths | Uses sed placeholders for dynamic configuration |
| **Error Handling** | Basic | Enhanced with better error messages |
| **Documentation** | Minimal | Comprehensive help text and examples |

#### New Command: `logrotate`
```bash
log-capture.sh logrotate  # Install only logrotate without service
```

#### Path Configuration
- **Old**: Hardcoded `/usr/local/sbin/enhance-plus/enhance-log-capture/`
- **New**: Detects script location and substitutes into service/logrotate files using sed

#### Function Refactoring
- Replaced `_running3` with `_running2`
- Added `_warning()` function for non-error alerts
- Better separation of install and uninstall logic
- Added `check-logrotate` diagnostic command

---

### 2. Logrotate Configuration: Consolidated & Enhanced

#### Changes to `enhance-log-capture.logrotate`

**Old Structure (May 2025)**:
```
- Two separate configurations:
  1. /var/log/webserver_logs/*.log (daily rotation)
  2. /var/log/webserver_logs/*.log-* (renamed hourly logs)
- Two archive rules:
  1. /var/log/webserver_logs_archive/*.gz (30 day maxage)
  2. /var/log/webserver_logs/*.gz (60 day maxage)
- postrotate: Called enhance-log-capture-rename.sh
```

**New Structure (August 2025)**:
```
- Single *.log configuration block with enhanced features:
  - Added dateext and dateformat -%Y%m%d
  - Removed .renamed suffix requirement
- Consolidated archive rule:
  - Both directories in single rule
  - Unified 30-day maxage
- postrotate enhancements:
  - Calls enhance-log-capture-rename.sh (dynamic path)
  - Logs rotation events to /var/log/webserver_logs/rotation.log
  - Finds and compresses uncompressed domain-based log files
```

#### File Pattern Matching
```bash
# Old approach (May)
/var/log/webserver_logs/*.log-20250521.renamed

# New approach (August)
/var/log/webserver_logs/*.log-20250810
# Automatically compressed during rotation
```

#### Removed File
❌ `enhance-log-capture-hourly.logrotate` - No longer needed as hourly rotation logic consolidated

---

### 3. Rename Script: Major Rewrite

#### `enhance-log-capture-rename.sh` - Complete Refactoring

**Size**: 84 lines (May) → 158 lines (August)  
**Dependencies**: 
- Old: Required `enhance-cli` command
- New: Uses `jq` for JSON parsing of `/var/local/enhance/appcd/*/website.json`

#### Key Improvements

| Feature | May 2025 | August 2025 |
|---------|----------|------------|
| **UUID Resolution** | `enhance-cli` command | `jq` JSON parsing |
| **Domain Lookup** | Runtime lookup | Cached in associative array |
| **Modes** | `rename`, `dryrun`, `archive` | `rename`, `dryrun` with `-a` flag |
| **Logging** | logger command | Color-coded echo output |
| **Error Handling** | Basic | Enhanced with proper messaging |
| **Code Quality** | Minimal comments | Well-documented with sections |
| **Debug Mode** | None | Added `-d|--debug` flag |

#### Command Line Changes

**May 2025**:
```bash
enhance-log-capture-rename.sh rename      # Rename and move to archive
enhance-log-capture-rename.sh dryrun      # Show what would happen
enhance-log-capture-rename.sh archive     # Move without renaming
```

**August 2025**:
```bash
enhance-log-capture-rename.sh rename      # Rename in current directory
enhance-log-capture-rename.sh rename -a   # Rename and move to archive
enhance-log-capture-rename.sh dryrun      # Show what would happen
enhance-log-capture-rename.sh dryrun -a   # Show with archive option
```

#### New Functions
```bash
_enhance_uuid_to_domain_db()      # Build UUID→domain mapping from enhance JSON
_enhance_uuid_to_domain()         # Lookup domain for a given UUID
_rename_log_files()               # Core renaming logic
_pre_flight()                     # Validation checks
```

#### Dependency Changes
- **Added**: `jq` (for JSON parsing)
- **Removed**: `enhance-cli` dependency

---

### 4. SystemD Service File: Path Updates

#### `enhance-log-capture.service`

**May 2025**:
```ini
ExecStart=/usr/local/sbin/enhance-plus/enhance-log-capture/enhance-log-capture.sh
```

**August 2025**:
```ini
ExecStart=SERVICE_SCRIPT_PATH_PLACEHOLDER/enhance-log-capture.sh
```

**Change**: Uses placeholder that gets substituted with actual path during installation

---

### 5. Core Script: `enhance-log-capture.sh`

✅ **No changes** - Remains identical between May and August versions

---

## New Features Added (August 2025)

### 1. GoAccess Integration
- **New File**: `enhance-goaccess-report.sh` (13KB)
- **Purpose**: Generate web analytics reports from log files
- **Features**:
  - Historical report generation
  - Report indexing
  - .htaccess/.htpasswd generation for report protection
  - Cron job installation
  - Configuration file support

### 2. README Documentation
- **New File**: `README.md`
- **Includes**:
  - Installation instructions
  - Usage examples
  - Monitoring and troubleshooting commands
  - Service status checks
  - Log file location references

### 3. Dynamic Path Configuration
- Installation scripts now detect their location
- Paths are substituted into service and logrotate files
- Supports installation from any directory

---

## Logrotate Compression Details

### August Enhancement: Automatic Compression of Domain-based Logs

The new postrotate script includes:

```bash
# Compress any uncompressed domain-based log files
find /var/log/webserver_logs/ /var/log/webserver_logs_archive/ \
  -name "*.log-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]" \
  -type f ! -name "*.gz" 2>/dev/null | while read -r logfile; do
    if [ -f "$logfile" ]; then
        echo "  - Found log not compressed $logfile, compressing" >> /var/log/webserver_logs/rotation.log
        gzip "$logfile"
    fi
done
```

**Benefits**:
- Ensures all rotated logs are compressed
- Catches logs that might have been missed by initial rotation
- Provides audit trail in `rotation.log`

---

## Migration Guide: May 2025 → August 2025

### For Users on May 2025 Version

If you're currently running the May 2025 version on your single server, here's what changed:

#### Step 1: Backup Current Configuration
```bash
sudo cp /etc/systemd/system/enhance-log-capture.service /etc/systemd/system/enhance-log-capture.service.bak
sudo cp /etc/logrotate.d/enhance-log-capture /etc/logrotate.d/enhance-log-capture.bak
```

#### Step 2: Key Changes to Note

| Component | May Version | August Version | Action Required |
|-----------|------------|-----------------|-----------------|
| Installer | `elc-install.sh` | `log-capture.sh` | Update scripts in cron/docs |
| Dependencies | `enhance-cli` | `jq` | May need to install jq |
| Archive Rule | Two separate rules | One consolidated rule | Logrotate will auto-update |
| Path Config | Hardcoded paths | Dynamic placeholders | Re-run installer |
| GoAccess | Not included | New feature included | Optional, install if needed |

#### Step 3: Uninstall Old Version
```bash
cd /path/to/old/enhance-plus
sudo ./elc-install.sh uninstall
```

#### Step 4: Install New Version
```bash
cd /path/to/new/enhance-plus
sudo ./log-capture.sh install
```

#### Step 5: Verify Installation
```bash
sudo systemctl status enhance-log-capture.service
sudo journalctl -u enhance-log-capture.service -f
ls -la /var/log/webserver_logs/
```

---

## Summary of Removals

| Item | May 2025 | August 2025 | Reason |
|------|----------|------------|--------|
| `elc-install.sh` | ✅ | ❌ | Replaced by `log-capture.sh` with more features |
| `enhance-cli` dependency | ✅ | ❌ | Replaced by `jq` JSON parsing |
| `enhance-log-capture-hourly.logrotate` | ✅ | ❌ | Consolidated into main logrotate config |
| Separate archive rules | ✅ | ❌ | Merged into single rule for simplicity |

---

## Summary of Additions

| Item | May 2025 | August 2025 | Purpose |
|------|----------|------------|---------|
| `log-capture.sh` | ❌ | ✅ | Unified installer with more features |
| `enhance-goaccess-report.sh` | ❌ | ✅ | Web analytics and reporting |
| `README.md` | ❌ | ✅ | Installation/usage documentation |
| Dynamic path substitution | ❌ | ✅ | Flexible installation locations |
| Debug logging in rotation | ❌ | ✅ | Better audit trail |
| Color-coded output | ❌ | ✅ | Better script feedback |
| Configuration file support | ❌ | ✅ | (in goaccess) Flexible settings |

---

## Compatibility Notes

### Backward Compatibility
- The core log capture mechanism (`enhance-log-capture.sh`) is identical
- Old log files will continue to work with new rotation configuration
- Existing cron jobs may reference `elc-install.sh` - should update to `log-capture.sh`

### Forward Compatibility
- New installations use the August 2025 version
- Both logrotate configurations (old and new) are compatible
- No breaking changes to log file formats

---

## Conclusion

The August 2025 update represents a **significant improvement** in:
- **Maintainability**: Unified installer, better code organization
- **Flexibility**: Dynamic path configuration, optional features
- **Functionality**: Added GoAccess analytics support
- **Reliability**: Better error handling, audit logging
- **Documentation**: Comprehensive README and inline comments

The changes are **non-breaking** for existing installations, but **strongly recommended to adopt** the new version for:
- Better dependency management (`jq` vs `enhance-cli`)
- Enhanced logging and diagnostics
- GoAccess analytics capabilities
- Simplified maintenance

