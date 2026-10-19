FROM php:8.2-fpm-alpine

# 编译依赖（装完删掉，减小镜像层）
RUN apk add --no-cache --virtual .build-deps $PHPIZE_DEPS \
 && apk add --no-cache libzip-dev icu-dev \
 && docker-php-ext-configure opcache --enable-opcache \
 && docker-php-ext-install -j$(nproc) pdo_mysql mysqli opcache \
 && apk del .build-deps

# ★ 关键：php-fpm 默认监听 127.0.0.1:9000，nginx 在另一个容器里连不上
# 必须改成监听 0.0.0.0:9000（zz- 前缀保证该文件最后加载，覆盖默认配置）
RUN { \
      echo '[global]'; \
      echo 'daemonize = no'; \
      echo ''; \
      echo '[www]'; \
      echo 'listen = 0.0.0.0:9000'; \
      echo 'pm = dynamic'; \
      echo 'pm.max_children = 8';      # 2G 内存，别设太大 \
      echo 'pm.start_servers = 2'; \
      echo 'pm.min_spare_servers = 1'; \
      echo 'pm.max_spare_servers = 4'; \
      echo 'pm.max_requests = 500';    # 防内存泄漏累积 \
      echo 'slowlog = /proc/self/fd/2'; \
      echo 'request_slowlog_timeout = 3s'; \
    } > /usr/local/etc/php-fpm.d/zz-docker.conf

WORKDIR /var/www/html
EXPOSE 9000
CMD ["php-fpm"]
