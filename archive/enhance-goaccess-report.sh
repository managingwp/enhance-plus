#!/usr/bin/env bash
# TDOO - Generate Index.html for all files in the report dir
# TODO log to a file the run
# TODO fix time distribtuion
REPORT_DIR="$1"
MODE=""
REPORT_DIR=""
LOG_FILE="/var/log/enhance-goaccess-report.log"

# -- Echo commands
_running () { echo -e "-- $*" | tee -a "$LOG_FILE"; }
_running2 () { echo -e "\t-- $*" | tee -a "$LOG_FILE"; }
_running3 () { echo -e "\t\t-- $*" | tee -a "$LOG_FILE"; }
_running4 () { echo -e "\t\t\t-- $*" | tee -a "$LOG_FILE"; }
_error () { echo -e "ERROR: $*" | tee -a "$LOG_FILE"; }

# -- Usage
_usage () {
    echo "Usage: $0 -m|--mode <mode> -d|--directory"
    echo
    echo "Options:"
    echo "  -m|--mode     Mode of operation: process, historical, or index"
    echo "  -d|--directory <directory>  Directory to store reports"
    echo "  -h|--help     Show this help message"

}

# ======================================
# -- Pre-flight checks
# ======================================
function _pre-flight () {

    # -- Check if report dir exists
    [[ -d $REPORT_DIR ]] || { _error "Error: directory doesn't exist: $REPORT_DIR"; _usage; exit 1; }


    # -- Check if GoAccess is installed
    if ! command -v goaccess &> /dev/null; then
        _error "GoAccess is not installed. Please install it first."
        exit 1
    fi
}

# =====================================
# -- create_htaccess
# -- Function to create .htaccess file to disable caching
# =====================================
create_htaccess() {
    local REPORT_DIR="$1"
    local HTACCESS_FILE="$REPORT_DIR/.htaccess"
    
    _running2 "Creating .htaccess file in $REPORT_DIR"
    
    cat <<EOF > "$HTACCESS_FILE"
# Disable LiteSpeed server cache for everything
<IfModule LiteSpeed>
  CacheDisable public /
  CacheDisable private /
</IfModule>

# Turn off any Expires headers
<IfModule mod_expires.c>
  ExpiresActive Off
</IfModule>

# Prevent browser caching via headers
<IfModule mod_headers.c>
  Header set Cache-Control "no-store, no-cache, must-revalidate, max-age=0"
  Header set Pragma "no-cache"
  Header set Expires "Thu, 01 Jan 1970 00:00:00 GMT"
  Header unset ETag
</IfModule>

# Disable ETags
FileETag None
EOF
}

# =====================================
# -- process_log
# -- Function to process logs and generate GoAccess reports
# =====================================
function process_logs () {
    # Create .htaccess file to disable caching
    create_htaccess "$REPORT_DIR"
    
    SITES=(/var/local/enhance/appcd/*/website.json)
    for SITE_JSON_FILE in "${SITES[@]}"; do
        SITE_JSON=$(cat "$SITE_JSON_FILE")
        SITE_ID=$(echo "$SITE_JSON" | jq -r '.id')
        SITE_DOMAIN=$(echo "$SITE_JSON" | jq -r '.mapped_domains[] | select(.is_primary == true).domain')
        LOG_FILE="/var/log/webserver_logs/${SITE_ID}.log"
        _running "Processing log for $SITE_DOMAIN ($SITE_ID)"
        process_log_site "$SITE_DOMAIN" "$SITE_ID" "$LOG_FILE" "$REPORT_DIR"
        generate_index_site "$SITE_DOMAIN" "$REPORT_DIR"
    done
    generate_root_index "$REPORT_DIR"
}

# =====================================
# -- Function to process logs and generate hourly GoAccess reports
# =====================================
process_log_site() {
    local DOMAIN="$1"
    local SITE_ID="$2"
    local LOG_FILE="$3"
    local REPORT_DIR="$4"
    local TMP_LOG=$(mktemp)
    local DOMAIN_DIR="$REPORT_DIR/$DOMAIN"
    local OUTFILE="$DOMAIN_DIR/$DOMAIN-live.html"
    local DB_PATH="$DOMAIN_DIR/db"
    local RESTORE=""
    [[ -d $DB_PATH ]] && RESTORE="--restore --keep-last=2" || { mkdir -p "$DB_PATH"; RESTORE="--keep-last=2"; }
    _running2 "DB_PATH: $DB_PATH - RESTORE: $RESTORE"

    # -- Ensure domain-specific report directory exists
    [[ ! -d $DOMAIN_DIR ]] && mkdir -p "$DOMAIN_DIR"

    # -- Extract only lines from the last hour using grep
    # "50.175.91.30" "1747849176" "GET /wp-content/uploads/2025/05/unnamed-40-1.jpg HTTP/1.1" "200" "1284" "32427" "https://domain.com/" "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36"
    # -- For Unix timestamp logs, uncomment the line below
    #HOUR_TOKEN=$(date -d '1 hour ago' +%s)
    #echo -e "\t-- Extracting logs for the last hour ($HOUR_TOKEN)"
    #awk -F\" 'BEGIN { cutoff = systime() - 3600 } { if ($(4) > cutoff) print }' "$LOG_FILE" > "$TMP_LOG"
    #LOG_LINES_TOTAL=$(wc -l < "$TMP_LOG")
    #echo -e "\t-- Total lines in log file: $LOG_LINES_TOTAL"

    _running2 "Running GoAccess on the log file: $LOG_FILE"
    GO_ACCESS_VERSION=$(goaccess --version | head -1 | awk '{print $3}')
    _running2 "GoAccess version: $GO_ACCESS_VERSION"
    GO_ACCESS_CMD="/usr/bin/goaccess "$LOG_FILE" \
        --db-path="$DB_PATH" \
        $RESTORE \
        --persist \
        -o "$OUTFILE" \
        --log-format='^\"%h\" \"%d\" \"%r\" \"%s\" \"%b\" \"%T\" \"%R\" \"%u\"' \
        --date-format='%s' \
        --time-format='%s' \
        --agent-list \
        --html-refresh \
        --no-global-config"
    _running2 "Running command: $GO_ACCESS_CMD"
    eval "$GO_ACCESS_CMD"

    # -- Cleanup
    LOG_FILE_LINE="$(tail -n 1 $LOG_FILE)"
    _running2 "Last line of log file: $LOG_FILE_LINE"
    rm -f "$TMP_LOG"
}

# =====================================
# -- generate_historical_reports
# -- Function to generate historical reports
# =====================================
function generate_historical_reports() {
    # Create .htaccess file to disable caching
    create_htaccess "$REPORT_DIR"
    
    SITES=(/var/local/enhance/appcd/*/website.json)
    for SITE_JSON_FILE in "${SITES[@]}"; do
        SITE_JSON=$(cat "$SITE_JSON_FILE")
        SITE_ID=$(echo "$SITE_JSON" | jq -r '.id')
        SITE_DOMAIN=$(echo "$SITE_JSON" | jq -r '.mapped_domains[] | select(.is_primary == true).domain')
        _running2 "Generating historical reports for $SITE_DOMAIN ($SITE_ID)"
        generate_historical_report_site "$SITE_ID" "$SITE_DOMAIN"
        generate_index_site "$SITE_DOMAIN" "$REPORT_DIR"
    done
    generate_root_index "$REPORT_DIR"
}

# =====================================
# -- generate_historical_report_site $SITE_ID $DOMAIN
# -- Function to generate historical reports
# =====================================
generate_historical_report_site() {
    local SITE_ID="$1"
    local DOMAIN="$2"
    local REPORT_DIR="$REPORT_DIR/$DOMAIN"
    local TODAY_ID=$(date +%Y%m%d)
    local FILE_ARCHIVES
    local archive filename temp datepart human_date OUTFILE TMP_LOG

    _running2 "Checking historical reports for $DOMAIN"
    mkdir -p "$REPORT_DIR"

    # -- Grab every .gz for this site
    FILE_ARCHIVES=(/var/log/webserver_logs/${SITE_ID}.log-*.gz)

    # -- Count the number of archives
    local ACRHIVE_COUNT=${#FILE_ARCHIVES[@]}
    if [[ $ACRHIVE_COUNT -eq 0 ]]; then
        _running2 "No historical archives found for $SITE_ID"
        return
    fi
    _running2 "Found $ACRHIVE_COUNT historical archives for $SITE_ID"

    # collect unique dates
    declare -A SEEN_DATES=()
    for archive in "${FILE_ARCHIVES[@]}"; do
        _running3 "Processing archive: $archive"
        [[ ! -f $archive ]] && continue
        filename=$(basename "$archive")
        temp="${filename#${SITE_ID}.log-}"
        temp="${temp%.gz}"
        datepart="${temp%%-*}"    # YYYYMMDD
        # only 8 digits and not today/future
        if [[ $datepart =~ ^[0-9]{8}$ ]] && [[ $datepart -lt $TODAY_ID ]]; then
            SEEN_DATES[$datepart]=1
        else
            _running4 "Skipping invalid/future file: $filename"
        fi
    done

    # now generate one report per date
    for datepart in "${!SEEN_DATES[@]}"; do
        # convert to human YYYY-MM-DD
        if ! human_date=$(date -d "$datepart" +%Y-%m-%d 2>/dev/null); then
            _running4 "Invalid date token: $datepart"
            continue
        fi

        OUTFILE="$REPORT_DIR/$DOMAIN-$human_date.html"

        # <-- bail if we already made it
        if [[ -f $OUTFILE ]]; then
            _running4 "Report exists, skipping: $OUTFILE"
            continue
        fi

        _running4 "Generating report for $human_date"
        TMP_LOG=$(mktemp)

        # concatenate every archive for that date, sorted by timestamp
        for f in /var/log/webserver_logs/${SITE_ID}.log-${datepart}*.gz; do
            _running4 ">>>> Found archive: $f"
            [[ -f $f ]] || continue
            zcat "$f" >> "$TMP_LOG"
        done

        # no leading ^\" here
        local LOG_FORMAT='"%h" "%d" "%r" "%s" "%b" "%T" "%R" "%u"'
        _running4 "Running GoAccess on $TMP_LOG with format: $LOG_FORMAT"

        /usr/bin/goaccess "$TMP_LOG" \
            --log-format="$LOG_FORMAT" \
            --date-format='%s' \
            --time-format='%s' \
            --agent-list \
            --no-global-config \
            -o "$OUTFILE"

        rm -f "$TMP_LOG"
    done
}

# =====================================
# -- generate_index
# -- Function to generate index.html for all sites
# =====================================
generate_index() {
    # Create .htaccess file to disable caching
    create_htaccess "$REPORT_DIR"
    
    _running2 "Generating index.html for all domains in $REPORT_DIR"
    SITES=(/var/local/enhance/appcd/*/website.json)
    for SITE_JSON_FILE in "${SITES[@]}"; do
        SITE_JSON=$(cat "$SITE_JSON_FILE")
        SITE_ID=$(echo "$SITE_JSON" | jq -r '.id')
        SITE_DOMAIN=$(echo "$SITE_JSON" | jq -r '.mapped_domains[] | select(.is_primary == true).domain')
        generate_index_site "$SITE_DOMAIN" "$REPORT_DIR"
    done
}
# =====================================
# -- generate_index_site $DOMAIN $REPORT_DIR
# -- Function to generate index.html for a domain
# =====================================
generate_index_site() {
    local DOMAIN="$1"
    local REPORT_DIR="$2"
    local DOMAIN_DIR="$REPORT_DIR/$DOMAIN"
    local INDEX_FILE="$DOMAIN_DIR/index.html"
    _running2 "Generating index.html for $DOMAIN in $DOMAIN_DIR"
    # -- Start HTML skeleton
    cat <<EOF > "$INDEX_FILE"
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>$DOMAIN Reports Index</title>
  <style>
    body { font-family: sans-serif; margin: 2rem; }
    a { display: block; margin: 0.5rem 0; text-decoration: none; }
  </style>
</head>
<body>
  <h1>GoAccess Reports for $DOMAIN</h1>
  <p>Click a report below:</p>
  <ul>
EOF

    # -- List report files (excluding index.html)
    find "$DOMAIN_DIR" -maxdepth 1 -type f -name "$DOMAIN-*.html" ! -name 'index.html' | sort -r | while read -r file; do
        fname=$(basename "$file")
        echo "    <li><a href=\"$fname\">$fname</a></li>" >> "$INDEX_FILE"
    done

    # -- Close HTML tags
    cat <<EOF >> "$INDEX_FILE"
  </ul>
</body>
</html>
EOF
}

# =====================================
# -- generate_root_index
# -- Function to generate root-level index.html for all domains
# =====================================
generate_root_index() {
    _running "Generating root index.html for all domains"
    local REPORT_DIR="$1"
    local INDEX_FILE="$REPORT_DIR/index.html"

    # -- Start HTML skeleton
    cat <<EOF > "$INDEX_FILE"
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>All GoAccess Reports</title>
  <style>
    body { font-family: sans-serif; margin: 2rem; }
    a { display: block; margin: 0.5rem 0; text-decoration: none; }
  </style>
</head>
<body>
  <h1>All GoAccess Domains</h1>
  <p>Select a domain to view reports:</p>
  <ul>
EOF

    # -- List each domain directory and link to its index
    for dir in "$REPORT_DIR"/*/; do
        domain=$(basename "$dir")
        echo "    <li><a href=\"$domain/index.html\">$domain</a></li>" >> "$INDEX_FILE"
    done

    # -- Close HTML tags
    cat <<EOF >> "$INDEX_FILE"
  </ul>
</body>
</html>
EOF
}

# =============================================================================
# -- Main script execution
# =============================================================================

# -- Check args
POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -m|--mode)
    MODE="$2"
    shift # past argument
    shift # past value
    ;;
    -d|--directory)
    REPORT_DIR="$2"
    shift # past argument
    shift # past value
    ;;
    -h|--help)
    _usage
    exit 0
    ;;
    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

_pre-flight

if [[ -z $MODE ]]; then
    _usage
    _error "Error: mode is required. Use -m|--mode to specify."
    exit 1
elif [[ $MODE == "process" ]]; then
    _running "======== Starting GoAccess report generation ========"
    process_logs
elif [[ $MODE == "past" ]]; then
    _running "Generating historical reports"
    generate_historical_reports
elif [[ $MODE == "index" ]]; then
    _running "Generating index.html for all domains in $REPORT_DIR"
    generate_index
    generate_root_index
else
    _usage
    _error "Error: Invalid mode specified. Use 'process', 'historical', or 'index'."
    exit 1
fi% 