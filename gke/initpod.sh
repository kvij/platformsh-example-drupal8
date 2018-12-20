#!/usr/bin/env bash
date
STATEFILE="private/tmp$COMMIT_ID"
if [[ ! -f "$STATEFILE" ]] || grep -q FAILED "$STATEFILE"; then
     rm private/tmp*
     touch "private/tmp${COMMIT_ID}"
     echo "#### Will update drupal database ####"
else
    PROCESSED=true
    echo "-No drupal database update - already started-"
fi

echo '### Copying repo to /var/www/html ###';
time -f '#time: %e sec' cp -r /usr/src/app/. /var/www/html;
mv web/index.php web/index.wait  ### Get ready when all database updates have been run
cd /var/www/html

if [[ -z ${PROCESSED} ]]; then
  echo "start the database update"
  /bin/sh gke/dbupdate.sh >dbupdate.log 2>&1
  echo "Send update log file to slack"
  curl https://slack.com/api/files.upload -F token="$SLACK_BOT_TOKEN" -F channels="build" -F title="Updating $REPO_NAME$ENVIRONMENT database" -F filename="dbupdate.log" -F file=@"/var/www/html/dbupdate.log"
  date
else
  echo '### composer install --no-dev  ###';
  time -f '#time: %e sec' composer install --no-dev --no-progress 2>&1 | grep -v '^ '

  ### Small hack - add info the health output so we can see which specific POD is answering
  sed -i "s/response->setContent(time());/response->setContent(time() . ' TAG: ' . getenv('TAG') . ' HOSTNAME: ' . getenv('HOSTNAME'));/g" web/modules/contrib/health_check/src/Controller/HealthController.php

  while grep -qv SUCCESS "$STATEFILE" # Wait until database update is successfully done
  do
    sleep 2
  done
  mv web/index.wait web/index.php
  date
fi
# Run cron daemon
sudo -E /usr/sbin/crond
