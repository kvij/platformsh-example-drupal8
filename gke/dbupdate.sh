#!/usr/bin/env bash
set -eE
date
STATEFILE="private/tmp$COMMIT_ID"
trap "echo FAILED > ${STATEFILE}" ERR

printf '\n*************** COMMIT MESSAGE **************\n'
cat commitmsg
printf '*********************************************\n'
printf "Variables: \n"
printf " # REPO_NAME=%s\n # ENVIRONMENT=%s\n # BRANCH_NAME=%s\n" "$REPO_NAME" "$ENVIRONMENT" "$BRANCH_NAME"
printf " # REPLICAS=%s\n # COMMIT_ID=%s\n # TAG=%s\n" "$REPLICAS" "$COMMIT_ID" "$TAG"
printf '\n###  composer install --no-dev  ###\n';
time -f '#time: %e sec' composer install --no-dev --no-progress 2>&1 | grep -v '^ '

frintf '\n### Install and enable health check ###\n'
time -f '#time: %e sec' composer require  'drupal/health_check:^1.0' --no-progress 2>&1 | grep -v '^ '
# Small hack - add info the health output so we can see which specific POD is answering
sed -i "s/response->setContent(time());/response->setContent(time() . ' TAG: ' . getenv('TAG') . ' HOSTNAME: ' . getenv('HOSTNAME'));/g" web/modules/contrib/health_check/src/Controller/HealthController.php
time -f '#time: %e sec' drush pm-enable health_check -y

printf '\n### Do database updates ###\n'
time -f '#time: %e sec' drush updatedb -y
printf '\n### Apply entity updates ###\n'
time -f '#time: %e sec' drush entup -y
####
printf '\n### Import configuration ###\n'
# Import config twice when config_split is not yet enabled
drush pm:list --status=enabled --type=module --no-core --fields=name | grep -q 'config_split' \
  || time -f '#time: %e sec' drush config:import -y
time -f '#time: %e sec' drush config:import -y
####
# Guard against accidental test content imports
if [[ -n "$ENVIRONMENT" ]] && [[ "$ENVIRONMENT" != "stageing" ]] && [[ "$ENVIRONMENT" != "production" ]]
then
  if drush pm:list --status=enabled --type=module --no-core --fields=name | grep -q 'default_content_deploy'
  then
    printf '\n### Importing content ###\n'
    time -f '#time: %e sec' drush default-content-deploy:import --force-update -y
  fi
fi
####
printf '\n### DB work all done - let other new pods know they can start serving ###\n';
echo 'SUCCESS' > "$STATEFILE"
touch private/cron.done
mv web/index.wait web/index.php
date