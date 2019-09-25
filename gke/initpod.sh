#!/usr/bin/env bash

set -eEo pipefail
APP_SRC='/usr/src/app'
APP_ROOT='/var/www/html'
LOG_FILE="$APP_ROOT/initpod.log"

# Abort when something goes wrong
trap abort ERR
# Unlock other pods and start serving on normal exit
trap unlock EXIT

cd "$APP_ROOT"

function main {
    print_header
    detect_environment
    updater_lock
    prepare_src
    install_dependencies
    install_health_check
    if [[ -n "$SITE_UPDATER" ]]; then
        clear_cache
        update_database
        import_config
        import_content
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

# Set up additional environment info
function detect_environment {
    if [[ -n "$ENVIRONMENT" ]] && [[ "$ENVIRONMENT" != "staging" ]] && [[ "$ENVIRONMENT" != "prod" ]]
    then
        DEVELOPMENT_ENVIRONMENT='TRUE'
    fi
}

# Copy source to ephemeral storage
function prepare_src {
    log "### Copying repo content to $APP_ROOT ###"
    if [[ -n "$DEVELOPMENT_ENVIRONMENT" ]]
    then
        logt cp -r "$APP_SRC/." "$APP_ROOT"
    else
        logt rsync -qr --exclude-from="$APP_SRC/gke/rsync-prod.exclude" "$APP_SRC/" "$APP_ROOT"
    fi
    mv 'web/index.php' 'web/index.wait'  # Be unhealthy until site update tasks are completed
}

function install_dependencies {
    if [[ -n "$DEVELOPMENT_ENVIRONMENT" ]]
    then
        logf '\n###  composer install ###\n';
        logt composer install --no-progress --optimize-autoloader
    else
        logf '\n###  composer install --no-dev  ###\n';
        logt composer install --no-dev --no-progress --optimize-autoloader
    fi
}

function install_health_check {
    logf '\n### Install and patch health check module ###\n'
    if ! grep -q '"drupal/health_check"' "$APP_ROOT/composer.json"
    then
        logt composer require  'drupal/health_check:^1.0' --no-progress --optimize-autoloader
    fi
    # Small hack - add info the health output so we can see which specific POD is answering
    sed -i "s/response->setContent(time());/response->setContent(time() . ' TAG: ' . getenv('TAG') . ' HOSTNAME: ' . getenv('HOSTNAME'));/g" web/modules/contrib/health_check/src/Controller/HealthController.php
}

function update_database {
    if [[ -n "$DEVELOPMENT_ENVIRONMENT" ]]
    then
        logf '\n### Importing default.sql.gz ###\n'
        loge mysql --host="$DB_HOST" --user="$DB_USER" --password="$DB_PASSWORD" -e 'DROP DATABASE IF EXISTS `'"$DB_NAME"'`; CREATE DATABASE `'"$DB_NAME"'`;'
        gunzip -c "$APP_SRC/default.sql.gz" | mysql --host="$DB_HOST" --user="$DB_USER" --password="$DB_PASSWORD" "$DB_NAME" 2>&1 | tee -a "$LOG_FILE"
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

function import_content {
    # Guard against accidental test content imports
    if [[ -n "$DEVELOPMENT_ENVIRONMENT" ]]
    then
        if drush pm:list --status=enabled --type=module --no-core --fields=name | grep -q 'default_content_deploy'
        then
            logf '\n### Importing content ###\n'
            logt drush default-content-deploy:import --force-update -y
        fi
    fi
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
        SITE_UPDATER='TRUE'
        log "#### Additional Drupal update tasks will be performed ####"
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
    mv web/index.wait web/index.php
    if [[ -n "$SITE_UPDATER" ]]; then
        logf '\n### Website update tasks done - let other new pods know they can start serving ###\n';
        mysql --host="$DB_HOST" --user="$DB_USER" --password="$DB_PASSWORD" -e 'USE `'"$DB_NAME"'`; UPDATE `_gke_init` SET `state` = "SUCCESS" WHERE commit = "'"$SHORT_SHA"'"'
    fi
    log 'Starting cron daemon'
    sudo -E /usr/sbin/crond
    loge date
    send_log
}

function abort {
    trap - EXIT
    mysql --host="$DB_HOST" --user="$DB_USER" --password="$DB_PASSWORD" -e 'USE `'"$DB_NAME"'`; UPDATE `_gke_init` SET `state` = "FAILED" WHERE commit = "'"$SHORT_SHA"'"'
    log "Aborting..."
    send_log
    exit 0
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

    # Composer less verbose hack
    if [[ "$1" = 'composer' ]] || [[ "$4" = 'composer' ]]
    then
        "$@" 2>&1 | grep -v '^ ' | tee "$tee_options" "$LOG_FILE"
    else
        "$@" 2>&1 | tee "$tee_options" "$LOG_FILE"
    fi
}

function send_log {
    [[ -n "$SITE_UPDATER" ]] &&
        curl https://slack.com/api/files.upload -F token="$SLACK_BOT_TOKEN" -F channels="build" -F title="Updating $REPO_NAME$ENVIRONMENT database" -F filename="initpod.log" -F file=@"$LOG_FILE" -F filetype="text"

    return 0 # Prevents accidental return 1 when test is false
}

main "$@"
