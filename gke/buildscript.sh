#!/usr/bin/env bash

set -eEo pipefail
export COMPOSER_MEMORY_LIMIT=-1
COMPOSER_OPTIONS="--no-progress --optimize-autoloader"

function main {
    install_dependencies "$1"
    install_health_check
    cleanup
}

function install_dependencies {
    [[ "$1" != "testing" ]] && \
        local nodev="--no-dev"

    composer install $COMPOSER_OPTIONS $nodev
}

function install_health_check {
    if ! grep -q '"drupal/health_check"' "composer.json"
    then
        composer require 'drupal/health_check:^1.0' $COMPOSER_OPTIONS
    fi
    # Small hack - add info the health output so we can see which specific POD is answering
    sed -i "s/response->setContent(time());/response->setContent(time() . ' TAG: ' . getenv('TAG') . ' HOSTNAME: ' . getenv('HOSTNAME'));/g" web/modules/contrib/health_check/src/Controller/HealthController.php
}

function cleanup {
    rm -rf ~/.composer
}

main "$@"