#!/usr/bin/env bash
# Description: Import database from a gzipped sql file when there is previously no filled Drupal database present.
# Author: Karel van IJperen

# Set up default db credentials for the Lando Drupal appserver container
: ${MYSQL_USER:=drupal8}
: ${MYSQL_PASSWORD:=drupal8}
: ${MYSQL_DATABASE:=drupal8}
: ${MYSQL_HOST:=database}

# Load the path to the .sql.gz file from the first argument and fallback to default
file_name=${1:-default.sql.gz}

# Database server might be started but not completely ready. Wait for it.
mysql --host="$MYSQL_HOST" --user="$MYSQL_USER" --password="$MYSQL_PASSWORD" -e 'SELECT 1;' > /dev/null 2>&1 || sleep 4;

# Only import when $MYSQL_DATABASE/config does not exists.
if ! mysql --host="$MYSQL_HOST" --user="$MYSQL_USER" --password="$MYSQL_PASSWORD" -e 'SELECT 1 FROM config LIMIT 1;' "$MYSQL_DATABASE" > /dev/null 2>&1
then
  # Test for pressence of the .sql.gz file
  [[ ! -f $file_name ]] && echo "'$file_name' does not exist skipping database import..." && exit 0

  echo "Importing $file_name into $MYSQL_DATABASE"
  mysql --host="$MYSQL_HOST" --user="$MYSQL_USER" --password="$MYSQL_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS $MYSQL_DATABASE;"
  gunzip -c $file_name | mysql --host="$MYSQL_HOST" --user="$MYSQL_USER" --password="$MYSQL_PASSWORD" "$MYSQL_DATABASE"
  scripts/ewise/development_cleanup.sh build-steps-only
fi

exit 0