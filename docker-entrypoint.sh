#!/bin/bash
set -e

# Đợi DB sẵn sàng
sleep 15

# Đảm bảo thư mục conf tồn tại
mkdir -p conf

# Tạo cấu hình options.php động từ biến môi trường
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

# Thiết lập thư mục quyền truy cập cho upload
mkdir -p uploads
chown -R www-data:www-data uploads
chmod -R 755 uploads

# Chạy script tạo cấu trúc bảng nếu db trống
if mysql -h"${DB_HOST:-hotcrp-db}" -u"${DB_USER:-hotcrp}" -p"${DB_PASSWORD:-hotcrp_secure_password}" "${DB_NAME:-hotcrp_db}" -e "SHOW TABLES;" 2>/dev/null | grep -q "Settings"; then
    echo "Database tables already exist."
else
    echo "Initializing database tables..."
    mysql -h"${DB_HOST:-hotcrp-db}" -u"${DB_USER:-hotcrp}" -p"${DB_PASSWORD:-hotcrp_secure_password}" "${DB_NAME:-hotcrp_db}" < src/schema.sql || true
fi

exec apache2-foreground
