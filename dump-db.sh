#!/bin/bash
script_start=$(date '+%s.%N')

set -e

usage() {
    printf '%s\n\n' "\

NAME

    dump-db.sh - Docker friendly database dumping bash script

SYNOPSIS

    Usage: $0  [-h hostname] [-p password] [-d /directory]

DESCRIPTION

      This script will dump and autorotate the contents of multiple databases in a configurable
    and friendly manner. Designed with Docker in mind, each option can be set from the CLI,
    environment variable, or read in from a file for use with Docker secrets. e.g. Setting
    'BACKUP_PASSWORD_FILE=/var/run/secrets/password' will place the contents of the file into
    the BACKUP_PASSWORD variable. For best results, use with scheduling software such as vixie's
    cron or mcuadros/ofelia.

DEPENDENCIES

    bash, date, awk, mysqldump, mysqladmin, printf, gzip, cp, rm

OPTIONS

    -h, --host [hostname]       (default: localhost) (env: DB_HOST)
        mysql server hostname

    -P, --port [port]           (default: 3306) (env: DB_PORT)
        port used by mysql server

    -u, --user [username]       (default:root) (env: BACKUP_USER)
        username credential for connecting to the database

    -p, --password [password]   (default: password) (env: BACKUP_PASSWORD)
        password credential for connecting to the database

    -d, --directory [/path]     (default: /backups) (env: BACKUP_PATH)
        directory to store database dump files

    -t, --timezone [timezone]   (default: UTC) (env: BACKUP_TZ)
        /bin/date friendly timezone to use for backup filenames and log output

    -D, --databases [db1/db2]   (default: '') (env: BACKUP_DATABASES)
        databases to backup with / delimiter

    -q, --query [query]         (default: SELECT DB FROM mysql.db WHERE User NOT LIKE 'mysql.%') (env: BACKUP_DB_QUERY)
        query used to find your databases if a static list is not provided, requires '--init true' (default)

    -o, --options [options]     (default: --single-transaction) (env: MYSQLDUMP_OPTIONS)
        command line arguments for mysqldump

    -l, --log [/path/file]      (default: false) (env: BACKUP_LOG_FILE)
        set to a writable path to enable logging

    -kc, --keep-current [count]          (default: 60) (env: MAX_CURRENT_BACKUPS)
        maxmimum backups to keep in the current folder; use 0 for no pruning

    -kh, --keep-hourly [count]          (default: 24) (env: MAX_HOURLY_BACKUPS)
        maxmimum backups to keep in the hourly folder; use 0 for no pruning

    -kd, --keep-daily [count]          (default: 7) (env: MAX_DAILY_BACKUPS)
        maxmimum backups to keep in the daily folder; use 0 for no pruning

    -kw, --keep-weekly [count]          (default: 5) (env: MAX_WEEKLY_BACKUPS)
        maxmimum backups to keep in the weekly folder; use 0 for no pruning

    -km, --keep-monthly [count]          (default: 12) (env: MAX_MONTHLY_BACKUPS)
        maxmimum backups to keep in the monthly folder; use 0 for no pruning

    -ky, --keep-yearly [count]          (default: 0) (env: MAX_YEARLY_BACKUPS)
        maxmimum backups to keep in the yearly folder; use 0 for no pruning

    -c, --connect [count]       (default: 5) (env: MAX_CONNECT_ATTEMPTS)
        maximum connection attempts before giving up on a server, requires '--init true' (default)

    -s, --sleep [count]         (default: 3) (env: SLEEP_BETWEEN_ATTEMPTS)
        number of seconds to wait inbetween connection attempts, requires '--init true' (default)

    -i, --init [true/false]     (default: true) (env: INIT_QUERY)
        send init query to database. Required 'true' for --query and --connect options
        recommended 'true' for Docker installations to mitigate container init delays

    --debug [true/false]        (default: false) (env: BACKUP_DEBUG_LOGGING)
        change value from false enable additional log output

    --help, --usage
        this help menu"

    exit 1
}
set_options(){
    while [[ "$1" =~ ^- && ! "$1" == "--" ]]; do case $1 in
        -h | --host)
            shift; DB_HOST=$1
            ;;
        -P | --port)
            shift; DB_PORT=$1
            ;;
        -u | --user)
            shift; BACKUP_USER=$1
            ;;
        -p | --password)
            shift; BACKUP_PASSWORD=$1
            ;;
        -d | --directory)
            shift; BACKUP_PATH=$1
            ;;
        -t | --timezone)
            shift; BACKUP_TZ=$1
            ;;
        -D | --databases)
            shift; BACKUP_DATABASES=$1
            ;;
        -q | --query)
            shift; BACKUP_TZ=$1
            ;;
        -o | --options)
            shift; MYSQLDUMP_OPTIONS=$1
            ;;
        -l | --log)
            shift; BACKUP_LOG_FILE=$1
            ;;
        -kc | --keep-current)
            shift; MAX_CURRENT_BACKUPS=$1
            ;;
        -kh | --keep-hourly)
            shift; MAX_HOURLY_BACKUPS=$1
            ;;
        -kd | --keep-daily)
            shift; MAX_DAILY_BACKUPS=$1
            ;;
        -kw | --keep-weekly)
            shift; MAX_WEEKLY_BACKUPS=$1
            ;;
        -km | --keep-monthly)
            shift; MAX_MONTHLY_BACKUPS=$1
            ;;
        -ky | --keep-yearly)
            shift; MAX_YEARLY_BACKUPS=$1
            ;;
        -i | --init)
            shift; INIT_QUERY=$1
            ;;
        -c | --connect)
            shift; MAX_CONNECT_ATTEMPTS=$1
            ;;
        -s | --sleep)
            shift; SLEEP_BETWEEN_ATTEMPTS=$1
            ;;
        --debug)
            shift; BACKUP_DEBUG_LOGGING=$1
            ;;
        * )
            usage # officially --help | --usage
            ;;
    esac; shift; done
    if [[ "$1" == '--' ]]; then shift; fi
}
file_env() {
    local var="$1"
    local fileVar="${var}_FILE"
    local def="${2:-}"
    if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
        abort "Both $var and $fileVar are set (but are exclusive)"
    fi
    local val="$def"
    if [ "${!var:-}" ]; then
        val="${!var}"
    elif [ "${!fileVar:-}" ]; then
        val="$(< "${!fileVar}")"
    fi
    export "$var"="$val"
    unset "$fileVar"
}
debuglog(){
    if [ "$BACKUP_DEBUG_LOGGING" != "false" ]; then
        log "[DEBUG] $1"
    fi
}
log(){
    if [ "$BACKUP_LOG_FILE" != "false" ]; then
        printf '%s\n' "[$(TZ=$BACKUP_TZ date '+%Y-%m-%d %H:%M:%S')] $1" >> "$BACKUP_LOG_FILE"
    fi
}
warn(){
    local m=${1:-"..."}
    log "[WARN] $m"
    printf '%s\n' "$0 [WARN] $m" >&2
}
abort(){
    local m=${1:-"..."}
    log "[ERROR] $m"
    printf '%s\n' "$0 [ERROR] $m" >&2
    exit 1
}
wait_for_db(){
    printf '%s' "Pinging $DB_HOST:$DB_PORT"
    timer_start=$(date '+%s.%N')
    SECONDS=0
    while [ "$results" != "0" ]; do
        if [ "$SECONDS" -ge "10" ]; then
            timeout=$(printf '%s' "$timer_start $(date '+%s.%N')" | awk '{ printf "%f", $2 - $1 }')
            printf '%s\n' ''
            warn "Ping timeout after $timeout seconds"
            break
        fi
        if [ ! -z "$results" ]; then
            printf '%s' "."
            sleep 1
        fi
        results=$(ping_db)
    done
    if [ "$results" == "0" ]; then
        timer_end=$(printf '%s' "$timer_start $(date '+%s.%N')" | awk '{ printf "%f", $2 - $1 }')
        printf '%s\n' " Pong!"
        debuglog "Pinging $DB_HOST:$DB_PORT took $timer_end seconds"
    fi
}
ping_db(){
    "$mysqladmin" ping -h"$DB_HOST" --silent > /dev/null
    printf '%s' "$?"
}
get_rotate_mask(){
    local val
    case "$1" in
        hourly)
            val="$current_year$current_month$current_day${current_week}-$current_hour"
            ;;
        daily)
            val="$current_year$current_month$current_day${current_week}-"
            ;;
        weekly)
            val="$current_year${current_month}??${current_week}-"
            ;;
        monthly)
            val="$current_year$current_month"
            ;;
        yearly)
            val="$current_year"
            ;;
    esac
    printf '%s' "$val"
}
dump(){
    local dir="$BACKUP_PATH/$1/current"
    local file="${1}-$file_date"
    local ext='sql.gz'
    local tmpfile="/tmp/$file.$ext"
    local filepath="$dir/$file.$ext"
    local count=1
    local copied='0'

    mkdir -p "$dir" || abort "Unable mkdir $dir for dump()"
    "$mysqldump" -h"$DB_HOST" -u"$BACKUP_USER" "$MYSQLDUMP_OPTIONS" "$1" | \
      "$gzip" > "$tmpfile"
    if [ "${PIPESTATUS[0]}" -eq 0 ]; then
        debuglog "$1 dumped to $tmpfile"
    else
        warn "mysqldump could not complete backup of $1 to $tmpfile"
    fi
    if [ -e "$tmpfile" ]; then
        while [ "$copied" -eq '0' ]; do
            debuglog "Copying to $filepath"
            copied=$(cp -nv "$tmpfile" "$filepath" | awk 'END{print NR}')
            if [ "$copied" -gt '0' ]; then
                if [ -e "$tmpfile" ]; then
                    debuglog "Removing temp file: $tmpfile"
                    rm "$tmpfile"
                fi
                break
            elif [ -e "$filepath" ]; then
                warn "[Attempt $count] Failed, because file exists: $filepath"
                count=$((count + 1))
                filepath="$dir/$file.$count.$ext"
                if [ "$count" -gt "100" ]; then
                    warn "Unable to complete backup after 100 attempts, leaving dump at $tmpfile"
                    break
                fi
            else
                abort "[Attempt $count] Failed to write to destination: $filepath"
            fi
        done
    fi
}
rotate(){
    local db=$1
    local rotation=$2
    local demote_files=()
    local source_file="${db}-$file_date.sql.gz"
    local source="$BACKUP_PATH/$db/current/$source_file"
    local dest_dir="$BACKUP_PATH/$db/$rotation"
    local date_mask="$(get_rotate_mask $rotation)"
    debuglog "rotation_mask: $rotation=$date_mask"
    local glob_mask=${dest_dir}/${db}-${date_mask}*.sql.gz
    debuglog "glob_mask: $glob_mask"

    mkdir -p "$dest_dir" || abort "Unable mkdir $dest_dir for rotate()"

    # Promote current into rotation
    if [ -f "$source" ]; then
        log "Promoting $source into $rotation"
        cp "$source" "$dest_dir" || warn "Unable to copy $source to $dest_dir for rotate()"
    fi

    # Build a list to avoid any races
    for file in ${glob_mask[@]}; do
        if [ "${file##*/}" == "$source_file" ]; then
            break
        else
            debuglog "$file scheduled to be demoted"
            demote_files+=("$file")
        fi
    done

    # Demote (remove) older rotations of this segment
    for file in ${demote_files[@]}; do
        if [ -f "$file" ]; then
            log "Demoting $file"
            rm "$file" || warn "Unable to remove $file for rotate()"
        fi
    done
}
rotate_backups(){
    local rotations=( hourly daily weekly monthly yearly )
    local db="$1"
    for rotation in ${rotations[@]}; do
        rotate "$db" "$rotation"
    done
}
prune(){
    local dir="$BACKUP_PATH/$1/$2"
    local var="MAX_$(echo $2 | awk '{print toupper($0)}')_BACKUPS"
    local max=${!var}
    if [ "$max" -gt 0 ]; then
        local files=$(ls "$dir" | sort -rn | awk "NR > $max")
        local file
        if [ -d "$dir" ]; then
            for f in $files; do
                file="$dir/$f"
                if [ -f "$file" ]; then
                    log "Pruning $file"
                    rm "$file" || warn "Unable to remove $file for prune()"
                fi
            done
        fi
    else
        debuglog "Max backups for $2 is ${max:-"null"}, pruning skipped"
    fi
}
prune_backups(){
    local rotations=( current hourly daily weekly monthly yearly )
    local db="$1"
    for rotation in ${rotations[@]}; do
        prune "$db" "$rotation"
    done
}

file_env 'DB_HOST' 'localhost'
file_env 'DB_PORT' '3306'
file_env 'BACKUP_USER' 'root'
file_env 'BACKUP_PASSWORD' 'password'
file_env 'BACKUP_PATH' '/backups'
file_env 'BACKUP_TZ' 'UTC'
file_env 'BACKUP_DATABASES' ''
file_env 'BACKUP_DB_QUERY' "SELECT DB FROM mysql.db WHERE User NOT LIKE 'mysql.%'"
file_env 'MYSQLDUMP_OPTIONS' '--single-transaction'
file_env 'BACKUP_LOG_FILE' 'false'
file_env 'BACKUP_DEBUG_LOGGING' 'false'
file_env 'MAX_CURRENT_BACKUPS' '60'
file_env 'MAX_HOURLY_BACKUPS' '24'
file_env 'MAX_DAILY_BACKUPS' '7'
file_env 'MAX_WEEKLY_BACKUPS' '5'
file_env 'MAX_MONTHLY_BACKUPS' '12'
file_env 'MAX_YEARLY_BACKUPS' '0'
file_env 'INIT_QUERY' 'true'
file_env 'MAX_CONNECT_ATTEMPTS' '5'
file_env 'SLEEP_BETWEEN_ATTEMPTS' '3'

set_options $@

mysqldump=$(which mysqldump || abort "$0 requires mysqldump, but it was not found")
mysqladmin=$(which mysqladmin || abort "$0 requires mysqladmin, but it was not found")
gzip=$(which gzip || abort "$0 requires gzip, but it was not found")

# Avoid CLI password handling
export MYSQL_PWD=$BACKUP_PASSWORD
# Used by mysql and mysqladmin CLI
export MYSQL_TCP_PORT=$DB_PORT

if [ -z "$BACKUP_DATABASES" ]; then
    if [ "$INIT_QUERY" == "false" ] || [ -z "$BACKUP_DB_QUERY" ]; then
        log "BACKUP_DATABASES=${BACKUP_DATABASES:-null} INIT_QUERY=${INIT_QUERY:-null} and BACKUP_DB_QUERY=${BACKUP_DB_QUERY:-null}"
        abort "INIT_QUERY must be enabled and have a valid BACKUP_DB_QUERY if BACKUP_DATABASES is not specified."
    fi
else
    BACKUP_DATABASES="${BACKUP_DATABASES//$'/'/$'\n'}"
    BACKUP_DB_QUERY="SELECT true"
fi

# Wait until we get a ping from the database
wait_for_db

if [ "$INIT_QUERY" != "false" ]; then
    BACKUP_DB_QUERY="${BACKUP_DB_QUERY:-'SELECT true'}"
    connect_attempt=0
    debuglog "Sending '$BACKUP_DB_QUERY' to '$BACKUP_USER@$DB_HOST:$DB_PORT'"
    while [ "$dbexit" != "0" ]; do
        connect_attempt=$((connect_attempt + 1))
        if [ "$connect_attempt" -gt "$MAX_CONNECT_ATTEMPTS" ]; then
            abort "Failed $MAX_CONNECT_ATTEMPTS attempts to connect to $BACKUP_USER@$DB_HOST:$DB_PORT"
        fi
        if [ "$connect_attempt" -gt "1" ]; then
            log "Attempt $connect_attempt/$MAX_CONNECT_ATTEMPTS: Unable to query $BACKUP_USER@$DB_HOST:$DB_PORT"
            sleep $SLEEP_BETWEEN_ATTEMPTS
            printf '%s' "Attempt $connect_attempt/$MAX_CONNECT_ATTEMPTS - "
            wait_for_db
        fi
        set +e
        db_response=$(mysql -h"$DB_HOST" -u"$BACKUP_USER" -N -e "$BACKUP_DB_QUERY")
        dbexit=$?
        set -e
    done
fi

BACKUP_DATABASES="${BACKUP_DATABASES:-${db_response:-$(abort 'Unable to find any databases to backup')}}"
debuglog BACKUP_DATABASES="${BACKUP_DATABASES//$'\n'/$'/'}" # Replace newlines with / delim for log readability

# Cache backup set datestamp
full_date=$(TZ=$BACKUP_TZ date '+%Y-%m-%d %H:%M:%S %Z' || abort "Unable to obtain current date")
file_date=$(TZ=$BACKUP_TZ date -d "$full_date" '+%Y%m%dw%W-%H%M%S' || abort "Unable to format datestamp '$full_date' for file")
current_hour=$(TZ=$BACKUP_TZ date -d "$full_date" '+%H' || abort "Unable to detect hour from timestamp '$full_date'")
current_day=$(TZ=$BACKUP_TZ date -d "$full_date" '+%d' || abort "Unable to detect day from timestamp '$full_date'")
current_week=$(TZ=$BACKUP_TZ date -d "$full_date" '+w%W' || abort "Unable to detect week from timestamp '$full_date'")
current_month=$(TZ=$BACKUP_TZ date -d "$full_date" '+%m' || abort "Unable to detect month from timestamp '$full_date'")
current_year=$(TZ=$BACKUP_TZ date -d "$full_date" '+%Y' || abort "Unable to detect month from timestamp '$full_date'")
debuglog "full_date=$full_date"
debuglog "file_date=$file_date"
debuglog "year=$current_year month=$current_month day=$current_day week=$current_week hour=$current_hour"

# Backup all databases before any rotations or pruning
for dbname in $BACKUP_DATABASES; do
    timer_start=$(date '+%s.%N')
    dump "$dbname"
    timer_end=$(printf '%s' "$timer_start $(date '+%s.%N')" | awk '{ printf "%f", $2 - $1 }')
    log "Dumping $dbname took $timer_end seconds"
done

# Finish all backups first, then worry about rotations and pruning
for dbname in $BACKUP_DATABASES; do
    timer_start=$(date '+%s.%N')
    rotate_backups "$dbname"
    timer_end=$(printf '%s' "$timer_start $(date '+%s.%N')" | awk '{ printf "%f", $2 - $1 }')
    log "Rotating $dbname took $timer_end seconds"
    timer_start=$(date '+%s.%N')
    prune_backups "$dbname"
    timer_end=$(printf '%s' "$timer_start $(date '+%s.%N')" | awk '{ printf "%f", $2 - $1 }')
    log "Pruning $dbname took $timer_end seconds"
done
script_end=$(printf '%s' "$script_start $(date '+%s.%N')" | awk '{ printf "%f", $2 - $1 }')
log "$0 took $script_end seconds"
