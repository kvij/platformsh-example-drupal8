#!/usr/bin/env bash

set -eEo pipefail
APP_SRC='/usr/src/app'
APP_ROOT='/var/www/html'
LOG_FILE="$APP_ROOT/initpod.log"
STATE_FILE="$APP_ROOT/private/tmp$COMMIT_ID.state"

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
        update_database
        import_config
        import_content
    fi
    updater_wait
}

function print_header {
    date
    logf '\n*************** COMMIT MESSAGE **************\n'
    loge cat "$APP_SRC/commitmsg"
    logf '*********************************************\n'
    logf "Variables: \n"
    logf " # REPO_NAME=%s\n # ENVIRONMENT=%s\n # BRANCH_NAME=%s\n" "$REPO_NAME" "$ENVIRONMENT" "$BRANCH_NAME"
    logf " # REPLICAS=%s\n # COMMIT_ID=%s\n # TAG=%s\n" "$REPLICAS" "$COMMIT_ID" "$TAG"
}

# Set up additional environment info
function detect_environment {
    if [[ -n "$ENVIRONMENT" ]] && [[ "$ENVIRONMENT" != "staging" ]] && [[ "$ENVIRONMENT" != "production" ]]
    then
        DEVELOPMENT_ENVIRONMENT='TRUE'
    fi
}

# Copy source to ephemeral storage
function prepare_src {
    log "### Copying repo content to $APP_ROOT ###"
    logt cp -r "$APP_SRC/." "$APP_ROOT"
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
    logt composer require  'drupal/health_check:^1.0' --no-progress --optimize-autoloader
    # Small hack - add info the health output so we can see which specific POD is answering
    sed -i "s/response->setContent(time());/response->setContent(time() . ' TAG: ' . getenv('TAG') . ' HOSTNAME: ' . getenv('HOSTNAME'));/g" web/modules/contrib/health_check/src/Controller/HealthController.php
}

function update_database {
    logf '\n### Do database updates ###\n'
    logt drush updatedb -y
    logf '\n### Apply entity updates ###\n'
    logt drush entup -y
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
    if [[ ! -f "$STATE_FILE" ]] || grep -q 'FAILED' "$STATE_FILE"; then
        rm -f "$(dirname "$STATE_FILE")/"*".state" # Remove older statefiles
        truncate -s 0 "$STATE_FILE"
        SITE_UPDATER='TRUE'
        log "#### Additional Drupal update tasks will be performed ####"
    else
        log "Skipping already started update tasks"
    fi
}

# Wait until Drupal update tasks are done
function updater_wait {
    [[ -n "$SITE_UPDATER" ]] && return # Updater does must not wait on itself
    while grep -qv SUCCESS "$STATE_FILE"
    do
        sleep 2
    done
}

function unlock {
    touch private/cron.done
    mv web/index.wait web/index.php
    if [[ -n "$SITE_UPDATER" ]]; then
        logf '\n### Website update tasks done - let other new pods know they can start serving ###\n';
        echo 'SUCCESS' > "$STATE_FILE"
    fi
    log 'Starting cron daemon'
    sudo -E /usr/sbin/crond
    date
    send_log
}

function abort {
    trap - EXIT
    echo 'FAILED' > "$STATE_FILE"
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
        curl https://slack.com/api/files.upload -F token="$SLACK_BOT_TOKEN" -F channels="build" -F title="Updating $REPO_NAME$ENVIRONMENT database" -F filename="initpod.log" -F file=@"$LOG_FILE"
}

main "$@"