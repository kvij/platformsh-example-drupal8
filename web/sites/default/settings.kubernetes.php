<?php
/**
 * @file
 * Google Cloud Platform settings.
 */

 // Configure the database if on Kubernetes
if (getenv('KUBER')) {
  $databases['default']['default'] = [
    'database' => getenv('DB_NAME'),
    'username' => getenv('DB_USER'),
    'password' => getenv('DB_PASSWORD'),
    'host' => (string) getenv('DB_HOST'),
    'port' => (string) getenv('DB_PORT'),
    'driver' => 'mysql'
  ];

  // bogus hashsalt for now
  $settings['hash_salt'] = json_encode($databases);

  $settings['trusted_host_patterns'] = [
    '.*'  // Can be a wildcard because the site (pods) can only be reached via configured domains
  ];

  // Configure private and temporary file paths.
  if (!isset($settings['file_private_path'])) {
    $settings['file_private_path'] = '/var/www/html/private';
  }
  // Configure the default PhpStorage and Twig template cache directories.
  if (!isset($settings['php_storage']['default'])) {
    $settings['php_storage']['default']['directory'] = $settings['file_private_path'];
  }
  if (!isset($settings['php_storage']['twig'])) {
    $settings['php_storage']['twig']['directory'] = $settings['file_private_path'];
  }

  // Enable development config when appropriate
  if (!in_array(getenv('ENVIRONMENT'), ['', 'staging', 'prod'])) {
    $settings['container_yamls'][] = $app_root . '/' . $site_path . '/development.services.yml';
    $config['config_split.config_split.development']['status'] = TRUE;
  }

  // Enable specific production config when appropriate
  if (getenv('ENVIRONMENT') === 'prod') {
    $config['config_split.config_split.production']['status'] = TRUE;
    $config['keycdn.settings.d05546f041']['api_key'] = getenv('KEYCDN_API_KEY');
  }
}
