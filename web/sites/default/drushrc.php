<?php
/**
 * Example Drush configuration file for a Platform.sh Drupal site.
 */

if (PHP_SAPI === 'cli' && getenv('PLATFORM_ROUTES') && getenv('PLATFORM_APPLICATION_NAME')) {
  $routes = json_decode(base64_decode(getenv('PLATFORM_ROUTES')), TRUE);
  $expected_route_urls = [
    'https://{default}/',
    'https://www.{default}/',
    'http://{default}/',
    'http://www.{default}/',
  ];
  foreach ($routes as $url => $route) {
    if ($route['type'] === 'upstream'
    	&& $route['upstream'] === getenv('PLATFORM_APPLICATION_NAME')
      && in_array($route['original_url'], $expected_route_urls)) {
      $options['uri'] = $url;
      break;
    }
  }
}
