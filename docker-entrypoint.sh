#!/bin/bash
set -e

DB_HOST_ACTUAL="${DB_HOST:-hotcrp-db}"
DB_USER_ACTUAL="${DB_USER:-hotcrp}"
DB_PASS_ACTUAL="${DB_PASSWORD:-hotcrp_secure_password}"
DB_NAME_ACTUAL="${DB_NAME:-hotcrp_db}"

# ─── Resend SMTP via msmtp ────────────────────────────────────────────────────
# Required env vars: RESEND_API_KEY, MAIL_FROM
if [ -n "${RESEND_API_KEY}" ]; then
    echo "Configuring msmtp for Resend..."
    cat > /etc/msmtprc <<EOF
defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /var/log/msmtp.log

account        resend
host           smtp.resend.com
port           587
from           ${MAIL_FROM:-noreply@example.com}
user           resend
password       ${RESEND_API_KEY}

account default : resend
EOF
    chmod 644 /etc/msmtprc

    # Point PHP's mail() to msmtp
    echo "sendmail_path = /usr/bin/msmtp -t --read-envelope-from" \
        > /usr/local/etc/php/conf.d/mail.ini
    echo "Resend SMTP configured."
else
    echo "WARNING: RESEND_API_KEY not set. Email will not work."
fi

# ─── Wait for database port ───────────────────────────────────────────────────
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

# ─── Always regenerate conf/options.php from env vars ────────────────────────
mkdir -p conf

echo "Writing conf/options.php..."
cat > conf/options.php <<OPTEOF
<?php
global \$Opt;
\$Opt["dbName"]     = "${DB_NAME_ACTUAL}";
\$Opt["dbUser"]     = "${DB_USER_ACTUAL}";
\$Opt["dbPassword"] = "${DB_PASS_ACTUAL}";
\$Opt["dbHost"]     = "${DB_HOST_ACTUAL}";
\$Opt["sendEmail"]  = true;
OPTEOF

if [ -n "${MAIL_FROM}" ]; then
    echo "\$Opt[\"emailFrom\"] = \"${MAIL_FROM}\";" >> conf/options.php
fi
if [ -n "${HOTCRP_SITE_URL}" ]; then
    echo "\$Opt[\"paperSite\"] = \"${HOTCRP_SITE_URL}\";" >> conf/options.php
fi

chown www-data:www-data conf/options.php
echo "conf/options.php written."

# ─── Uploads directory ────────────────────────────────────────────────────────
mkdir -p uploads
chown -R www-data:www-data uploads
chmod -R 755 uploads

# ─── Import DB schema if needed ──────────────────────────────────────────────
TABLE_CHECK=$(mysql --skip-ssl -h"${DB_HOST_ACTUAL}" -u"${DB_USER_ACTUAL}" --password="${DB_PASS_ACTUAL}" "${DB_NAME_ACTUAL}" -e "SHOW TABLES LIKE 'Settings';" 2>/dev/null | wc -l)
if [ "$TABLE_CHECK" -gt 1 ]; then
    echo "Database tables already exist, skipping schema import."
else
    echo "Initializing database tables from schema.sql..."
    mysql --skip-ssl -h"${DB_HOST_ACTUAL}" -u"${DB_USER_ACTUAL}" --password="${DB_PASS_ACTUAL}" "${DB_NAME_ACTUAL}" < src/schema.sql
    echo "Schema imported successfully."
fi

exec apache2-foreground
