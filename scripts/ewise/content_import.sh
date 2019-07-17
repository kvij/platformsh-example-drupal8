#!/usr/bin/env bash

set -eEo pipefail

cd $LANDO_MOUNT
[[ -f '.content_import' ]] && source .content_import

USER=${USER:-"replicator"}
HOST=${HOST:-"rsync.e-wise.io"}
NFS_DIR=${NFS_DIR:-"/mnt"}
PROJECT=${PROJECT:-"$LANDO_APP_PROJECT"}
ENVIRONMENT=${ENVIRONMENT:-"staging"}

function main {
    echo "By importing content from upstream all your current custom content and not exported settings will be lost."
    areYouShure

    fetchFiles
    importDB
    importLocalConfig

    echo "*** All done, enjoy the $ENVIRONMENT content ***"
}

function fetchFiles {
    local source="$USER@$HOST:$NFS_DIR/$PROJECT/$ENVIRONMENT"
    local options="--archive --delete --human-readable --progress"

    echo '*** Updating private files ***'
    rsync $options "$source/private/" private/
    echo '*** Updating public files ***'
    rsync $options "$source/files/" web/sites/default/files/
}

function importDB {
    echo '*** Prepping database ***'
    mysql --host=database --user=drupal8 --password=drupal8 -e "DROP DATABASE drupal8;"
    mysql --host=database --user=drupal8 --password=drupal8 -e "CREATE DATABASE IF NOT EXISTS drupal8;"
    echo '*** Import database from fetched backup ***'
    gunzip -c private/backup_migrate/backup.mysql.gz | mysql --host=database --user=drupal8 --password=drupal8 drupal8
}

function importLocalConfig {
    echo '*** Import development configuration ***'
    drush config:import --yes
}

function areYouShure {
    read -p "Are you sure you want to continue? (y/N) " -n 1 -r REPLY
    echo    # move to a new line
    [[ $REPLY =~ ^[Yy]$ ]] || exit 0 # Aborted
}

main "$@"