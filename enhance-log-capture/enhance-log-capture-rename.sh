#!/bin/env bash
# enhance-log-capture-rename.sh - Script to rename and archive log files based on UUID to domain mapping
# This script is intended to be run as a postrotate script in logrotate configuration.
# =============================================================================
# -- Variables
# =============================================================================
MODE=""
DEBUG=0
DRY_RUN=0
USE_ARCHIVE=0
ARCHIVE_ENABLE=0
LOG_RENAME=1
SYMLINK_ENABLE=0
ACTIVE_DIR="/var/log/webserver_logs"
ARCHIVE_DIR="/var/log/webserver_logs_archive"
declare -A UUID_TO_DOMAIN
declare -A UUID_TO_SITEFILE
SHOW_DETAILS=0

# =============================================================================
# -- Load Configuration
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/enhance-log-capture.conf"

if [[ -f "$CONFIG_FILE" ]]; then
    # Source the configuration file to override default values
    source "$CONFIG_FILE"
fi

# Apply ARCHIVE_ENABLE from config to USE_ARCHIVE if ARCHIVE_ENABLE is set to 1
if [[ $ARCHIVE_ENABLE -eq 1 ]]; then
    USE_ARCHIVE=1
fi

# ==============================================================================
# -- Functions
# ==============================================================================
_running () { echo -e "\e[1;34m${*}\e[0m"; }
_running2 () { echo -e "\e[1;30m-- ${*}\e[0m"; }
_success () { echo -e "\e[1;32m${*}\e[0m"; }
_warning () { echo -e "\e[1;33m${*}\e[0m"; }
_error () { echo -e "\e[1;31m${*}\e[0m"; }
_debug () {
    if [[ $DEBUG -eq 1 ]]; then
        echo -e "\e[1;35mDEBUG: ${*}\e[0m" >&2
    fi
}
_log_action() {
    # Log actions to rename.run file if LOG_RENAME is enabled
    if [[ $LOG_RENAME -eq 1 ]]; then
        local timestamp
        timestamp=$(date '+%m/%d/%Y %H:%M:%S %Z')
        local log_file="${ACTIVE_DIR}/rename.run"
        echo "[${timestamp}] ${*}" >> "$log_file"
    fi
}
_usage() {
    echo "Usage: $0 <rename|dryrun> [-a] [-s] [-d]"
    echo
    echo "Commands:"
    echo "  rename   Rename and archive log files based on UUID to domain mapping"
    echo "  dryrun   Show what would be done without making any changes"
    echo
    echo "Options:"
    echo "  -a       Move files to archive directory (default: rename in current directory)"
    echo "  -s       Show per-file parsing details (source, UUID, domain, date, destination)"
    echo "  -d       Debug mode (verbose internal logs)"
    echo
    echo "Examples:"
    echo "  $0 rename        # Rename files in current directory"
    echo "  $0 rename -a     # Rename and move files to archive directory"
    echo "  $0 dryrun -a     # Show what would be done with archive option"
    exit 1
}
# =====================================
# -- Pre-flight checks
# =====================================
_pre_flight() {
    # -- Check if the active directory exists
    if [ ! -d "$ACTIVE_DIR" ]; then
        _error "Active directory $ACTIVE_DIR does not exist."
        exit 1
    fi
}

# =====================================
# -- Enhance UUID to domain mapping
# =====================================
_enhance_uuid_to_domain_db() {
    _running2 "Generating enhance UUID to domain mapping"
    # -- Get a list of all domains an UUID into an arry for use later.
    ENHANCE_SITES=($(ls -1 /var/local/enhance/appcd/*/website.json))
    if [ ${#ENHANCE_SITES[@]} -eq 0 ]; then
        _warning "No enhance sites found in /var/local/enhance/appcd/*/website.json"
        return 1
    fi
    # -- Process each site file to extract UUID and domain
    for SITE in "${ENHANCE_SITES[@]}"; do
        UUID=$(jq -r '.id' "$SITE")
        DOMAIN=$(jq -r '.mapped_domains[] | select(.is_primary == true) | .domain' "$SITE")
        _debug "Debug: Processing site $SITE, UUID=$UUID, DOMAIN=$DOMAIN"
        if [[ -z "$DOMAIN" || -z "$UUID" ]]; then
            _warning "Invalid site file $SITE, missing UUID or primary domain"
            continue
        fi
        # -- Store the mapping in an associative array (and remember source file)
        UUID_TO_DOMAIN["$UUID"]="$DOMAIN"
        UUID_TO_SITEFILE["$UUID"]="$SITE"
    done
    _running2 "Found ${#UUID_TO_DOMAIN[@]} UUID to domain mappings"
}

# =====================================
# -- _enhance_uuid_to_domain $UUID
# -- Enhance UUID to domain mapping
# =====================================
_enhance_uuid_to_domain() {
    UUID=$1
    if [[ -z "$UUID" ]]; then
        echo "UUID is required for enhance_uuid_to_domain"
        return 1
    fi
    # Check if associative array is populated
    if [[ ${#UUID_TO_DOMAIN[@]} -eq 0 ]]; then
        echo "UUID_TO_DOMAIN associative array is empty, run _enhance_uuid_to_domain_db first"
        return 1
    fi

    # -- Get the domain from the UUID_TO_DOMAIN associative array
    DOMAIN=${UUID_TO_DOMAIN[$UUID]}
    _debug "Debug: UUID=$UUID, DOMAIN=$DOMAIN"
    if [[ -z "$DOMAIN" ]]; then
        _warning "No domain found for UUID: $UUID"
        return 1
    fi
    echo "$DOMAIN"
    return 0
}

# =====================================
# -- Create symlinks from domain names to UUID log files
# =====================================
_create_symlinks() {
    # Check if symlink feature is enabled
    if [[ $SYMLINK_ENABLE -eq 0 ]]; then
        _debug "Debug: Symlink creation is disabled (SYMLINK_ENABLE=0)"
        return 0
    fi

    _running "Creating symlinks from domain names to UUID log files"
    _log_action "Starting symlink creation process"

    # Get enhance UUID to domain mapping if not already loaded
    if [[ ${#UUID_TO_DOMAIN[@]} -eq 0 ]]; then
        _enhance_uuid_to_domain_db
        [[ $? -ne 0 ]] && _error "Failed to get enhance UUID to domain mapping" && return 1
    fi

    # Get all UUID.log files in the active directory (not the rotated ones with dates)
    # Pattern: UUID.log (not UUID.log-20250421)
    UUID_LOG_FILES=($(\ls "$ACTIVE_DIR"/*.log 2>/dev/null | grep -E '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.log$'))
    UUID_LOG_COUNT=${#UUID_LOG_FILES[@]}

    if [[ $UUID_LOG_COUNT -eq 0 ]]; then
        _warning "No UUID log files found in $ACTIVE_DIR"
        _log_action "No UUID log files found for symlink creation"
        return 0
    fi

    _running2 "Found $UUID_LOG_COUNT UUID log files to process"
    _log_action "Found $UUID_LOG_COUNT UUID log files to process"

    local symlinks_created=0
    local symlinks_skipped=0
    local symlinks_failed=0

    for FILE in "${UUID_LOG_FILES[@]}"; do
        FILENAME=$(basename "$FILE")
        # Extract UUID from filename (remove .log extension)
        UUID=${FILENAME%.log}

        _debug "Debug: Processing file $FILENAME with UUID $UUID"

        # Get the domain from UUID mapping
        DOMAIN=$(_enhance_uuid_to_domain "$UUID")
        if [[ $? -ne 0 ]] || [[ -z "$DOMAIN" ]]; then
            _warning "No domain found for UUID: $UUID, skipping symlink creation"
            _log_action "No domain found for UUID: $UUID, skipping symlink creation"
            ((symlinks_failed++))
            continue
        fi

        # Construct symlink name
        SYMLINK_NAME="${DOMAIN}.log"
        SYMLINK_PATH="${ACTIVE_DIR}/${SYMLINK_NAME}"

        # Check if symlink already exists
        if [[ -L "$SYMLINK_PATH" ]]; then
            # Symlink exists, check if it points to the correct target
            CURRENT_TARGET=$(readlink "$SYMLINK_PATH")
            if [[ "$CURRENT_TARGET" == "$FILENAME" ]] || [[ "$CURRENT_TARGET" == "$FILE" ]]; then
                _debug "Debug: Symlink $SYMLINK_NAME already exists and points to correct target, skipping"
                _log_action "Symlink $SYMLINK_NAME already exists and is correct"
                ((symlinks_skipped++))
                continue
            else
                _warning "Symlink $SYMLINK_NAME exists but points to wrong target: $CURRENT_TARGET"
                if [[ $DRY_RUN == 1 ]]; then
                    _running2 "Would update symlink $SYMLINK_PATH -> $FILENAME"
                else
                    # Remove old symlink and create new one
                    rm -f "$SYMLINK_PATH"
                    ln -s "$FILENAME" "$SYMLINK_PATH"
                    if [[ $? -eq 0 ]]; then
                        _success "Updated symlink $SYMLINK_PATH -> $FILENAME"
                        _log_action "Updated symlink $SYMLINK_PATH -> $FILENAME"
                        ((symlinks_created++))
                    else
                        _error "Failed to update symlink $SYMLINK_PATH"
                        _log_action "Failed to update symlink $SYMLINK_PATH"
                        ((symlinks_failed++))
                    fi
                fi
            fi
        elif [[ -e "$SYMLINK_PATH" ]]; then
            # A regular file exists with this name
            _warning "File $SYMLINK_PATH already exists and is not a symlink, skipping"
            _log_action "File $SYMLINK_PATH already exists and is not a symlink, skipping"
            ((symlinks_failed++))
        else
            # Symlink doesn't exist, create it
            if [[ $DRY_RUN == 1 ]]; then
                _running2 "Would create symlink $SYMLINK_PATH -> $FILENAME"
            else
                ln -s "$FILENAME" "$SYMLINK_PATH"
                if [[ $? -eq 0 ]]; then
                    _success "Created symlink $SYMLINK_PATH -> $FILENAME"
                    _log_action "Created symlink $SYMLINK_PATH -> $FILENAME"
                    ((symlinks_created++))
                else
                    _error "Failed to create symlink $SYMLINK_PATH"
                    _log_action "Failed to create symlink $SYMLINK_PATH"
                    ((symlinks_failed++))
                fi
            fi
        fi
    done

    # Log summary
    _running2 "Symlink summary: Created/Updated: $symlinks_created, Skipped: $symlinks_skipped, Failed: $symlinks_failed"
    _log_action "Symlink summary: Created/Updated: $symlinks_created, Skipped: $symlinks_skipped, Failed: $symlinks_failed"
}


# =====================================
# -- Rename log files
# =====================================
_rename_log_files() {
    # This should be your mapping from UUID → domain
    # Ideally load from a file or a DB in production

    # -- Determine target directory
    if [[ $USE_ARCHIVE == 1 ]]; then
        TARGET_DIR="$ARCHIVE_DIR"
        _running "Moving files to archive directory: $TARGET_DIR"
        # -- Create archive directory if it doesn't exist
        if [ ! -d "$TARGET_DIR" ]; then
            _running2 "Creating archive directory: $TARGET_DIR"
            mkdir -p "$TARGET_DIR"
            _log_action "Created archive directory: $TARGET_DIR"
        fi
    else
        TARGET_DIR="$ACTIVE_DIR"
        _running "Renaming files in current directory: $TARGET_DIR"
    fi

    # -- Get enhance UUID to domain mapping
    _enhance_uuid_to_domain_db
    [[ $? -ne 0 ]] && _error "Failed to get enhance UUID to domain mapping" && exit 1

    # -- Candidate files: *.log-*
    ALL_FILES=($(\ls "$ACTIVE_DIR"/*.log-* 2>/dev/null))
    ALL_COUNT=${#ALL_FILES[@]}

    # -- Filter to UUID-based, non-gz files only
    LOG_FILES=()
    SKIPPED_NON_UUID=0
    SKIPPED_GZ=0
    UUID_REGEX='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    for FILE in "${ALL_FILES[@]}"; do
        FILENAME=$(basename "$FILE")
        PREFIX=${FILENAME%%.log-*}
        # ignore compressed archives (ends with .gz)
        if [[ "$FILENAME" == *.gz ]]; then
            ((SKIPPED_GZ++))
            if [[ $SHOW_DETAILS -eq 1 ]]; then
                _running2 "Skip (gz): $FILENAME"
            fi
            continue
        fi
        if [[ "$PREFIX" =~ $UUID_REGEX ]]; then
            LOG_FILES+=("$FILE")
        else
            ((SKIPPED_NON_UUID++))
            if [[ $SHOW_DETAILS -eq 1 ]]; then
                _running2 "Skip (non-UUID prefix '$PREFIX'): $FILENAME"
            fi
        fi
    done

    LOG_FILE_COUNT=${#LOG_FILES[@]}
    if [ $LOG_FILE_COUNT -eq 0 ]; then
        _warning "No rotated log files (pattern *.log-*) found in $ACTIVE_DIR; skipping rename step"
        return 0
    fi
    
    _running "Processing $LOG_FILE_COUNT log files (from $ALL_COUNT candidates; skipped non-UUID: $SKIPPED_NON_UUID, gz: $SKIPPED_GZ)"
    _log_action "Processing $LOG_FILE_COUNT log files"
    for FILE in "${LOG_FILES[@]}"; do
        # Example file name /var/log/webserver_logs/ff5a1958-0e43-4584-8de8-466a24542582.log-20250421
        FILENAME=$(basename "$FILE")
        # Extract UUID and date part
        UUID=${FILENAME%%.log-*}
        DATE_PART=${FILENAME##*.log-}

        if [[ $SHOW_DETAILS -eq 1 ]]; then
            _running2 "Parse: file=$FILENAME uuid=$UUID date=$DATE_PART"
        fi

        # -- Get the domain from enhance-cli
        _running2 "Getting domain for UUID: $UUID"
        DOMAIN=$(_enhance_uuid_to_domain "$UUID")
        if [[ $? -ne 0 ]]; then
            _warning "enhance_uuid_to_domain failed for UUID:$UUID with error: $DOMAIN"
            if [[ $SHOW_DETAILS -eq 1 ]]; then
                _running2 "Mapping source: (none)"
            fi
            continue
        fi

        if [[ -z "$DOMAIN" ]]; then
            DOMAIN="$UUID-broken"
        fi
        if [[ $SHOW_DETAILS -eq 1 ]]; then
            SRC_FILE="${UUID_TO_SITEFILE[$UUID]}"
            _running2 "Mapping: uuid=$UUID -> domain=$DOMAIN (source=${SRC_FILE:-unknown})"
        fi
        
        # -- Construct new filename with domain instead of UUID
        NEW_FILENAME="${DOMAIN}.log-${DATE_PART}"
        NEW_FILE_PATH="$TARGET_DIR/$NEW_FILENAME"
        if [[ $SHOW_DETAILS -eq 1 ]]; then
            ACTION=$([[ $USE_ARCHIVE == 1 ]] && echo move || echo rename)
            _running2 "Plan: $ACTION $FILE -> $NEW_FILE_PATH"
        fi
        
        # -- Handle duplicate filenames
        if [ -e "$NEW_FILE_PATH" ]; then
            _running2 "Filename $NEW_FILE_PATH already exists, adding a number to the end"
            # Add a number to the end of the filename if it already exists
            i=1
            while [ -e "$NEW_FILE_PATH" ]; do
                NEW_FILENAME="${DOMAIN}.log-${DATE_PART}-$i"
                NEW_FILE_PATH="$TARGET_DIR/$NEW_FILENAME"
                ((i++))
            done
        fi
        
        # -- Move/rename the file
        if [[ $DRY_RUN == 1 ]]; then
            if [[ $USE_ARCHIVE == 1 ]]; then
                _running2 "Would move $FILE to $NEW_FILE_PATH"
            else
                _running2 "Would rename $FILE to $NEW_FILE_PATH"
            fi
        else
            mv "$FILE" "$NEW_FILE_PATH"
            if [ $? -ne 0 ]; then
                _error "Failed to rename $FILE to $NEW_FILE_PATH"
                _log_action "Failed to rename $FILE to $NEW_FILE_PATH"
                continue
            fi
            _success "Renamed $FILE to $NEW_FILE_PATH"
            _log_action "Renamed $FILE to $NEW_FILE_PATH"
        fi
    done
}


# ==============================================================================
# -- Main Execution
# ==============================================================================

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        rename|dryrun)
            if [[ -z "$MODE" ]]; then
                MODE="$1"
            else
                _error "Multiple commands specified"
                _usage
            fi
            shift
            ;;
        -a|--archive)
            USE_ARCHIVE=1
            shift
            ;;
        -s|--show)
            SHOW_DETAILS=1
            shift
            ;;
        -d|--debug)
            _running2 "Debug mode enabled"
            DEBUG=1
            shift
            ;;
        -h|--help)
            _usage
            ;;
        *)
            _error "Unknown option: $1"
            _usage
            ;;
    esac
done

# Check if mode was specified
if [[ -z "$MODE" ]]; then
    _error "No command specified"
    _usage
fi

# Run pre-flight checks
_pre_flight

# Log script start
_log_action "Script started - Mode: ${MODE}, Archive: ${USE_ARCHIVE}"

# Execute based on mode
if [[ "$MODE" == "rename" ]]; then
    _rename_log_files
    _create_symlinks
elif [[ "$MODE" == "dryrun" ]]; then
    DRY_RUN=1
    _rename_log_files
    _create_symlinks
else
    _error "Invalid mode: $MODE"
    _usage
fi

# Log script end
_log_action "Script completed - Mode: ${MODE}"