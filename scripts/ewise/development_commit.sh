#!/usr/bin/env bash

function main {
  cd $LANDO_MOUNT

    case $1 in
        "")
            areYouShure "Do you want to export the configuration" y false && \
                drush -y config-export

            if drush pm:list --status=enabled --type=module --no-core --fields=name | grep -q 'default_content_deploy'
            then
                areYouShure "Do you want to export the content" y false && \
                    drush -y default-content-deploy:export
            fi

            areYouShure "Do you want update default.sql.gz? When unsure the answer is no" n false && \
                mysqldump --host=database --user=drupal8 --password=drupal8 drupal8 | gzip > default.sql.gz

            git add .
            git status
            areYouShure "Are these the files you want to commit?" n resetAndQuit
            read -p "Your changes will be shown press 'q' to exit review mode. Press any key to continue" -n 1 -r
            git diff --staged
            areYouShure "Is everything you the way you want it to be?" n resetAndQuit
            git commit
        ;;
        *)
            echo -e "USAGE: lando commit"
            exit 1
        ;;
    esac
}

function areYouShure { # question default action
    local question=${1:-Are you sure you want to continue?}
    local abortAction="${3:-exit 0}"

    if [[ "$2" = "y" ]]
    then
        read -p "$question (Y/n) " -n 1 -r REPLY
        echo    # move to a new line
        [[ -z $REPLY ]] || [[ $REPLY =~ ^[Yy]$ ]] || $abortAction
    else
        read -p "$question (y/N) " -n 1 -r REPLY
        echo    # move to a new line
        [[ $REPLY =~ ^[Yy]$ ]] || $abortAction
    fi
}

function resetAndQuit {
    git reset
    exit 0
}

main "$@"