#!/usr/bin/env bash
# enhance-log-capture-rename.sh - Rename/organize webserver logs by domain
#
# Commands:
#   rename    Rename UUID.log-YYYYMMDD -> domain.log-YYYYMMDD (and optionally move to archive)
#   dryrun    Show what would happen; accepts options (-a, -l, -c, -s, -d)
#   symlinks  Create domain.log -> UUID.log symlinks for live logs in ACTIVE_DIR
#   compress  Gzip any uncompressed *.log-YYYYMMDD in ACTIVE_DIR and ARCHIVE_DIR
#   archive   Move compressed *.log-YYYYMMDD.gz from ACTIVE_DIR to ARCHIVE_DIR

set -o pipefail

# ---------- Defaults ----------
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
SHOW_DETAILS=0
COMPRESS=0

# ---------- Optional config ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/enhance-log-capture.conf"
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
fi
[[ ${ARCHIVE_ENABLE:-0} -eq 1 ]] && USE_ARCHIVE=1

# ---------- Helpers ----------
_running()  { echo -e "\e[1;34m${*}\e[0m"; }
_running2() { echo -e "\e[1;30m-- ${*}\e[0m"; }
_success()  { echo -e "\e[1;32m${*}\e[0m"; }
_warning()  { echo -e "\e[1;33m${*}\e[0m"; }
_error()    { echo -e "\e[1;31m${*}\e[0m"; }
_debug()    { [[ $DEBUG -eq 1 ]] && echo -e "\e[1;35mDEBUG: ${*}\e[0m" >&2; }
_log_action(){
  [[ $LOG_RENAME -ne 1 ]] && return 0
  local ts; ts=$(date '+%m/%d/%Y %H:%M:%S %Z')
  echo "[$ts] $*" >> "$ACTIVE_DIR/rename.run"
}

_usage(){ cat <<'EOF'
Usage: enhance-log-capture-rename.sh <command>

Commands:
  rename     Rename/move rotated UUID logs to domain logs
  dryrun     Show what would be done (accepts options below)
  symlinks   Create domain.log -> UUID.log symlinks for live logs
  compress   Compress any uncompressed *.log-YYYYMMDD
  archive    Move compressed logs (*.gz) from active to archive

Options (only for 'dryrun'):
  -a, --archive    Plan to use ARCHIVE_DIR for renames and move compressed logs (*.gz) to archive
  -l, --symlinks   Plan to also create domain symlinks
  -c, --compress   Plan to run compression after rename
  -s, --show       Show per-file mapping/plan details
  -d, --debug      Verbose internal logs

Examples:
  enhance-log-capture-rename.sh rename
  enhance-log-capture-rename.sh dryrun -l -c -s
  enhance-log-capture-rename.sh compress
  enhance-log-capture-rename.sh archive
EOF
  exit 1; }

_pre_flight(){
  [[ -d "$ACTIVE_DIR" ]] || { _error "Active dir $ACTIVE_DIR not found"; exit 1; }
}

# ---------- UUID -> domain mapping ----------
_enhance_uuid_to_domain_db(){
  _running2 "Building UUID->domain map"
  local -a sites
  mapfile -t sites < <(ls -1 /var/local/enhance/appcd/*/website.json 2>/dev/null || true)
  if [[ ${#sites[@]} -eq 0 ]]; then
    _warning "No enhance sites found"
    return 1
  fi
  for SITE in "${sites[@]}"; do
    local uuid domain
    uuid=$(jq -r '.id' "$SITE" 2>/dev/null || true)
    domain=$(jq -r '.mapped_domains[] | select(.is_primary == true) | .domain' "$SITE" 2>/dev/null || true)
    [[ -n "$uuid" && -n "$domain" ]] || { _warning "Skip invalid $SITE"; continue; }
    UUID_TO_DOMAIN["$uuid"]="$domain"
  done
  _running2 "Mapped ${#UUID_TO_DOMAIN[@]} UUIDs"
}

_enhance_uuid_to_domain(){ [[ -n "$1" ]] && echo "${UUID_TO_DOMAIN[$1]}"; }

# ---------- Symlinks ----------
_create_symlinks(){
  [[ $SYMLINK_ENABLE -eq 1 ]] || { _running2 "Symlink creation disabled"; return 0; }
  [[ ${#UUID_TO_DOMAIN[@]} -gt 0 ]] || _enhance_uuid_to_domain_db || { _warning "No mappings"; return 0; }
    local -a files
    mapfile -t files < <(find "$ACTIVE_DIR" -maxdepth 1 -type f -regextype posix-extended -regex ".*/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\\.log$" -print 2>/dev/null || true)
  [[ ${#files[@]} -gt 0 ]] || { _running2 "No UUID live logs"; return 0; }
  local created=0 skipped=0 failed=0
  for f in "${files[@]}"; do
    local base uuid domain link
    base=$(basename "$f"); uuid=${base%.log}
    domain=$(_enhance_uuid_to_domain "$uuid") || true
    [[ -n "$domain" ]] || { ((failed++)); continue; }
    link="$ACTIVE_DIR/${domain}.log"
    if [[ -L "$link" ]]; then
      local cur; cur=$(readlink "$link")
      if [[ "$cur" == "$base" || "$cur" == "$f" ]]; then ((skipped++)); continue; fi
      if [[ $DRY_RUN -eq 1 ]]; then _running2 "Would update $link -> $base"; ((skipped++)); else rm -f "$link" && ln -s "$base" "$link" && ((created++)) || ((failed++)); fi
    elif [[ -e "$link" ]]; then
      _warning "$link exists (not symlink)"; ((failed++))
    else
      if [[ $DRY_RUN -eq 1 ]]; then _running2 "Would create $link -> $base"; ((skipped++)); else ln -s "$base" "$link" && ((created++)) || ((failed++)); fi
    fi
  done
  _running2 "Symlinks: created=$created skipped=$skipped failed=$failed"
}

# ---------- Compress ----------
_compress_logs(){
  local -a targets=()
  for d in "$ACTIVE_DIR" "$ARCHIVE_DIR"; do
    [[ -d "$d" ]] || continue
    while IFS= read -r -d '' f; do targets+=("$f"); done < <(find "$d" -maxdepth 2 -type f -regextype posix-extended -regex ".*\\.log-[0-9]{8}$" ! -name "*.gz" -print0 2>/dev/null)
  done
  [[ ${#targets[@]} -gt 0 ]] || { _running2 "No uncompressed rotated logs"; _log_action "Compress: nothing"; return 0; }
  local done=0 skip=0 fail=0
  for f in "${targets[@]}"; do
    if [[ $DRY_RUN -eq 1 ]]; then _running2 "Would compress $f"; _log_action "Would compress $f"; ((skip++));
    else gzip -f "$f" && { ((done++)); _log_action "Compressed $f"; } || { ((fail++)); _log_action "Compress failed $f"; }; fi
  done
  _running2 "Compress: compressed=$done skipped=$skip failed=$fail"
}

# ---------- Archive ----------
_archive_logs(){
  [[ -d "$ARCHIVE_DIR" ]] || { _running2 "Create $ARCHIVE_DIR"; mkdir -p "$ARCHIVE_DIR"; }
  local -a files
  mapfile -t files < <(find "$ACTIVE_DIR" -maxdepth 2 -type f -regextype posix-extended -regex ".*\\.log-[0-9]{8}\\.gz$" -print 2>/dev/null || true)
  [[ ${#files[@]} -gt 0 ]] || { _running2 "No compressed logs to move"; _log_action "Archive: nothing"; return 0; }
  local moved=0 skip=0 fail=0
    for f in "${files[@]}"; do
        local dest
        dest="$ARCHIVE_DIR/$(basename "$f")"
    if [[ $DRY_RUN -eq 1 ]]; then _running2 "Would move $f -> $dest"; _log_action "Would move $f -> $dest"; ((skip++));
    else mv -f "$f" "$dest" && { ((moved++)); _log_action "Archived $f -> $dest"; } || { ((fail++)); _log_action "Archive failed $f"; }; fi
  done
  _running2 "Archive: moved=$moved skipped=$skip failed=$fail"
}

# ---------- Rename ----------
_rename_log_files(){
  local target_dir
  if [[ $USE_ARCHIVE -eq 1 ]]; then target_dir="$ARCHIVE_DIR"; [[ -d "$target_dir" ]] || mkdir -p "$target_dir"; _running "Move to archive: $target_dir";
  else target_dir="$ACTIVE_DIR"; _running "Rename in place: $target_dir"; fi

  _enhance_uuid_to_domain_db || _warning "No UUID->domain mappings"

  local -a candidates=()
  mapfile -t candidates < <(ls -1 "$ACTIVE_DIR"/*.log-* 2>/dev/null || true)
  [[ ${#candidates[@]} -gt 0 ]] || { _running2 "No rotated logs"; return 0; }

  local UUID_REGEX='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  local -a files=()
  for f in "${candidates[@]}"; do
    local name; name=$(basename "$f")
    [[ "$name" == *.gz ]] && continue
    local prefix=${name%%.log-*}
    [[ $prefix =~ $UUID_REGEX ]] && files+=("$f")
  done
  [[ ${#files[@]} -gt 0 ]] || { _running2 "No UUID-rotated files"; return 0; }

  for FILE in "${files[@]}"; do
    local FILENAME UUID DATE_PART DOMAIN NEW_FILENAME NEW_PATH
    FILENAME=$(basename "$FILE")
    UUID=${FILENAME%%.log-*}
    DATE_PART=${FILENAME##*.log-}
    DOMAIN=$(_enhance_uuid_to_domain "$UUID")
    [[ -n "$DOMAIN" ]] || DOMAIN="$UUID-broken"
    [[ $SHOW_DETAILS -eq 1 ]] && _running2 "uuid=$UUID -> domain=$DOMAIN"
    NEW_FILENAME="${DOMAIN}.log-${DATE_PART}"
    NEW_PATH="$target_dir/$NEW_FILENAME"
    if [[ -e "$NEW_PATH" ]]; then
      local i=1
      while [[ -e "$target_dir/${DOMAIN}.log-${DATE_PART}-$i" ]]; do ((i++)); done
      NEW_FILENAME="${DOMAIN}.log-${DATE_PART}-$i"
      NEW_PATH="$target_dir/$NEW_FILENAME"
    fi
        if [[ $DRY_RUN -eq 1 ]]; then
            local action
            action=$([[ $USE_ARCHIVE -eq 1 ]] && echo move || echo rename)
      _running2 "Would $action $FILE -> $NEW_PATH"; _log_action "Would $action $FILE -> $NEW_PATH"; continue
    fi
    mv "$FILE" "$NEW_PATH" && { _success "Renamed $FILE -> $NEW_PATH"; _log_action "Renamed $FILE -> $NEW_PATH"; } || { _error "Failed $FILE"; _log_action "Failed rename $FILE"; }
  done

  [[ $COMPRESS -eq 1 ]] && _compress_logs
}

# ---------- CLI ----------
_pre_flight
[[ $# -ge 1 ]] || _usage
MODE="$1"; shift

if [[ "$MODE" == "dryrun" ]]; then
  DRY_RUN=1
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -a|--archive) USE_ARCHIVE=1 ;;
      -l|--symlinks) SYMLINK_ENABLE=1 ;;
      -c|--compress) COMPRESS=1 ;;
      -s|--show) SHOW_DETAILS=1 ;;
      -d|--debug) DEBUG=1 ;;
      -h|--help) _usage ;;
      *) _error "Unknown dryrun option: $1"; _usage ;;
    esac
    shift
  done
else
  # For non-dryrun commands, reject options for clarity
  if [[ $# -gt 0 ]]; then
    _error "Options are only supported with the 'dryrun' command"
    _usage
  fi
fi

case "$MODE" in
  rename)
    _rename_log_files
    SYMLINK_ENABLE=1; _create_symlinks
    ;;
  dryrun)
    _rename_log_files
    _create_symlinks
    [[ $COMPRESS -eq 1 ]] && _compress_logs
    [[ $USE_ARCHIVE -eq 1 ]] && _archive_logs
    ;;
  symlinks)
    SYMLINK_ENABLE=1; _create_symlinks
    ;;
  compress)
    _compress_logs
    ;;
  archive)
    _archive_logs
    ;;
  *)
    _usage
    ;;
esac

exit 0