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
    chmod 600 /etc/msmtprc

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

# ─── Create or update conf/options.php ───────────────────────────────────────
mkdir -p conf

if [ ! -f conf/options.php ]; then
    echo "Creating conf/options.php..."
    cat > conf/options.php <<EOF
<?php
global \$Opt;
\$Opt["dbName"]     = "${DB_NAME_ACTUAL}";
\$Opt["dbUser"]     = "${DB_USER_ACTUAL}";
\$Opt["dbPassword"] = "${DB_PASS_ACTUAL}";
\$Opt["dbHost"]     = "${DB_HOST_ACTUAL}";
EOF
    chown www-data:www-data conf/options.php
fi

# Always ensure email settings are present/updated (not just on first create)
php -r "
\$f = 'conf/options.php';
\$c = file_get_contents(\$f);
function upsert_opt(\$key, \$val, \$src) {
    if (strpos(\$src, \"\\\\\$Opt[\\\"\$key\\\"\") !== false) {
        return preg_replace('/\\\\\\\$Opt\\\\\[\"' . preg_quote(\$key, '/') . '\"\\\\]\s*=\s*\"[^\"]*\";/', \"\\\\\\\$Opt[\\\"{\$key}\\\"] = \\\"{\$val}\\\";\", \$src);
    }
    return rtrim(\$src) . \"\n\\\\\$Opt[\\\"\$key\\\"] = \\\"{\$val}\\\";\n\";
}
if (getenv('MAIL_FROM'))         \$c = upsert_opt('emailFrom',  getenv('MAIL_FROM'), \$c);
if (getenv('HOTCRP_SITE_URL'))   \$c = upsert_opt('paperSite',  getenv('HOTCRP_SITE_URL'), \$c);
file_put_contents(\$f, \$c);
echo 'options.php email settings updated.' . PHP_EOL;
"

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
