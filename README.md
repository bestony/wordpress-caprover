# WordPress for CapRover

Docker images for running WordPress on [CapRover](https://caprover.com). GitHub Actions builds and pushes each image to GHCR on every push to `main`/`master`, on version tags (`v*`, `release-*`, `*.*.*`), and on manual dispatch.

## Available Images

All images live under `ghcr.io/bestony/`.

| Image | Dockerfile | Base | Key Additions | When to Use |
|-------|------------|------|---------------|-------------|
| [`wordpress-caprover-apache`](#wordpress-caprover-apache) | `Dockerfile` | `wordpress:7.0-php8.5-apache` | memcached + redis (igbinary/msgpack) cache backends | **Default / recommended.** Classic Apache + mod_php stack, what the CapRover one-click deploy uses. |
| [`wordpress-caprover-fpm`](#wordpress-caprover-fpm) | `Dockerfile.fpm` | `wordpress:php8.5-fpm` | yac, igbinary, imagick, exif, zip | PHP-FPM runtime. Pair with a separate web server (e.g. an nginx app on CapRover) that proxies FastCGI to it. |
| [`wordpress-caprover-apache-yac`](#wordpress-caprover-apache-yac) | `Dockerfile.apache` | `wordpress:php8.5-apache` (PHP 8.5) | igbinary, yac, tuned opcache/yac config | Apache variant tuned for caching: OPcache + YAC memory tuning for high-traffic sites. |

## Image Semantics

### `wordpress-caprover-apache`

The all-in-one image, built from `Dockerfile`. Apache with mod_php serving WordPress directly, plus the memcached and redis PHP extensions (with igbinary/msgpack serializers) so you can use CapRover's Memcached or Redis one-click apps as object-cache backends (e.g. via the `redis-cache` / `memcached` WordPress plugins). This is the image the `captain-definition` in this repo points to, so it is what a CapRover app using this repo builds by default.

```bash
docker pull ghcr.io/bestony/wordpress-caprover-apache:latest
```

### `wordpress-caprover-fpm`

A PHP-FPM variant, built from `Dockerfile.fpm`, for setups that separate the web server from PHP. Comes with yac and igbinary (fast local object cache / serialization), imagick (image processing), and the bundled exif/zip extensions. Point your nginx/other proxy's FastCGI upstream at the container port (9000) instead of serving PHP itself.

```bash
docker pull ghcr.io/bestony/wordpress-caprover-fpm:latest
```

### `wordpress-caprover-apache-yac`

Apache variant built from `Dockerfile.apache` on the rolling `wordpress:php8.5-apache` tag (PHP 8.5). It keeps the upstream imagick/exif/zip/OPcache extensions, adds igbinary and yac, and writes tuned `opcache` (256M memory, 20k accelerated files) and `yac` (4M keys / 64M values) settings that override the base image defaults. Choose this when you want the Apache stack with the strongest in-process caching (`yac` + OPcache) and don't need the memcached/redis backends of `wordpress-caprover-apache`.

```bash
docker pull ghcr.io/bestony/wordpress-caprover-apache-yac:latest
```

## Tags

Each image is published with the same tag scheme from `docker/metadata-action`:

- `latest` — most recent build on the default branch (`main`/`master`)
- `<branch>` — e.g. `main`
- `<tag>` — for semver tags like `v1.2.3` / `1.2.3` / `release-1.2.3`
- `<sha>` — short commit SHA for exact-pin rollback

CI also pushes a `buildcache` tag for each image. That tag is a BuildKit cache index for GitHub Actions. Do not run it.

## Environment Variables

All images inherit the configuration from the upstream `wordpress` image, so `wp-config.php` is generated from environment variables on first boot. The common ones:

| Variable | Default | Purpose |
|----------|---------|---------|
| `WORDPRESS_DB_HOST` | `mysql` | Database host (`host` or `host:port`). |
| `WORDPRESS_DB_USER` | `root` | Database user. |
| `WORDPRESS_DB_PASSWORD` | _(empty)_ | Database password. |
| `WORDPRESS_DB_NAME` | `wordpress` | Database name. |
| `WORDPRESS_TABLE_PREFIX` | `wp_` | Table prefix (needed to share one DB across sites). |
| `WORDPRESS_AUTH_KEY`, `WORDPRESS_SECRET_KEY`, `WORDPRESS_LOGGED_IN_KEY`, `WORDPRESS_NONCE_KEY`, `WORDPRESS_AUTH_SALT`, `WORDPRESS_SECURE_AUTH_SALT`, `WORDPRESS_LOGGED_IN_SALT`, `WORDPRESS_NONCE_SALT` | random | Auth keys/salts. Set them explicitly in production so sessions survive redeploys. |
| `WORDPRESS_DEBUG` | _(unset)_ | Any non-empty value turns on `WP_DEBUG`. |
| `WORDPRESS_CONFIG_EXTRA` | _(unset)_ | Raw PHP appended to `wp-config.php`, e.g. to `define()` extra constants. |

Notes:

- Any `WORDPRESS_*` variable also accepts a `_FILE` suffix (e.g. `WORDPRESS_DB_PASSWORD_FILE=/run/secrets/db_password`) to read the value from a file — use this for Docker/CapRover secrets instead of putting passwords in plaintext.
- To enable an object cache backend (redis/memcached extensions ship in `wordpress-caprover-apache`), inject the config via `WORDPRESS_CONFIG_EXTRA` and a drop-in plugin, e.g.:

  ```bash
  -e WORDPRESS_CONFIG_EXTRA="define('WP_REDIS_HOST', 'srv-captain--redis'); define('WP_REDIS_PORT', 6379);"
  ```

- On CapRover, set these under the app's **App Configs → Environment Variables**.

## File Mounts (Volumes)

The images use the upstream `WORKDIR`/`VOLUME` of `/var/www/html`. Mount that path for persistence, or bind-mount subpaths to inject your own plugins and themes.

| Container path | What to mount there |
|----------------|---------------------|
| `/var/www/html` | The whole WordPress install — mount a persistent volume so uploads, updates, and installed plugins/themes survive redeploys. |
| `/var/www/html/wp-content/plugins/<plugin>` | A single plugin directory. |
| `/var/www/html/wp-content/themes/<theme>` | A single theme directory. |

### Mount a plugin and a theme

Bind-mount your local plugin/theme directories straight into `wp-content`. Add `:ro` (read-only) for code you don't want WordPress to auto-update or modify:

```bash
docker run -d --name wordpress \
  -p 8080:80 \
  -e WORDPRESS_DB_HOST=db \
  -e WORDPRESS_DB_USER=wordpress \
  -e WORDPRESS_DB_PASSWORD=wordpress \
  -e WORDPRESS_DB_NAME=wordpress \
  -v wp_data:/var/www/html \
  -v ./my-plugin:/var/www/html/wp-content/plugins/my-plugin:ro \
  -v ./my-theme:/var/www/html/wp-content/themes/my-theme:ro \
  ghcr.io/bestony/wordpress-caprover-apache:latest
```

The same with Compose:

```yaml
services:
  wordpress:
    image: ghcr.io/bestony/wordpress-caprover-apache:latest
    ports:
      - "8080:80"
    environment:
      WORDPRESS_DB_HOST: db
      WORDPRESS_DB_USER: wordpress
      WORDPRESS_DB_PASSWORD: wordpress
      WORDPRESS_DB_NAME: wordpress
    volumes:
      - wp_data:/var/www/html
      - ./my-plugin:/var/www/html/wp-content/plugins/my-plugin:ro
      - ./my-theme:/var/www/html/wp-content/themes/my-theme:ro
volumes:
  wp_data:
```

The directory name after `plugins/` or `themes/` is what WordPress lists — mount to a path whose last segment matches the plugin/theme slug (its main folder name). After the container is up, activate them from **wp-admin → Plugins / Appearance**.

> Bake-in vs mount: for image builds you own, `COPY my-plugin /var/www/html/wp-content/plugins/my-plugin` in a Dockerfile ships the plugin inside the image (immutable, no host dependency). Bind-mounting is for local development or host-managed code you edit without rebuilding.

## Usage on CapRover

1. In CapRover, create an app and set the image to one of the GHCR images above (e.g. `ghcr.io/bestony/wordpress-caprover-apache:latest`).
2. Set the app's HTTP port to `80` for the apache image, or proxy PHP-FPM separately for the `-fpm` image.
3. Mount a persistent volume for `/var/www/html` so `wp-content` uploads survive redeploys.
4. Set database and secret variables under **App Configs → Environment Variables** (see [Environment Variables](#environment-variables)).
5. To ship a custom plugin/theme on CapRover via **Persistent Directories** (App Configs → Persistent Directories):
   - Add one directory per plugin/theme. Set **Path in App** to the container path, e.g. `/var/www/html/wp-content/plugins/my-plugin` or `/var/www/html/wp-content/themes/my-theme`.
   - Choose **Set a specific path** and give a host path on the CapRover server, e.g. `/captain/data/wp/my-plugin`.
   - A persistent directory starts **empty** — the plugin/theme only shows up after you put its files at that host path. SSH into the CapRover server and `git clone` / `scp` / `rsync` your code into it (the last path segment must match the plugin/theme slug).
   - Save & Update, then activate from **wp-admin → Plugins / Appearance**.
   - This also survives redeploys, so you can edit the code on the host without rebuilding the image.
