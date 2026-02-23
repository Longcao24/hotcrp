#!/bin/bash
set -e

# Đợi DB sẵn sàng một cách chắc chắn thay vì sleep tĩnh
echo "Waiting for database to be ready..."
max_tries=30
count=0
while ! mysql -h"${DB_HOST:-hotcrp-db}" -u"${DB_USER:-hotcrp}" -p"${DB_PASSWORD:-hotcrp_secure_password}" -e "SELECT 1;" >/dev/null 2>&1; do
    count=$((count+1))
    if [ $count -gt $max_tries ]; then
        echo "Error: Database is not ready after 60 seconds."
        exit 1
    fi
    echo "Database is unavailable - sleeping 2s (Attempt $count/$max_tries)..."
    sleep 2
done
echo "Database is up and running!"

mkdir -p conf

if [ ! -f conf/options.php ]; then
    echo "Creating conf/options.php from environment variables..."
    cat <<EOF > conf/options.php
<?php
global \$Opt;
\$Opt["dbName"] = getenv("DB_NAME") ?: "hotcrp_db";
\$Opt["dbUser"] = getenv("DB_USER") ?: "hotcrp";
\$Opt["dbPassword"] = getenv("DB_PASSWORD") ?: "hotcrp_secure_password";
\$Opt["dbHost"] = getenv("DB_HOST") ?: "hotcrp-db";
EOF
    chown www-data:www-data conf/options.php
fi

mkdir -p uploads
chown -R www-data:www-data uploads
chmod -R 755 uploads

if mysql -h"${DB_HOST:-hotcrp-db}" -u"${DB_USER:-hotcrp}" -p"${DB_PASSWORD:-hotcrp_secure_password}" "${DB_NAME:-hotcrp_db}" -e "SHOW TABLES;" 2>/dev/null | grep -q "Settings"; then
    echo "Database tables already exist."
else
    echo "Initializing database tables..."
    mysql -h"${DB_HOST:-hotcrp-db}" -u"${DB_USER:-hotcrp}" -p"${DB_PASSWORD:-hotcrp_secure_password}" "${DB_NAME:-hotcrp_db}" < src/schema.sql || true
fi

exec apache2-foreground
