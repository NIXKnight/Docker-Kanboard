#!/usr/bin/env bash

set -e

writeKanboardConfig () {
cat <<EOF > /var/www/kanboard/config.php
<?php
// Data folder (must be writeable by the web server user and absolute)
define('DATA_DIR', __DIR__.DIRECTORY_SEPARATOR.'data');

// Enable/Disable debug
define('DEBUG', false);

// Available log drivers: syslog, stderr, stdout, system or file
define('LOG_DRIVER', 'system');

// Plugins directory
define('PLUGINS_DIR', __DIR__.DIRECTORY_SEPARATOR.'plugins');

// Plugins directory URL
define('PLUGIN_API_URL', 'https://kanboard.org/plugins.json');

// Enable/Disable plugin installer (Disabled by default for security reasons)
// There is no code review or any approval process to submit a plugin.
// This is up to the Kanboard instance owner to validate if a plugin is legit.
define('PLUGIN_INSTALLER', true);

// Available cache drivers are "file" and "memory"
define('CACHE_DRIVER', 'memory');

// Cache folder to use if cache driver is "file" (must be writeable by the web server user)
define('CACHE_DIR', DATA_DIR.DIRECTORY_SEPARATOR.'cache');

// Folder for uploaded files (must be writeable by the web server user)
define('FILES_DIR', DATA_DIR.DIRECTORY_SEPARATOR.'files');

// Email configuration
define('MAIL_CONFIGURATION', true);
define('MAIL_TRANSPORT', 'smtp');
define('MAIL_SMTP_HOSTNAME', getenv('MAIL_SMTP_HOSTNAME'));
define('MAIL_SMTP_PORT', getenv('MAIL_SMTP_PORT'));
define('MAIL_SMTP_USERNAME', getenv('MAIL_SMTP_USERNAME'));
define('MAIL_SMTP_PASSWORD', getenv('MAIL_SMTP_PASSWORD'));
define('MAIL_SMTP_ENCRYPTION', getenv('MAIL_SMTP_ENCRYPTION'));
define('MAIL_FROM', getenv('MAIL_FROM'));

// Run automatically database migrations
// If set to false, you will have to run manually the SQL migrations from the CLI during the next Kanboard upgrade
// Do not run the migrations from multiple processes at the same time (example: web page + background worker)
define('DB_RUN_MIGRATIONS', true);

// Database configuration
define('DB_DRIVER', getenv('DB_DRIVER'));
define('DB_USERNAME', getenv('DB_USERNAME'));
define('DB_PASSWORD', getenv('DB_PASSWORD'));
define('DB_HOSTNAME', getenv('DB_HOSTNAME'));
define('DB_NAME', getenv('DB_NAME'));
define('DB_PORT', getenv('DB_PORT'));
define('DB_TIMEOUT', null);

// Enable/disable remember me authentication
define('REMEMBER_ME_AUTH', true);

// Enable or disable "Strict-Transport-Security" HTTP header
define('ENABLE_HSTS', true);

// Enable or disable "X-Frame-Options: DENY" HTTP header
define('ENABLE_XFRAME', true);

// Escape html inside markdown text
define('MARKDOWN_ESCAPE_HTML', true);

// Enable/disable url rewrite
define('ENABLE_URL_REWRITE', false);

// Hide login form, useful if all your users use Google/Github/ReverseProxy authentication
define('HIDE_LOGIN_FORM', false);

// Disabling logout (useful for external SSO authentication)
define('DISABLE_LOGOUT', false);

EOF
}

writeUnitConfig() {
cat <<'EOF' > /etc/kanboard.json
{
  "listeners": {
    "0.0.0.0:9000": {
      "pass": "routes"
    }
  },
  "applications": {
    "kanboard": {
      "type": "php",
      "processes": {
        "max": 20,
        "spare": 2
      },
      "user": "www-data",
      "group": "www-data",
      "root": "/var/www/kanboard",
      "script": "index.php"
    }
  },
  "routes": [
{
      "match": {
        "uri": [
          "*.css",
          "*.woff2",
          "*.ico",
          "*.jpg",
          "*.js",
          "*.png"
        ]
      },
      "action": {
        "share": "/var/www/kanboard/"
      }
    },
    {
      "action": {
        "pass": "applications/kanboard"
      }
    }
  ]
}
EOF
}

configureUnit() {
  CURL_REQUEST=$(/usr/bin/curl -s -w '%{http_code}' -X PUT --data-binary @/etc/kanboard.json --unix-socket /var/run/control.unit.sock http://localhost/config)
  CURL_RESPONSE_BODY=${CURL_REQUEST::-3}
  CURL_RESPONSE_CODE=$(echo $CURL_REQUEST | /usr/bin/tail -c 4)
  if [ "$CURL_RESPONSE_CODE" -ne "200" ] ; then
    echo "$0: Error: HTTP response status code is '$CURL_RESPONSE_CODE'"
    echo "$CURL_RESPONSE_BODY"
    return 1
  else
    echo "$0: OK: HTTP response status code is '$CURL_RESPONSE_CODE'"
    echo "$CURL_RESPONSE_BODY"
  fi
  return 0
}

if [ "$1" = "unitd" ]; then
  if /usr/bin/find "/var/lib/unit/" -mindepth 1 -print -quit 2>/dev/null | /bin/grep -q .; then
    echo "$0: /var/lib/unit/ is not empty, skipping initial configuration..."
  else
    echo "$0: Launching Unit daemon to perform initial configuration..."
    /usr/local/sbin/unitd --control unix:/var/run/control.unit.sock
    while [ ! -S /var/run/control.unit.sock ]; do
      echo "$0: Waiting for control socket to be created..."
      /bin/sleep 0.1
    done
    # even when the control socket exists, it does not mean unit has finished initialisation
    # this curl call will get a reply once unit is fully launched
    /usr/bin/curl -s -X GET --unix-socket /var/run/control.unit.sock http://localhost/
    echo "$0: Writing Unit configuration for Kanboard..."
    writeUnitConfig
    configureUnit
    echo "$0: Stopping Unit daemon after initial configuration..."
    kill -TERM `/bin/cat /var/run/unit.pid`
    while [ -S /var/run/control.unit.sock ]; do
      echo "$0: Waiting for control socket to be removed..."
      /bin/sleep 0.1
    done
    echo "$0: Unit initial configuration complete; ready for start up..."
  fi
fi
echo "$0: Writing Kanboard configuration..."
writeKanboardConfig

exec "$@"
