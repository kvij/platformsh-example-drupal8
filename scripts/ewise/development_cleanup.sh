#!/usr/bin/env bash
#
# Description:
#   This script ensures the development environment is pristine and that the site is in sync with
#   the files on disk.
#   It should be run whenever changes are made in the repo that is not content.
#
# WARNING: Make sure you export and commit any content before running this script

function main {
    cd $LANDO_MOUNT

    case $1 in
        ""|"soft"|"--soft")
            echo "WARNING this command will destroy unexported configuration and managed content changes. Please export and commit changes you want to keep."
            areYouShure
            softReset
            echo "If the development environment is still not consistent please do 'lando apply force'"
        ;;
        "force"|"--force"|"forced"|"--hard"|"hard")
            echo "WARNING this command will destroy unexported and uncommited content, configuration and code. Please export and commit changes you want to keep."
            areYouShure
            hardReset
            echo "If the development environment is still not consistent please do 'lando destroy; lando start'"
        ;;
        "build-steps-only")
            echo "Updating database from files"
            commonBuildTasks
        ;;
        *)
            echo "USAGE: lando apply [force]"
            exit 1
        ;;
    esac
}

function areYouShure {
    read -p "Are you sure you want to continue? (y/N) " -n 1 -r REPLY
    echo    # move to a new line
    [[ $REPLY =~ ^[Yy]$ ]] || exit 0 # Aborted
}

function softReset {
    # Clean git workdir
    git clean --interactive

    # Sync site with config in files
    commonBuildTasks
}

function hardReset {
    # Clean git workdir
    git reset --hard
    git clean -d --force

	# Reset database to last export
    mysql --host=database --user=drupal8 --password=drupal8 -e "DROP DATABASE drupal8;"
    mysql --host=database --user=drupal8 --password=drupal8 -e "CREATE DATABASE IF NOT EXISTS drupal8;"
    gunzip -c /app/default.sql.gz | mysql --host=database --user=drupal8 --password=drupal8 drupal8

    # Sync site with config in files
    commonBuildTasks
}

function commonBuildTasks {
    composer install
	drush -y cache-rebuild
	drush -y updatedb
	drush -y config-import
	drush -y entup
    if drush pm:list --status=enabled --type=module --no-core --fields=name | grep -q 'default_content_deploy'
    then
        drush -y default-content-deploy:import --force-update
        drush -y cache-rebuild
    fi
}

main "$@"
