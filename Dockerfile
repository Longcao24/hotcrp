FROM php:8.2-apache

# Cài đặt các thư viện hệ thống cần thiết
RUN apt-get update && apt-get install -y \
    libicu-dev \
    libzip-dev \
    zip \
    unzip \
    poppler-utils \
    msmtp \
    msmtp-mta \
    mariadb-client \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Cài đặt các PHP extensions yêu cầu bởi HotCRP
RUN docker-php-ext-install intl zip mysqli pdo pdo_mysql

# Enable Apache modules
RUN a2enmod rewrite headers

# Trust Coolify's reverse-proxy headers (fixes https://host:80/ URLs)
COPY apache-hotcrp.conf /etc/apache2/sites-available/000-default.conf

# Cấu hình PHP theo khuyến nghị của HotCRP
RUN echo "upload_max_filesize = 15M\n\
post_max_size = 20M\n\
max_input_vars = 4096\n\
session.gc_maxlifetime = 86400\n\
memory_limit = 256M" > /usr/local/etc/php/conf.d/hotcrp.ini

# Khai báo thư mục làm việc
WORKDIR /var/www/html

# Copy source code vào container
COPY . /var/www/html/

# Copy entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Phân quyền cho www-data (user chạy Apache)
RUN chown -R www-data:www-data /var/www/html

ENTRYPOINT ["docker-entrypoint.sh"]
