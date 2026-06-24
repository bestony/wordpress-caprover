FROM wordpress:7.0-php8.4-apache

# Keep CapRover-specific cache backends available without re-maintaining the
# upstream WordPress image bootstrap, entrypoint, Apache, and PHP defaults.
RUN set -eux; \
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		libmemcached-dev \
		zlib1g-dev \
	; \
	pecl install igbinary msgpack redis; \
	docker-php-ext-enable igbinary msgpack redis; \
	pecl download memcached; \
	memcachedTar="$(find . -maxdepth 1 -name 'memcached-*.tgz' -print -quit)"; \
	[ -n "$memcachedTar" ]; \
	mkdir -p /usr/src/php/ext/memcached; \
	tar --extract --file "$memcachedTar" --strip-components=1 --directory /usr/src/php/ext/memcached; \
	rm "$memcachedTar"; \
	docker-php-ext-configure memcached \
		--enable-memcached-igbinary \
		--enable-memcached-msgpack \
		--disable-memcached-sasl \
	; \
	docker-php-ext-install -j "$(nproc)" memcached; \
	rm -rf /tmp/pear /usr/src/php/ext/memcached; \
	\
# Some misbehaving extensions end up outputting to stdout
# (https://github.com/docker-library/wordpress/issues/669#issuecomment-993945967).
	out="$(php -r 'exit(0);')"; \
	[ -z "$out" ]; \
	err="$(php -r 'exit(0);' 3>&1 1>&2 2>&3)"; \
	[ -z "$err" ]; \
	\
	extDir="$(php -r 'echo ini_get("extension_dir");')"; \
	[ -d "$extDir" ]; \
	apt-mark auto '.*' > /dev/null; \
	apt-mark manual $savedAptMark; \
	ldd "$extDir"/*.so \
		| awk '/=>/ { so = $(NF-1); if (index(so, "/usr/local/") == 1) { next }; gsub("^/(usr/)?", "", so); printf "*%s\n", so }' \
		| sort -u \
		| xargs -r dpkg-query --search \
		| cut -d: -f1 \
		| sort -u \
		| xargs -rt apt-mark manual; \
	\
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf /var/lib/apt/lists/*; \
	\
	! { ldd "$extDir"/*.so | grep 'not found'; }; \
	err="$(php --version 3>&1 1>&2 2>&3)"; \
	[ -z "$err" ]; \
	php -m | grep -E '^(redis|igbinary|msgpack|memcached)$'; \
	php --ri redis; \
	php --ri memcached
