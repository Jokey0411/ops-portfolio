FROM php:8.2-fpm-alpine

# ★ 换清华源（境外 dl-cdn 拉 apk 跨境龟速，国内源快一个量级）
RUN sed -i 's#dl-cdn.alpinelinux.org#mirrors.tuna.tsinghua.edu.cn#g' /etc/apk/repositories

# 编译依赖（装完删掉，减小镜像层）
# ★ pecl install redis 是「编译安装」，需要 $PHPIZE_DEPS 提供的 autoconf/gcc/make。
#   官方 php-fpm 镜像里没有 pecl？有的，但缺编译器，所以必须挂在同一个 RUN 里，
#   否则 apk del .build-deps 之后 pecl 就报 "phpize: not found"。
RUN apk add --no-cache --virtual .build-deps $PHPIZE_DEPS \
 && apk add --no-cache libzip-dev icu-dev \
 && docker-php-ext-configure opcache --enable-opcache \
 && docker-php-ext-install -j$(nproc) pdo_mysql mysqli opcache \
 && pecl install redis \
 && docker-php-ext-enable redis \
 && apk del .build-deps

# ★ 关键：php-fpm 默认监听 127.0.0.1:9000，nginx 在另一个容器里连不上
#   必须改成监听 0.0.0.0:9000（zz- 前缀保证该文件最后加载，覆盖默认配置）
#   pm.max_children=8：2G 内存别设太大；max_requests=500 防内存泄漏累积
# ★ 注意：这些 echo 行尾不能写注释——`#` 会把行尾续行符 `\` 一起吞掉，
#   命令组不闭合，构建报 syntax error: unexpected end of file (expecting "}")
RUN { \
      echo '[global]'; \
      echo 'daemonize = no'; \
      echo ''; \
      echo '[www]'; \
      echo 'listen = 0.0.0.0:9000'; \
      echo 'pm = dynamic'; \
      echo 'pm.max_children = 8'; \
      echo 'pm.start_servers = 2'; \
      echo 'pm.min_spare_servers = 1'; \
      echo 'pm.max_spare_servers = 4'; \
      echo 'pm.max_requests = 500'; \
      echo 'slowlog = /proc/self/fd/2'; \
      echo 'request_slowlog_timeout = 3s'; \
    } > /usr/local/etc/php-fpm.d/zz-docker.conf

WORKDIR /var/www/html
EXPOSE 9000
CMD ["php-fpm"]
