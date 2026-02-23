#!/bin/bash
set -e

DB_HOST_ACTUAL="${DB_HOST:-hotcrp-db}"
DB_USER_ACTUAL="${DB_USER:-hotcrp}"
DB_PASS_ACTUAL="${DB_PASSWORD:-hotcrp_secure_password}"
DB_NAME_ACTUAL="${DB_NAME:-hotcrp_db}"

# Đợi port 3306 mở (TCP check, không cần auth)
echo "Waiting for database port to be open..."
max_tries=30
count=0
until bash -c "echo > /dev/tcp/${DB_HOST_ACTUAL}/3306" 2>/dev/null; do
    count=$((count+1))
    if [ $count -gt $max_tries ]; then
        echo "Error: Database port not reachable after 60 seconds."
        exit 1
    fi
    echo "Port not ready - sleeping 2s (Attempt $count/$max_tries)..."
    sleep 2
done
echo "Database port is open! Waiting 5 more seconds for MariaDB to fully initialize..."
sleep 5

mkdir -p conf

if [ ! -f conf/options.php ]; then
    echo "Creating conf/options.php from environment variables..."
    cat <<EOF > conf/options.php
<?php
global \$Opt;
\$Opt["dbName"] = "${DB_NAME_ACTUAL}";
\$Opt["dbUser"] = "${DB_USER_ACTUAL}";
\$Opt["dbPassword"] = "${DB_PASS_ACTUAL}";
\$Opt["dbHost"] = "${DB_HOST_ACTUAL}";
EOF
    chown www-data:www-data conf/options.php
fi

mkdir -p uploads
chown -R www-data:www-data uploads
chmod -R 755 uploads

# Khởi tạo schema nếu chưa có bảng
TABLE_CHECK=$(mysql --skip-ssl -h"${DB_HOST_ACTUAL}" -u"${DB_USER_ACTUAL}" --password="${DB_PASS_ACTUAL}" "${DB_NAME_ACTUAL}" -e "SHOW TABLES LIKE 'Settings';" 2>/dev/null | wc -l)
if [ "$TABLE_CHECK" -gt 1 ]; then
    echo "Database tables already exist, skipping schema import."
else
    echo "Initializing database tables from schema.sql..."
    mysql --skip-ssl -h"${DB_HOST_ACTUAL}" -u"${DB_USER_ACTUAL}" --password="${DB_PASS_ACTUAL}" "${DB_NAME_ACTUAL}" < src/schema.sql
    echo "Schema imported successfully."
fi

exec apache2-foreground
