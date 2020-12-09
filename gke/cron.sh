#!/usr/bin/env bash
# Run crontab on all pods (every 15 minutes) but only run drupal cron on one pod
cd /var/www/html/
sleep $(( ( RANDOM % 20 )  + 1 ))
if test `find "private/cron.done" -mmin +12`
then
  touch private/cron.done
  /usr/local/bin/drupal cre > private/cron.done
fi