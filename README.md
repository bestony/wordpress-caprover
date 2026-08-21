# WordPress for CapRover

Docker images for running WordPress on [CapRover](https://caprover.com), automatically built and pushed to GHCR on every push to `main`/`master`, version tags (`v*`, `release-*`, `*.*.*`), and manual dispatch.

## Available Images

All images live under `ghcr.io/<your-ghcr-owner>/`. Replace `<owner>` below with your GitHub username or organization that owns the GHCR package.

| Image | Dockerfile | Base | Key Additions | When to Use |
|-------|------------|------|---------------|-------------|
| [`wordpress-caprover-apache`](#wordpress-caprover-apache) | `Dockerfile` | `wordpress:7.0-php8.4-apache` | memcached + redis (igbinary/msgpack) cache backends | **Default / recommended.** Classic Apache + mod_php stack, what the CapRover one-click deploy uses. |
| [`wordpress-caprover-fpm`](#wordpress-caprover-fpm) | `Dockerfile.fpm` | `wordpress:php8.5-fpm` | yac, igbinary, imagick, exif, zip | PHP-FPM runtime. Pair with a separate web server (e.g. an nginx app on CapRover) that proxies FastCGI to it. |
| [`wordpress-caprover-7.0.4`](#wordpress-caprover-704) | `Dockerfile.apache` | `wordpress:apache` (PHP 8.3) | igbinary, yac, tuned opcache/yac config | Apache variant tuned for caching: OPcache + YAC memory tuning for high-traffic sites. |

## Image Semantics

### `wordpress-caprover-apache`

The all-in-one image, built from `Dockerfile`. Apache with mod_php serving WordPress directly, plus the memcached and redis PHP extensions (with igbinary/msgpack serializers) so you can use CapRover's Memcached or Redis one-click apps as object-cache backends (e.g. via the `redis-cache` / `memcached` WordPress plugins). This is the image the `captain-definition` in this repo points to, so it is what a CapRover app using this repo builds by default.

```bash
docker pull ghcr.io/<owner>/wordpress-caprover-apache:latest
```

### `wordpress-caprover-fpm`

A PHP-FPM variant, built from `Dockerfile.fpm`, for setups that separate the web server from PHP. Comes with yac and igbinary (fast local object cache / serialization), imagick (image processing), and the bundled exif/zip extensions. Point your nginx/other proxy's FastCGI upstream at the container port (9000) instead of serving PHP itself.

```bash
docker pull ghcr.io/<owner>/wordpress-caprover-fpm:latest
```

### `wordpress-caprover-7.0.4`

Apache variant built from `Dockerfile.apache` on the rolling `wordpress:apache` tag (PHP 8.3). The GHCR image name is historical (the Dockerfile was previously `Dockerfile.704`). It keeps the upstream imagick/exif/zip/OPcache extensions, adds igbinary and yac, and writes tuned `opcache` (256M memory, 20k accelerated files) and `yac` (16M keys / 128M values) settings that override the base image defaults. Choose this when you want the Apache stack with the strongest in-process caching (`yac` + OPcache) and don't need the memcached/redis backends of `wordpress-caprover-apache`.

```bash
docker pull ghcr.io/<owner>/wordpress-caprover-7.0.4:latest
```

## Tags

Each image is published with the same tag scheme from `docker/metadata-action`:

- `latest` — most recent build on the default branch (`main`/`master`)
- `<branch>` — e.g. `main`
- `<tag>` — for semver tags like `v1.2.3` / `1.2.3` / `release-1.2.3`
- `<sha>` — short commit SHA for exact-pin rollback

## Usage on CapRover

1. In CapRover, create an app and set the image to one of the GHCR images above (e.g. `ghcr.io/<owner>/wordpress-caprover-apache:latest`).
2. Set the app's HTTP port to `80` for the apache image, or proxy PHP-FPM separately for the `-fpm` image.
3. Mount a persistent volume for `/var/www/html` so `wp-content` uploads survive redeploys.
