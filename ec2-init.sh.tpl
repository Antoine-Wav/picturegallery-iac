#!/bin/bash
set -euo pipefail

LOG_FILE="/var/log/ec2-init.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

trap 'log "ERROR: script failed at line $LINENO"' ERR

MYSQL_HOST="${db_host}"
MYSQL_DATABASE="${db_name}"
MYSQL_USER="${db_user}"
MYSQL_PASSWORD="${db_password}"

log "Starting CSE AWS deployment"

# Update the list of packages
log "Updating packages"
dnf update -y

# Install required dependencies
log "Installing dependencies"
dnf install -y \
    httpd \
    php \
    php-mysqlnd \
    php-fpm \
    git \
    mariadb105

systemctl enable httpd
systemctl enable php-fpm

systemctl start httpd
systemctl start php-fpm

# Clone the website repository if not already present
if [ ! -d /var/www/html/picturegallery ]; then
    log "Cloning website repository"
    git clone "https://github.com/csdso-wavestone/picturegallery" /tmp/site/picturegallery || {
        log "ERROR: Git clone failed"
        exit 1
    }
    cp -R /tmp/site/* /var/www/html/
else
    log "Website already present, skipping clone"
fi

# Setting up Apache permissions
log "Setting permissions"
chown -R apache:apache /var/www/html/picturegallery
find /var/www/html/picturegallery -type d -exec chmod 755 {} \;
find /var/www/html/picturegallery -type f -exec chmod 644 {} \;
chown apache:apache /var/www/html/picturegallery/uploads

# Wait until MySQL is available
MAX_RETRIES=60
RETRY_COUNT=0

log "Waiting for MySQL availability"

while ! mysql \
    -h "$MYSQL_HOST" \
    -u "$MYSQL_USER" \
    -p"$MYSQL_PASSWORD" \
    -e "SELECT 1" >/dev/null 2>&1
do
    RETRY_COUNT=$((RETRY_COUNT + 1))

    log "MySQL unavailable, attempt $RETRY_COUNT/$MAX_RETRIES"

    if [ "$RETRY_COUNT" -ge "$MAX_RETRIES" ]; then
        log "Unable to connect to RDS"
        exit 1
    fi

    sleep 10
done

# Initialize database only on first run
INIT_FLAG="/var/lib/ec2-init-db-done"
if [ ! -f "$INIT_FLAG" ]; then
    log "Initializing database"
    grep -iv '^\(create database\|use \)' /var/www/html/picturegallery/sql.sql | \
    mysql \
        -h "$MYSQL_HOST" \
        -u "$MYSQL_USER" \
        -p"$MYSQL_PASSWORD" \
        "$MYSQL_DATABASE" || {
            log "ERROR: Database initialization failed"
            exit 1
        }
    touch "$INIT_FLAG"
    log "Database initialized"
else
    log "Database already initialized, skipping"
fi

# Replace hardcoded credentials with environment variable lookups
log "Updating mysqli_connect.php"
sed -i "s|\$db_user = .*;|\$db_user = getenv('DB_USER');|g" /var/www/html/picturegallery/mysqli_connect.php
sed -i "s|\$db_password = .*;|\$db_password = getenv('DB_PASSWORD');|g" /var/www/html/picturegallery/mysqli_connect.php
sed -i "s|\$db_host = .*;|\$db_host = getenv('DB_HOST');|g" /var/www/html/picturegallery/mysqli_connect.php
sed -i "s|DEFINE ('DB_NAME', '.*');|DEFINE ('DB_NAME', getenv('DB_NAME'));|g" /var/www/html/picturegallery/mysqli_connect.php
log "Database connection file updated"

# Configure PHP-FPM environment variables (idempotent)
PHP_FPM_CONF="/etc/php-fpm.d/www.conf"

log "Configuring PHP-FPM"
grep -q "^clear_env = no" "$PHP_FPM_CONF" || \
sed -i 's/^;* *clear_env *= *.*/clear_env = no/' "$PHP_FPM_CONF"

if ! grep -q "^env\[DB_HOST\]" "$PHP_FPM_CONF"; then
    cat << EOF >> "$PHP_FPM_CONF"
env[DB_HOST] = "${db_host}"
env[DB_USER] = "${db_user}"
env[DB_PASSWORD] = "${db_password}"
env[DB_NAME] = "${db_name}"
EOF
fi

# Restart web services
log "Restarting services"
systemctl restart php-fpm && systemctl restart httpd

log "Deployment completed successfully"