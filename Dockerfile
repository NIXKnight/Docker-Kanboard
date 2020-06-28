FROM debian:buster-slim
LABEL name="Docker-Kanboard" \
      description="Dockerfile for Kanboard using PHP with NGINX Unit application server" \
      maintainer="Saad Ali <saad@nixknight.net>"

# Build-time variables
# --------------------------
ARG INSTALL_PREFIX="/usr/local"
ARG PHP_VERSION
ARG PHPIZE_DEPS="autoconf dpkg-dev file g++ gcc libc-dev make pkg-config re2c"
ARG PHP_CFLAGS='-fstack-protector-strong -fpic -fpie -O2 -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64'
ARG PHP_CPPFLAGS="$PHP_CFLAGS"
ARG PHP_LDFLAGS='-Wl,-O1 -Wl,--hash-style=both -pie'
ARG PHP_URL="https://github.com/php/php-src.git"
ARG PHP_SRC_DIR="/usr/src/php"
ARG PHP_INI_DIR="$INSTALL_PREFIX/etc/php"
ARG NGINX_UNIT_VERSION
ARG NGINX_UNIT_URL="https://github.com/nginx/unit"
ARG NGINX_UNIT_SRC_DIR="/usr/src/unit"
ARG NGINX_UNIT_CCFLAGS='-g -O2 -fstack-protector-strong -Wformat -Werror=format-security -Wp,-D_FORTIFY_SOURCE=2 -fPIC'
ARG NGINX_UNIT_LDFLAGS='-Wl,-z,relro -Wl,-z,now -Wl,--as-needed -pie'
ARG KANBOARD_URL="https://github.com/kanboard/kanboard.git"
ARG KANBOARD_VERSION
# --------------------------

# Build/Install PHP and NGINX Unit
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends --no-install-suggests $PHPIZE_DEPS ca-certificates curl git; \
    mkdir -p "$PHP_INI_DIR/conf.d"; \
    savedAptMark="$(apt-mark showmanual)"; \
    apt-mark auto '.*' > /dev/null; \
    apt-mark manual $savedAptMark > /dev/null; \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    savedAptMark="$(apt-mark showmanual)"; \
    apt-get install -y --no-install-recommends --no-install-suggests bison libargon2-dev libcurl4-openssl-dev libedit-dev libonig-dev \
      libsodium-dev libsqlite3-dev libssl-dev libxml2-dev zlib1g-dev libpng-dev libzip-dev ${PHP_EXTRA_BUILD_DEPS:-}; \
    rm -rvf /var/lib/apt/lists/*; \
    gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"; \
    debMultiarch="$(dpkg-architecture --query DEB_BUILD_MULTIARCH)"; \
    if [ ! -d /usr/include/curl ]; then \
      ln -sT "/usr/include/$debMultiarch/curl" /usr/local/include/curl; \
    fi; \
    git clone $PHP_URL --branch php-$PHP_VERSION --depth 1 $PHP_SRC_DIR && cd $PHP_SRC_DIR; \
    ./buildconf --force && CFLAGS="$PHP_CFLAGS" CPPFLAGS="$PHP_CPPFLAGS" LDFLAGS="$PHP_LDFLAGS" ./configure --prefix="$INSTALL_PREFIX" --build="$gnuArch" \
      --with-config-file-path="$PHP_INI_DIR" --with-config-file-scan-dir="$PHP_INI_DIR/conf.d" --enable-option-checking=fatal --with-mhash --enable-gd \
      --enable-ftp --enable-mbstring --enable-mysqlnd --with-pdo-mysql --with-password-argon2 --with-sodium=shared --with-pdo-sqlite=/usr --with-sqlite3=/usr \
      --with-curl --with-libedit --with-openssl --with-zlib --enable-embed=shared --with-pear --with-zip --with-libdir="lib/$debMultiarch" ${PHP_EXTRA_CONFIGURE_ARGS:-}; \
    make -j "$(nproc)"; \
	  find -type f -name '*.a' -delete; \
	  make install; \
    cp -v php.ini-production $PHP_INI_DIR/php.ini; \
	  find /usr/local/bin /usr/local/sbin -type f -executable -exec strip --strip-all '{}' + || true; \
	  make clean; \
    git clone $NGINX_UNIT_URL --branch $NGINX_UNIT_VERSION --depth 1 $NGINX_UNIT_SRC_DIR && cd $NGINX_UNIT_SRC_DIR; \
    CFLAGS="$NGINX_UNIT_CCFLAGS" LDFLAGS="$NGINX_UNIT_LDFLAGS" ./configure --prefix=$INSTALL_PREFIX --state=$INSTALL_PREFIX/lib/unit \
      --control=unix:/var/run/control.unit.sock --pid=/var/run/unit.pid --log=/var/log/unit.log --tests --openssl \
      --modules=$INSTALL_PREFIX/lib/unit/modules --libdir=$INSTALL_PREFIX/lib/x86_64-linux-gnu; \
    CFLAGS="$NGINX_UNIT_CCFLAGS" LDFLAGS="$NGINX_UNIT_LDFLAGS" ./configure php --config=$INSTALL_PREFIX/bin/php-config \
      --lib-path=$INSTALL_PREFIX/lib; \
    make -j "$(nproc)"; \
    make install; \
    make php; \
    make php-install; \
    apt-mark auto '.*' > /dev/null; \
    [ -z "$savedAptMark" ] || apt-mark manual $savedAptMark; \
    find /usr/local -type f -executable -exec ldd '{}' ';' \
      | awk '/=>/ { print $(NF-1) }' \
      | sort -u \
      | xargs -r dpkg-query --search \
      | cut -d: -f1 \
      | sort -u \
      | xargs -r apt-mark manual; \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    cd ~ && rm -rvf $PHP_SRC_DIR $NGINX_UNIT_SRC_DIR; \
    ln -sf /dev/stdout /var/log/unit.log; \
    rm -rvf /var/lib/apt/lists/*

# Install Kanboard
RUN set -eux; \
    mkdir /var/www; \
    git clone $KANBOARD_URL --branch $KANBOARD_VERSION --depth 1 /var/www/kanboard; \
    rm -rvf /var/www/kanboard/.git; \
    chown -R www-data:www-data /var/www/kanboard

EXPOSE 9000

STOPSIGNAL SIGTERM
COPY entrypoint.sh $INSTALL_PREFIX/bin/
WORKDIR /var/www/kanboard
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

CMD ["unitd", "--no-daemon", "--control", "unix:/var/run/control.unit.sock"]
