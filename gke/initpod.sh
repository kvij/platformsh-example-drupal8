#!/usr/bin/env bash

set -eEo pipefail
APP_ROOT='/var/www/html'
SHARE_ROOT='/mnt/share'
LOG_FILE="/tmp/initpod.log"

# Abort when something goes wrong
trap abort ERR
# Unlock other pods and start serving on normal exit
trap unlock EXIT

# Init-container skips the entrypoint. The entrypoint configures php.ini based on env.
/docker-entrypoint.sh

function main {
    cd "$APP_ROOT"
    cloud_sql_proxy
    print_header
    detect_environment
    updater_lock
    prepare_src
    if [[ -n "$SITE_UPDATER" ]]; then
        #clear_cache
        update_database
        import_config
    fi
    updater_wait
}

function print_header {
    loge date
    logf '\n*************** COMMIT MESSAGE **************\n'
    log  "$COMMITMSG"
    logf '*********************************************\n'
    logf "Variables: \n"
    logf " # REPO_NAME=%s\n # ENVIRONMENT=%s\n # BRANCH_NAME=%s\n" "$REPO_NAME" "$ENVIRONMENT" "$BRANCH_NAME"
    logf " # REPLICAS=%s\n # COMMIT_ID=%s\n # TAG=%s\n" "$REPLICAS" "$SHORT_SHA" "$TAG_NAME"
}

function cloud_sql_proxy {
    # Support old and new cluster. FIXME: Remove credential.json support after migration
    local cloudsql_auth_option='-ip_address_types=PRIVATE'
    local cloudsql_instances='kuberdrupal:europe-west4:cloudmysql=tcp:3306'
    if [[ -f "/secrets/cloudsql/credentials.json" ]]
    then
        cloudsql_auth_option='-credential_file=/secrets/cloudsql/credentials.json'
    else
	      cloudsql_instances="$cloudsql_instances,${cloudsql_instances//tcp:/tcp6:}"
    fi

    /cloud_sql_proxy -dir=/cloudsql -verbose=false -instances="$cloudsql_instances" \
        "$cloudsql_auth_option" &

    while ! nc -z -w1 localhost 3306; do
      sleep 0.2
    done
}

# Set up additional environment info
function detect_environment {
    if [[ -n "$ENVIRONMENT" ]] && [[ "$ENVIRONMENT" = "testing" ]]
    then
        DEVELOPMENT_ENVIRONMENT='TRUE'
    fi
}

# Copy web files to ephemeral storage
function prepare_src {
    log "### Copying repo content to $SHARE_ROOT ###"
    mkdir -p "web/sites/default/files" \
        "$SHARE_ROOT/web/sites/default/files" "$SHARE_ROOT/private" "$SHARE_ROOT/config" "$SHARE_ROOT/keys"
    cp 'gke/nginx.conf' "$SHARE_ROOT/config/"
    mv web/sites/default/files .
    logt rsync -qr --prune-empty-dirs --include-from="gke/rsync-web.include" --exclude='*' "web" "$SHARE_ROOT/"
    if [[ -n "$DEVELOPMENT_ENVIRONMENT" ]]
    then
        logt cp -r "files" "$SHARE_ROOT/web/sites/default"
        logt cp -r "private" "$SHARE_ROOT"
    fi

    [[ -e '/etc/secret-mounts/keys' ]] && logt cp -r '/etc/secret-mounts/keys' "$SHARE_ROOT"

    logf "\n### Fix ownership and permissions of $SHARE_ROOT ###\n"
    loge chown -R www-data:www-data $SHARE_ROOT
    loge chmod -R ug+ws "$SHARE_ROOT/web/sites/default/files" "$SHARE_ROOT/private"
    loge chmod -R go=,u=rwX "$SHARE_ROOT/keys"
}

function update_database {
    if [[ -n "$DEVELOPMENT_ENVIRONMENT" ]]
    then
        logf '\n### Importing default.sql.gz ###\n'
        loge mysql --host="$DB_HOST" --user="$DB_USER" --password="$DB_PASSWORD" -e 'DROP DATABASE IF EXISTS `'"$DB_NAME"'`; CREATE DATABASE `'"$DB_NAME"'`;'
        gunzip -c "default.sql.gz" | mysql --host="$DB_HOST" --user="$DB_USER" --password="$DB_PASSWORD" "$DB_NAME" 2>&1 | tee -a "$LOG_FILE"
        updater_lock
    fi

    logf '\n### Do database updates ###\n'
    logt drush updatedb -y
}

function clear_cache {
    logf '\n### Clear cache ###\n'
    logt drush -y cache-rebuild
}

function import_config {
    logf '\n### Import configuration ###\n'
    # Import config twice when config_split is not yet enabled
    drush pm:list --status=enabled --type=module --no-core --fields=name | grep -q 'config_split' \
      || logt drush config:import -y
    logt drush config:import -y
    logf '\n### Enable health_check ###\n'
    logt drush pm-enable health_check -y
}

function updater_lock {
    loge mysql --host="$DB_HOST" --user="$DB_USER" --password="$DB_PASSWORD" -e 'USE `'"$DB_NAME"'`; CREATE TABLE IF NOT EXISTS `_gke_init` (`id` int(10) unsigned NOT NULL AUTO_INCREMENT, `commit` varchar(50) NOT NULL, `state` varchar(50) DEFAULT NULL, `timestamp` datetime DEFAULT NULL, UNIQUE(`commit`), PRIMARY KEY (`id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8;'

    log '### Test for already existing site updating pod or become one ###'
    if mysql --host="$DB_HOST" --user="$DB_USER" --password="$DB_PASSWORD" -e 'USE `'"$DB_NAME"'`; INSERT INTO `_gke_init`	VALUES (0,"'"$SHORT_SHA"'","UPDATING", NOW())' 2>/dev/null
    then
        SITE_UPDATER='TRUE'
        log "#### Additional Drupal update tasks will be performed ####"

    # Check for previous failed state
    elif mysql -sN --host="$DB_HOST" --user="$DB_USER" --password="$DB_PASSWORD" -e 'USE `'"$DB_NAME"'`; SELECT `state` FROM `_gke_init` WHERE commit = "'"$SHORT_SHA"'"' | grep -q 'FAILED'
    then
        loge mysql --host="$DB_HOST" --user="$DB_USER" --password="$DB_PASSWORD" -e 'USE `'"$DB_NAME"'`; DELETE FROM `_gke_init` WHERE commit = "'"$SHORT_SHA"'" AND `state` = "FAILED"'
        updater_lock
    else
        log "Skipping already started update tasks"
    fi
}

# Wait until Drupal update tasks are done
function updater_wait {
    [[ -n "$SITE_UPDATER" ]] && return # Updater does must not wait on itself
    while mysql -sN --host="$DB_HOST" --user="$DB_USER" --password="$DB_PASSWORD" -e 'USE `'"$DB_NAME"'`; SELECT `state` FROM `_gke_init` WHERE commit = "'"$SHORT_SHA"'"' | grep -qv 'SUCCESS'
    do
        sleep 2
    done
}

function unlock {
    touch private/cron.done
    if [[ -n "$SITE_UPDATER" ]]; then
        logf '\n### Website update tasks done - let other new replicas know they can start serving ###\n';
        mysql --host="$DB_HOST" --user="$DB_USER" --password="$DB_PASSWORD" -e 'USE `'"$DB_NAME"'`; UPDATE `_gke_init` SET `state` = "SUCCESS" WHERE commit = "'"$SHORT_SHA"'"'
    fi
    loge date
    send_log
}

function abort {
    trap - EXIT
    mysql --host="$DB_HOST" --user="$DB_USER" --password="$DB_PASSWORD" -e 'USE `'"$DB_NAME"'`; UPDATE `_gke_init` SET `state` = "FAILED" WHERE commit = "'"$SHORT_SHA"'"'
    log "Aborting..."
    send_log
    sleep 1800 # Keep container alive for debugging
    exit 1
}

# Log to STDOUT and a logfile
function log {
    loge echo "$@"
}

# Formatted log entry like printf
function logf {
    loge printf "$@"
}

# Time the command in parameters and output the runtime
function logt {
    loge /usr/bin/time -f '#time: %e sec' "$@"
}

# Execute command in parameters and log the output to STDOUT and a logfile
# The file is truncated at every run of the script
function loge {
    local tee_options='-a'

    if [[ -z "$APPEND_LOG" ]]
    then
        tee_options='--'
        APPEND_LOG='TRUE'
    fi

    "$@" 2>&1 | tee "$tee_options" "$LOG_FILE"
}

function send_log {
    [[ -n "$SITE_UPDATER" ]] &&
        curl https://slack.com/api/files.upload -F token="$SLACK_BOT_TOKEN" -F channels="build" -F title="Updating $REPO_NAME$ENVIRONMENT database" -F filename="initpod.log" -F file=@"$LOG_FILE" -F filetype="text"

    return 0 # Prevents accidental return 1 when test is false
}

main "$@"
