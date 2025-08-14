#!/usr/bin/env bash
# enhance-goaccess.sh - Script to generate GoAccess reports for web server logs
# ==============================================================================
# TDOO - Generate Index.html for all files in the report dir
# TODO log to a file the run
# TODO fix time distribtuion

# ===============================================================================
# -- Variables
# ==============================================================================
REPORT_DIR="$1"
MODE=""
REPORT_DIR=""
LOG_FILE="/var/log/enhance-goaccess-report.log"

# ===============================================================================
# -- Load configuration file
# ==============================================================================
CONFIG_FILE="/etc/enhance-goaccess.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    # Source the config file to load variables
    source "$CONFIG_FILE"
elif [[ -f "./enhance-goaccess.conf" ]]; then
    # Fallback to local config file in current directory
    source "./enhance-goaccess.conf"
fi

# Set default LOG_FILE if not set in config
LOG_FILE="${LOG_FILE:-/var/log/enhance-goaccess-report.log}"

# ================================================================================
# -- Functions
# ================================================================================
# -- Echo commands
_running () { echo -e "########## $* ##########" | tee -a "$LOG_FILE"; }
_running2 () { echo -e "  -- $*" | fold -s -w 80 | sed '2,$s/^/\t   /' | tee -a "$LOG_FILE"; }
_running3 () { echo -e "    -- $*" | fold -s -w 76 | sed '2,$s/^/\t\t   /' | tee -a "$LOG_FILE"; }
_running4 () { echo -e "      -- $*" | fold -s -w 72 | sed '2,$s/^/\t\t\t   /' | tee -a "$LOG_FILE"; }
_log () { echo -e "$*" | tee -a "$LOG_FILE"; }
_error () { echo -e "\e[1;31mERROR: $*\e[0m" | fold -s -w 80 | sed '2,$s/^/       /' | tee -a "$LOG_FILE"; }
_debug () { 
    if [[ $DEBUG -eq 1 ]]; then
        echo -e "\e[1;35mDEBUG: $*\e[0m" | fold -s -w 80 | sed '2,$s/^/       /' | tee -a "$LOG_FILE"
    fi
}

# -- Usage
_usage () {
    echo "Usage: $0 -c <command> -d|--directory"
    echo
    echo "Commands:"
    echo "  process             Process logs and generate GoAccess reports"
    echo "  historical          Generate historical reports from archived logs"
    echo "  index               Generate index.html for all domains in the report directory"
    echo "  install-cron        Install a cron job to run this script periodically"
    echo
    echo "Options:"    
    echo "  -d|--directory <directory>  Directory to store reports"
    echo "                              (can also be set in /etc/enhance-goaccess.conf or ./enhance-goaccess.conf)"
    echo "  -h|--help     Show this help message"
    echo
    echo "Configuration File:"
    echo
    echo "  The script will look for configuration in:"
    echo "    1. /etc/enhance-goaccess.conf"
    echo "    2. ./enhance-goaccess.conf (in current directory)"
    echo "  Command line options override configuration file settings."
    echo
    echo "Examples:"
    echo "  $0 -c process -d /var/local/enhance/goaccess_reports"
    echo "  $0 -c historical -d /var/local/enhance/goaccess_reports"
    echo "  $0 -c index -d /var/local/enhance/goaccess_reports"
    echo
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
# -- process_log
# -- Function to process logs and generate GoAccess reports
# =====================================
function _process_logs () {
    SITES=(/var/local/enhance/appcd/*/website.json)
    for SITE_JSON_FILE in "${SITES[@]}"; do
        SITE_JSON=$(cat "$SITE_JSON_FILE")
        SITE_ID=$(echo "$SITE_JSON" | jq -r '.id')
        SITE_DOMAIN=$(echo "$SITE_JSON" | jq -r '.mapped_domains[] | select(.is_primary == true).domain')
        WEB_LOG_FILE="/var/log/webserver_logs/${SITE_ID}.log"
        _running "Processing log for $SITE_DOMAIN ($SITE_ID)"
        _process_log_site "$SITE_DOMAIN" "$SITE_ID" "$WEB_LOG_FILE" "$REPORT_DIR"
        generate_index_site "$SITE_DOMAIN" "$REPORT_DIR"
    done
    generate_root_index "$REPORT_DIR"
}

# =====================================
# -- _process_log_site $DOMAIN $SITE_ID $LOG_FILE $BASE_DIR
# -- Function to process logs and generate hourly GoAccess reports
# =====================================
function _process_log_site() {
    local DOMAIN="$1"
    local SITE_ID="$2"
    local WEB_LOG_FILE="$3"
    local BASE_DIR="$4"
    local TMP_LOG=$(mktemp)
    local DOMAIN_DIR="$BASE_DIR/$DOMAIN"
    local OUTFILE="$DOMAIN_DIR/$DOMAIN-live.html"
    local DB_PATH="$DOMAIN_DIR/db"
    local RESTORE=""
    local LOG_FILE_LINE
    [[ -d $DB_PATH ]] && RESTORE="--restore --keep-last=2" || { mkdir -p "$DB_PATH"; RESTORE="--keep-last=2"; }
    _running2 "DB_PATH: $DB_PATH"
    _running2 "RESTORE: $RESTORE"
    _running2 "WEB_LOG_FILE: $WEB_LOG_FILE"

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

    _running2 "Running GoAccess on the log file: $WEB_LOG_FILE"
    GO_ACCESS_VERSION=$(goaccess --version | head -1 | awk '{print $3}')
    _running2 "GoAccess version: $GO_ACCESS_VERSION"
    GO_ACCESS_CMD="/usr/bin/goaccess "$WEB_LOG_FILE" \
        --db-path="$DB_PATH" \
        $RESTORE \
        --persist \
        -o "$OUTFILE" \
        --log-format='^\"%h\" \"%x\" \"%r\" \"%s\" \"%b\" \"%T\" \"%R\" \"%u\"' \
        --date-format='%s' \
        --time-format='%s' \
        --agent-list \
        --html-refresh \
        --no-global-config"
    _running2 "Running command: $GO_ACCESS_CMD"
    _log "        ==RUN=================================================="
    eval "$GO_ACCESS_CMD"
    _log "        ==RUN=================================================="

    # -- Cleanup
    LOG_FILE_LINE="$(tail -n 2 $WEB_LOG_FILE)"
    _running2 "Last line of $WEB_LOG_FILE: $LOG_FILE_LINE"
    rm -f "$TMP_LOG"
}

# =====================================
# -- generate_historical_reports
# -- Function to generate historical reports
# =====================================
function generate_historical_reports() {
    SITES=(/var/local/enhance/appcd/*/website.json)
    for SITE_JSON_FILE in "${SITES[@]}"; do
        SITE_JSON=$(cat "$SITE_JSON_FILE")
        SITE_ID=$(echo "$SITE_JSON" | jq -r '.id')
        SITE_DOMAIN=$(echo "$SITE_JSON" | jq -r '.mapped_domains[] | select(.is_primary == true).domain')
        _running2 "======================================================="
        _running2 "Generating historical reports for $SITE_DOMAIN ($SITE_ID)"
        _running2 "======================================================="
        generate_historical_report_site "$SITE_ID" "$SITE_DOMAIN"
        generate_index_site "$SITE_DOMAIN" "$REPORT_DIR"
    done
    generate_root_index "$REPORT_DIR"    
}

# =====================================
# -- generate_historical_report_site $SITE_ID $DOMAIN
# -- Function to generate historical reports
# =====================================
function generate_historical_report_site() {
    local SITE_ID="$1"
    local DOMAIN="$2"
    local BASE_DIR="$REPORT_DIR/$DOMAIN"
    local TODAY_ID=$(date +%Y%m%d)
    local FILE_ARCHIVES
    local archive filename temp datepart human_date OUTFILE TMP_LOG

    _running2 "Checking historical reports for $DOMAIN"
    mkdir -p "$BASE_DIR"
    
    # -- Grab every .gz for this site from both UUID and domain-based naming
    FILE_ARCHIVES=()
    # Add UUID-based archives from webserver_logs
    for file in /var/log/webserver_logs/${SITE_ID}.log-*.gz; do
        [[ -f "$file" ]] && FILE_ARCHIVES+=("$file")
    done
    
    # Add domain-based archives from webserver_logs
    for file in /var/log/webserver_logs/${DOMAIN}.log-*.gz; do
        [[ -f "$file" ]] && FILE_ARCHIVES+=("$file")
    done
    
    # Add domain-based archives from webserver_logs_archive
    for file in /var/log/webserver_logs_archive/${DOMAIN}.log-*.gz; do
        [[ -f "$file" ]] && FILE_ARCHIVES+=("$file")
    done
    _debug "Found archives: ${FILE_ARCHIVES[*]}"

    # -- Count the number of archives
    local ACRHIVE_COUNT=${#FILE_ARCHIVES[@]}
    if [[ $ACRHIVE_COUNT -eq 0 ]]; then
        _running2 "No historical archives found for $SITE_ID"
        return
    fi
    _running3 "Found $ACRHIVE_COUNT historical archives for $SITE_ID"

    for archive in "${FILE_ARCHIVES[@]}"; do
        _running3 "Checking archive: $archive"
        [[ ! -f $archive ]] && { _running3 "Error: File not found: $archive"; continue;  }
        # File name format: domain.log-YYYYMMDD.gz or UUID.log-YYYYMMDD.gz
        filename=$(basename "$archive")
        # Extract 8 digits after .log-
        if [[ $filename =~ \.log-([0-9]{8})\.gz$ ]]; then
            datepart="${BASH_REMATCH[1]}"
            _running4 "Extracted date part: $datepart from filename: $filename"
            # only 8 digits and not today/future
            if [[ $datepart -lt $TODAY_ID ]]; then                
                _running4 "Archive $archive has datepart: $datepart eligible for processing"
                if ! human_date=$(date -d "$datepart" +%Y-%m-%d 2>/dev/null); then
                    _running4 "Invalid date token: $datepart"
                    continue
                fi
                OUTFILE="$BASE_DIR/$DOMAIN-$human_date.html"
                # <-- bail if we already made it
                [[ -f $OUTFILE ]] && _running4 "Report exists, skipping: $OUTFILE" && continue
                _running4 "Generating report for $human_date on $OUTFILE"                             
                generate_goaccess_report_file "$archive" "$OUTFILE"
            else
                _running4 "Skipping future file: $filename"
            fi
        else
            _running4 "Skipping invalid file (no date found): $filename"
        fi
    done
}

# ====================================
# -- generate_goaccess_report_file $LOG_FILE $OUTFILE
# ===================================
function generate_goaccess_report_file () {
    local LOG_FILE="$1"
    local OUTFILE="$2"             
    local LOG_FORMAT='"%h" "%x" "%r" "%s" "%b" "%T" "%R" "%u"'
    # Check if file is compressed and use zcat

    _running4 "Running GoAccess on $ with format: $LOG_FORMAT"
    _running4 "zcat --force $LOG_FILE | /usr/bin/goaccess \
        --log-format=$LOG_FORMAT \
        --date-format='%s' \
        --time-format='%s' \
        --agent-list \
        --no-global-config \
        -o $OUTFILE"
    zcat "$LOG_FILE" --force | /usr/bin/goaccess \
        --log-format="$LOG_FORMAT" \
        --date-format='%s' \
        --time-format='%s' \
        --agent-list \
        --no-global-config \
        -o "$OUTFILE"
    if [[ $? -ne 0 ]]; then
        _error "GoAccess failed for $OUTFILE"
        return 1
    else
        _running4 "Report created at $OUTFILE"
    fi
}


# =====================================
# -- generate_htaccess_protection $DIR
# -- Function to create .htaccess and .htpasswd files for authentication
# =====================================
function generate_htaccess_protection() {
    local DIR="$1"    
    local HTACCESS_FILE="$DIR/.htaccess"
    local HTPASSWD_FILE="$DIR/.htpasswd"

    _running2 "Generating .htaccess and .htpasswd in $DIR"
    
    # Create .htaccess and .htpasswd if they don't exist
    if [[ ! -f "$HTACCESS_FILE" ]]; then
        _running3 "Creating .htaccess file for $DIR"
        cat <<EOF > "$HTACCESS_FILE"
AuthType Basic
AuthName "Restricted Area"
AuthUserFile $HTPASSWD_FILE
Require valid-user
EOF
        _running3 ".htaccess created at $HTACCESS_FILE"
    else
        _running3 ".htaccess already exists for $DIR"
    fi
    
    if [[ ! -f "$HTPASSWD_FILE" ]]; then
        _running3 "Creating .htpasswd file for $DIR"
        # Generate random password
        local ADMIN_PASSWORD="$(openssl rand -base64 12)"
        
        # Create htpasswd entry using htpasswd command
        _running3 "Using htpasswd command for password encryption with generated password"
        if command -v htpasswd &> /dev/null; then            
            htpasswd -cBb "$HTPASSWD_FILE" admin $ADMIN_PASSWORD            
            if [[ $? -eq 0 ]]; then
                chmod 644 "$HTPASSWD_FILE"
                _running3 ".htpasswd created at $HTPASSWD_FILE"
                _running3 "Admin credentials - Username: admin, Password: $ADMIN_PASSWORD"
                echo "$(date '+%Y-%m-%d %H:%M:%S') - $DIR - Admin credentials - Username: admin, Password: $ADMIN_PASSWORD" >> "$LOG_FILE"
            else
                _error "htpasswd command failed"
                return 1
            fi
        else
            _error "htpasswd command not found. Please install apache2-utils package"
            _running3 "Install with: sudo apt-get install apache2-utils (Ubuntu/Debian) or sudo yum install httpd-tools (CentOS/RHEL)"
            return 1
        fi
    else
        _running3 ".htpasswd already exists for $DIR"
    fi
}

# =====================================
# -- generate_index
# -- Function to generate index.html for all sites
# =====================================
generate_index() {
    _running "Generating index.html for all sites in $REPORT_DIR"    
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
    local BASE_DIR="$2"
    local DOMAIN_DIR="$BASE_DIR/$DOMAIN"
    local INDEX_FILE="$DOMAIN_DIR/index.html"
    
    _running2 "Generating index.html for $DOMAIN in dir $DOMAIN_DIR"
    
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
    _running2 "Index file created at $INDEX_FILE"
}

# =====================================
# -- generate_root_index
# -- Function to generate root-level index.html for all domains
# =====================================
generate_root_index() {
    _running "Generating root index.html for all domains"
    local BASE_DIR="$1"
    local INDEX_FILE="$BASE_DIR/index.html"

    # Generate .htaccess protection
    generate_htaccess_protection "$BASE_DIR"

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
    for dir in "$BASE_DIR"/*/; do
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

# =======================================
# -- Install Cron Job
# =======================================
_install_cron() {
    # Setup /etc/cron.d/enhance-goaccess
    local CRON_FILE="/etc/cron.d/enhance-goaccess"
    _running2 "Installing cron job to run GoAccess report generation every hour in $CRON_FILE"
    if [[ -f $CRON_FILE ]]; then
        _running2 "Cron file already exists, removing old one"
        sudo rm -f "$CRON_FILE"
    fi

    # Detect the absolute path to this script
    local SCRIPT_PATH
    SCRIPT_PATH="$(readlink -f "$0")"
    _running2 "Detected script path: $SCRIPT_PATH"

    # Create the cron job file with the detected script path
    CRON_FILE_CONTENTS=$(cat <<EOF
# Cron job for GoAccess report generation
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# Run GoAccess report generation every hour
0 * * * * root $SCRIPT_PATH -c process -d $REPORT_DIR >> $LOG_FILE 2>&1
# Run historical report generation every day at midnight
0 0 * * * root $SCRIPT_PATH -c historical -d $REPORT_DIR >> $LOG_FILE 2>&1
# Run index generation every hour
0 * * * * root $SCRIPT_PATH -c index -d $REPORT_DIR >> $LOG_FILE 2>&1
EOF
    )
    _running2 "Cron job installed in $CRON_FILE"    
    echo "$CRON_FILE_CONTENTS" | sudo tee "$CRON_FILE" > /dev/null
    sudo chmod 644 "$CRON_FILE"
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
    -c|--command)
    MODE="$2"
    shift # past argument
    shift # past value
    ;;
    -d|--directory)
    REPORT_DIR="$2"
    shift # past argument
    shift # past value
    ;;
    --debug)
    DEBUG=1
    shift # past argument
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
    _error "Error: command is required. Use -c|--command to specify."
    exit 1
elif [[ -z $REPORT_DIR ]]; then
    _usage
    _error "Error: report directory is required. Use -d|--directory or set REPORT_DIR in configuration file."
    exit 1
elif [[ $MODE == "process" ]]; then
    START_DATE=$(date +%Y-%m-%d_%H:%M:%S)
    _running "-----------------------------------------------------------"
    _running "Starting GoAccess report generation for $START_DATE"
    _running "-----------------------------------------------------------"
    _process_logs
elif [[ $MODE == "historical" ]]; then
    _running "Generating historical reports"
    generate_historical_reports
elif [[ $MODE == "index" ]]; then
    _running "Generating index.html for all domains in $REPORT_DIR"
    generate_index
    generate_root_index
elif [[ $MODE == "install-cron" ]]; then
    _running "Installing cron job for GoAccess report generation"
    _install_cron
    _running "Cron job installed successfully"    
else
    _usage
    _error "Error: Invalid mode specified. Use 'process', 'historical', or 'index'."
    exit 1
fi