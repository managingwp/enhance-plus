#!/bin/bash
# enhance_backup_sync.sh
#
# cPFence Team | https://cpfence.app 
#
# Description:
#   This script synchronizes the Enhance backup server's /backups directory with a remote server 
#   for disaster recovery (backup mode) or restores data from the remote server to the local server (restore mode).
#
# Usage:
#   ./enhance_backup_sync.sh [--dry-run] [--restore]
#   ./enhance_backup_sync.sh  --dry-run   Simulate operations without making changes.
#   ./enhance_backup_sync.sh  --restore   Restore backups from the remote server to the local server.
#   ./enhance_backup_sync.sh  If no arguments are provided, the script runs in backup mode, syncing local backups to the remote server.
#
#
# Key Features:
#   - Ability to sync only selected sites.
#   - Ability to exclude specific sites from the backup.
#   - In backup mode:
#     - Users and groups are automatically created on the remote server to match local UID, GID, and home directory.
#     - The remote shell is set to /usr/sbin/nologin for security reasons.
#   - In restore mode:
#     - No modifications are made to local user or group information.
#   - Backup Mode Exclusions: `current`, `snapshot-*`, and `wip-snapshot-*` are excluded for partial sync.
#   - Restore Mode Inclusions: Only `snapshot-*`, `wip-snapshot-*`, and `current` are restored; all other files are ignored.
#
# Disclaimer:
#   This script is provided "as is" without any warranties or guarantees. 
#   Use it at your own risk. The cPFence Team is not responsible for any data loss, 
#   security issues, or other damages resulting from its use.

################################################################################
#                              CONFIGURATION                                   #
################################################################################

# Local backups directory
LOCAL_BACKUP_DIR="/backups"

# Remote server details
REMOTE_SERVER="root@remoteserver.com"
REMOTE_BACKUP_DIR="/backups"

# Arrays for site IDs (using full UUID folder names)
#   - If INCLUDE_SITES is non-empty, only those sites are fully synced.
#   - If INCLUDE_SITES is empty but EXCLUDE_SITES is non-empty, all sites except those in EXCLUDE_SITES are fully synced.
#   - If both arrays are empty, all sites are fully synced.
INCLUDE_SITES=( ) # eg, ("123e4567-e89b-12d3-a456-426614174000" "234e5678-f90c-23d4-b567-526715175111")
EXCLUDE_SITES=( ) # eg, ("123e4567-e89b-12d3-a456-426614174000")

# Log file for operations
LOGFILE="/var/log/enhance_backup_sync.log"

# Lock file
LOCKFILE="/var/lock/enhance_backup_sync.lock"

################################################################################
#                              ARGUMENT PARSING                                #
################################################################################

MODE="backup"  # Default mode
DRY_RUN=""     # Default: not a dry-run

for arg in "$@"; do
    case "$arg" in
        --dry-run)
            DRY_RUN="--dry-run"
            ;;
        --restore)
            MODE="restore"
            ;;
        *)
            echo "Unknown argument: $arg"
            echo "Usage: $0 [--dry-run] [--restore]"
            exit 1
            ;;
    esac
done

echo "Running in $MODE mode. Dry run: ${DRY_RUN:-no}" | tee -a "$LOGFILE"
echo "=== Operation started at $(date) ===" | tee -a "$LOGFILE"

################################################################################
#                         FULL/PARTIAL SYNC DECISION                           #
################################################################################

should_sync_fully() {
    local site="$1"
    # If INCLUDE_SITES is non-empty, only those in it are fully synced
    if [ "${#INCLUDE_SITES[@]}" -gt 0 ]; then
        for inc in "${INCLUDE_SITES[@]}"; do
            if [ "$site" == "$inc" ]; then
                return 0  # Full
            fi
        done
        return 1  # Partial
    fi

    # Else if EXCLUDE_SITES is non-empty, exclude those from full sync
    if [ "${#EXCLUDE_SITES[@]}" -gt 0 ]; then
        for exc in "${EXCLUDE_SITES[@]}"; do
            if [ "$site" == "$exc" ]; then
                return 1  # Partial
            fi
        done
        return 0  # Full
    fi

    # If both arrays are empty, everything is full
    return 0
}

################################################################################
#                            LOCKING MECHANISM                                 #
################################################################################

exec 9>"$LOCKFILE"
if ! flock -n 9; then
    echo "Another instance is running. Exiting." | tee -a "$LOGFILE"
    exit 1
fi

################################################################################
#                USER/GROUP CREATION (REMOTE SIDE - BACKUP MODE ONLY)          #
################################################################################

# This function is only used in backup mode.
ensure_remote_user_and_group() {
    local user_name="$1"
    local group_name="$2"
    local uid_num="$3"
    local gid_num="$4"
    local home_dir="$5"

    ssh "$REMOTE_SERVER" bash -s <<EOF
# 1) Ensure the group exists with the same name and GID
if ! getent group "$group_name" >/dev/null 2>&1; then
    echo "[INFO] Creating group '$group_name' (gid=$gid_num)."
    groupadd --gid "$gid_num" "$group_name"
else
    existing_gid=\$(getent group "$group_name" | cut -d: -f3)
    if [ "\$existing_gid" != "$gid_num" ]; then
        echo "[INFO] Modifying group '$group_name' from gid=\$existing_gid to gid=$gid_num."
        groupmod -g "$gid_num" "$group_name"
    fi
fi

# 2) Ensure the user exists with the same UID, GID, and home directory;
#    Force the shell to /usr/sbin/nologin.
if ! id "$user_name" >/dev/null 2>&1; then
    echo "[INFO] Creating user '$user_name' (uid=$uid_num, gid=$gid_num) with home '$home_dir'."
    useradd --uid "$uid_num" --gid "$gid_num" --home-dir "$home_dir" --shell /usr/sbin/nologin "$user_name"
else
    existing_uid=\$(id -u "$user_name")
    existing_gid=\$(id -g "$user_name")
    if [ "\$existing_uid" != "$uid_num" ] || [ "\$existing_gid" != "$gid_num" ]; then
        echo "[INFO] Modifying user '$user_name' from (uid=\$existing_uid, gid=\$existing_gid) to (uid=$uid_num, gid=$gid_num)."
        usermod -u "$uid_num" -g "$gid_num" "$user_name"
    fi
    current_home=\$(getent passwd "$user_name" | cut -d: -f6)
    if [ "\$current_home" != "$home_dir" ]; then
        echo "[INFO] Setting home of '$user_name' from '\$current_home' to '$home_dir'."
        usermod -d "$home_dir" "$user_name"
    fi
    current_shell=\$(getent passwd "$user_name" | cut -d: -f7)
    if [ "\$current_shell" != "/usr/sbin/nologin" ]; then
        echo "[INFO] Setting shell of '$user_name' to /usr/sbin/nologin."
        usermod -s /usr/sbin/nologin "$user_name"
    fi
fi
EOF
}

################################################################################
#                             RSYNC COMMON OPTIONS                             #
################################################################################

# -a: archive mode (preserves permissions, timestamps, etc.)
# -H: preserve hard links (important for backup snapshots that use deduplication)
# --delete: remove files on destination that don't exist on source
# --info=progress2: show overall progress
# --ignore-missing-args: Ignore files that vanish during transfer
# --no-inc-recursive: Build full file list before transfer (helps with hard link tracking)
# Note: rsync exit code 24 means "some files vanished before they could be transferred" - this is normal
COMMON_RSYNC_OPTS="-aH --delete --info=progress2 --ignore-missing-args --no-inc-recursive $DRY_RUN"

# Set LC_ALL=C to avoid locale warnings on remote server
export LC_ALL=C

################################################################################
#                             MAIN LOGIC                                       #
################################################################################

if [ "$MODE" == "backup" ]; then
    #
    # BACKUP MODE: Local -> Remote
    #
    echo "Starting backup (local -> remote)..." | tee -a "$LOGFILE"

    for site_path in "$LOCAL_BACKUP_DIR"/*; do
        [ -d "$site_path" ] || continue

        site_id="$(basename "$site_path")"
        echo "Processing site: $site_id" | tee -a "$LOGFILE"

        # 1) Determine local user info from the site folder
        local_owner=$(stat -c %U "$site_path")
        local_group=$(stat -c %G "$site_path")
        local_uid=$(id -u "$local_owner")
        local_gid=$(id -g "$local_group")
        local_home=$(getent passwd "$local_owner" | cut -d: -f6)

        echo "Local site user: $local_owner (uid=$local_uid), group: $local_group (gid=$local_gid), home=$local_home" | tee -a "$LOGFILE"

        # 2) Create/modify that user/group on the remote side (only in backup mode)
        if [ -z "$DRY_RUN" ]; then
            echo "Ensuring remote user/group exist with matching UID, GID, and home..." | tee -a "$LOGFILE"
            ensure_remote_user_and_group "$local_owner" "$local_group" "$local_uid" "$local_gid" "$local_home"
        else
            echo "[DRY RUN] Would ensure remote user/group: $local_owner $local_group uid=$local_uid gid=$local_gid home=$local_home" | tee -a "$LOGFILE"
        fi

        # 3) Full or partial sync
        if should_sync_fully "$site_id"; then
            echo "-> Performing FULL backup for site $site_id" | tee -a "$LOGFILE"
            rsync $COMMON_RSYNC_OPTS \
                  "$site_path/" \
                  "${REMOTE_SERVER}:${REMOTE_BACKUP_DIR}/${site_id}/" \
                  2>&1 | tee -a "$LOGFILE"
        else
            echo "-> Performing PARTIAL backup for site $site_id (excluding 'current', 'snapshot-*', 'wip-snapshot-*')" | tee -a "$LOGFILE"
            rsync $COMMON_RSYNC_OPTS \
                  --exclude='current' \
                  --exclude='snapshot-*' \
                  --exclude='wip-snapshot-*' \
                  "$site_path/" \
                  "${REMOTE_SERVER}:${REMOTE_BACKUP_DIR}/${site_id}/" \
                  2>&1 | tee -a "$LOGFILE"
        fi

        echo "Finished processing site: $site_id" | tee -a "$LOGFILE"
    done

else
    #
    # RESTORE MODE: Remote -> Local
    #
    echo "Starting restore (remote -> local)..." | tee -a "$LOGFILE"
    remote_sites="$(ssh "$REMOTE_SERVER" "find ${REMOTE_BACKUP_DIR} -mindepth 1 -maxdepth 1 -type d -printf '%f\n'")"

    for site_id in $remote_sites; do
        echo "Restoring site: $site_id" | tee -a "$LOGFILE"
        # In restore mode, we do NOT modify local users or groups at all.

        # We also only sync 'snapshot-*' directories and the 'current' symlink, ignoring everything else.
        # This ensures we don't overwrite the "system files" like .bashrc, etc.
        echo "-> Restoring ONLY snapshots ('snapshot-*', 'wip-snapshot-*') and 'current' for site $site_id" | tee -a "$LOGFILE"
        rsync $COMMON_RSYNC_OPTS \
            --include='snapshot-*/' \
            --include='snapshot-*/**' \
            --include='wip-snapshot-*/' \
            --include='wip-snapshot-*/**' \
            --include='current' \
            --exclude='*' \
            "${REMOTE_SERVER}:${REMOTE_BACKUP_DIR}/${site_id}/" \
            "${LOCAL_BACKUP_DIR}/${site_id}/" \
            2>&1 | tee -a "$LOGFILE"

        echo "Finished restoring site: $site_id" | tee -a "$LOGFILE"
    done
fi

echo "=== Operation finished at $(date) ===" | tee -a "$LOGFILE"

