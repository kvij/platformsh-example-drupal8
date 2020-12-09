#!/usr/bin/env bash

set -eEo pipefail
export COMPOSER_MEMORY_LIMIT=-1

function main {
    install_dependencies
    install_health_check
    cleanup
}

function install_dependencies {
    composer install --no-progress --optimize-autoloader
}

function install_health_check {
    if ! grep -q '"drupal/health_check"' "composer.json"
    then
        composer require  'drupal/health_check:^1.0' --no-progress --optimize-autoloader
    fi
    # Small hack - add info the health output so we can see which specific POD is answering
    sed -i "s/response->setContent(time());/response->setContent(time() . ' TAG: ' . getenv('TAG') . ' HOSTNAME: ' . getenv('HOSTNAME'));/g" web/modules/contrib/health_check/src/Controller/HealthController.php
}

function cleanup {
    rm -rf ~/.composer
}

main "$@"