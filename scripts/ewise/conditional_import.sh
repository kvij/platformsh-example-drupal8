#!/usr/bin/env bash
# Description: Import database from a gzipped sql file when there is previously no filled Drupal database present.
# Author: Karel van IJperen

# Test for presence of nessary environment variables
if [[ -z $MYSQL_USER ]] || [[ -z $MYSQL_PASSWORD ]] || [[ -z $MYSQL_DATABASE ]]
then
  echo 'ERROR: $MYSQL_USER, $MYSQL_PASSWORD and $MYSQL_DATABASE have to be set'
  exit 1
fi

# Load the path to the .sql.gz file from the first argument and fallback to default
file_name=$1
[[ -z $file_name ]] && file_name='default.sql.gz'

# Only import when $MYSQL_DATABASE/config does not exists.
if ! mysql --user=$MYSQL_USER --password=$MYSQL_PASSWORD -e 'SELECT 1 FROM config LIMIT 1;' $MYSQL_DATABASE > /dev/null 2>&1
then
  # Test for pressence of the .sql.gz file
  [[ ! -f $file_name ]] && echo "'$file_name' does not exist skipping database import..." && exit 0

  echo "Importing $file_name into $MYSQL_DATABASE"
  mysql --user=$MYSQL_USER --password=$MYSQL_PASSWORD -e "CREATE DATABASE IF NOT EXISTS $MYSQL_DATABASE;"
  gunzip -c $file_name | mysql --user=$MYSQL_USER --password=$MYSQL_PASSWORD $MYSQL_DATABASE
fi

exit 0