<?php
/**
 * @file
 * Lando settings.
 */

// Configure the database if on Lando
// @todo: eventually we want to remove this in favor of Lando directly
// spoofing the needed PLATFORM_* envvars.
if (isset($_SERVER['LANDO'])) {

  // Set the database creds
  $databases['default']['default'] = [
    'database' => 'drupal8',
    'username' => 'drupal8',
    'password' => 'drupal8',
    'host' => 'database',
    'port' => '3306',
    'driver' => 'mysql'
  ];

  // And a bogus hashsalt for now
  $settings['hash_salt'] = json_encode($databases);

  // Set host pattern to default lando HTTP HOSTS
  $settings['trusted_host_patterns'] = [
    '^localhost$',
    '\.lndo\.site$',
    '\.localtunnel\.me$',
    '^appserver$',
  ];

  // Enable development config
  $settings['container_yamls'][] = $app_root . '/' . $site_path . '/development.services.yml';
  $config['config_split.config_split.development']['status'] = TRUE; // NOTE: D8Base does not contain the actual configuration
}
