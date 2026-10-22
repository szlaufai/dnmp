# PHP 7.4 security image

This is a temporary PHP 7.4 runtime containing the official source backports for
CVE-2026-109618 and CVE-2026-109619. It includes the extensions used by this
project, Composer, Git and Supervisor. No application code, `.env`, TLS keys,
database files or queue configuration is copied into the image.

## Source provenance

- PHP announcement: https://www.php.net/archive/2026.php#2026-10-21-5
- PHP security branch: https://github.com/php/php-src/tree/PHP-7.4-CVE-2026-109618-109619
- Pinned security commit: `712e60f9edfd03f0960fc4fc3c2c375f42b90aa2`
- Docker build recipe and helper scripts: `docker-library/php` commit
  `b9f17156020c3aef71df681b27684533529347a7`, `7.4/alpine3.16/fpm/`.
- `install-php-extensions` is vendored from this repository's existing
  `services/php74/extensions/install-php-extensions` (MIT license).
- `security.patch` is the complete diff from the official `php-7.4.33` tag to
  the pinned security commit. The original release tarball is verified using
  the upstream SHA-256 and GPG checks before patching. Patching fails on errors;
  autoconf is regenerated before compilation. The patched source archive is
  retained so later bundled extension builds also use the fixed sources.

The official security branch sets `configure.ac` to **7.4.34-dev**. That version
is expected here; it is not a newly supported upstream PHP release. The running
image can also be traced using its `io.dnmp.php-security-commit` label and
`/usr/local/share/php-security/source-commit`. Labels alone do not establish
that a third-party image is patched: retain build logs and image digests.

## Build and publish on GitHub

The `PHP 7.4 security image` workflow uses a native amd64 Ubuntu runner and four
compiler jobs. It builds PHP and every extension, tests the resulting image,
then publishes it to GHCR using the job's `GITHUB_TOKEN`. No registry password
needs to be stored in this repository. Publication never deploys a server.

The workflow runs on changes to its build files on `influen`, `master`, or
`feat/php74-security-image`. After the workflow exists on the default branch,
it can also be run using the Actions page's **Run workflow** button.

Default extensions match the current PHP 7.4 environment: pdo_mysql, mysqli,
redis, mbstring, gd, curl, opcache, xdebug, pcntl, bcmath, calendar, zip, mongodb,
imagick. PECL versions are pinned to redis 5.3.7, xdebug 2.9.2, mongodb 1.20.1
and imagick 3.7.0. Their source archives are vendored and checksummed to avoid
relying on PECL REST metadata during builds. The core is cached separately in
GHCR under `core-712e60f`; deploy only a final `security-...` image.
Imagick differs from the old script's 3.4.4; test image
processing before production use. The old preload of Alpine 3.13 libiconv is
unnecessary: this PHP runtime is already built against GNU libiconv.

Checks include required extension loading, FPM configuration, Composer, bounded
OOM behavior and a real FastCGI request. These checks do not replace application
testing or a complete security audit. Both CLI and FPM use the patched runtime.

Tags:

- `ghcr.io/szlaufai/dnmp-php74:security-712e60f-<full Git commit>`: unique build tag.
- `ghcr.io/szlaufai/dnmp-php74:security-712e60f`: moving convenience tag.

Use a unique build tag or, preferably, the published `@sha256:...` digest in
production. The GHCR package may initially be private. To pull a private package,
log in on the server using a suitable GitHub token with `read:packages`; pass it
through `docker login ghcr.io --username YOUR_LOGIN --password-stdin`. Do not
commit credentials to `.env` or workflow files.

## Deploy on the amd64 Ubuntu server

Requires Docker Compose >= 2.24.4 for the `!reset` override. Run `docker compose
version` first. For older Compose, update the Compose plugin or manually replace
the `php` service's entire `build` mapping with an `image` field in the server's
local `docker-compose.yml`.

1. Copy `compose.php74-image.yml` to the server's project directory and keep the
   server's existing `docker-compose.yml`, `.env` and Supervisor configuration.
2. Set the verified image from the successful Actions summary:

   ```sh
   export PHP74_IMAGE=ghcr.io/szlaufai/dnmp-php74:security-712e60f-REPLACE_WITH_BUILD_COMMIT
   ```

3. Preserve the currently running image for rollback. Run this before replacing
   the container, and retain a copy of the server's current configuration:

   ```sh
   docker image tag "$(docker inspect php --format '{{.Image}}')" dnmp/php74:before-security-update
   docker compose -f docker-compose.yml -f compose.php74-image.yml config --format json \
     | python3 -c 'import json,sys; s=json.load(sys.stdin)["services"]["php"]; assert not s.get("build"); print(s["image"])'
   docker compose -f docker-compose.yml -f compose.php74-image.yml pull php
   ```

4. Validate the new image with the server's mounted configuration:

   ```sh
   docker compose -f docker-compose.yml -f compose.php74-image.yml run --rm --no-deps php php-fpm -t
   docker compose -f docker-compose.yml -f compose.php74-image.yml run --rm --no-deps php php -m
   ```

5. After application acceptance testing and scheduling a brief interruption,
   replace only PHP 7.4. Supervisor queue workers in this service also restart:

   ```sh
   docker compose -f docker-compose.yml -f compose.php74-image.yml up -d --no-deps --no-build php
   docker compose -f docker-compose.yml -f compose.php74-image.yml exec php php -v
   docker compose -f docker-compose.yml -f compose.php74-image.yml exec php supervisorctl status
   docker compose -f docker-compose.yml -f compose.php74-image.yml exec nginx nginx -t
   docker compose -f docker-compose.yml -f compose.php74-image.yml exec nginx nginx -s reload
   docker compose -f docker-compose.yml -f compose.php74-image.yml logs --tail=100 php
   ```

6. Persist the chosen `PHP74_IMAGE` in the server's `.env`. Include the override
   on future Compose operations; running the old build configuration can revert
   this service to an unpatched image. Verify login, uploads, image processing,
   database/Redis connectivity and every queue worker. Reloading Nginx refreshes
   the upstream container address if recreating PHP changed its IP.

Rollback, if application compatibility fails:

```sh
PHP74_IMAGE=dnmp/php74:before-security-update docker compose \
  -f docker-compose.yml -f compose.php74-image.yml up -d --no-deps --no-build php
```

The rollback image remains vulnerable: restrict its exposure while investigating.
The Alpine 3.16 base and PHP 7.4 are end of life. This rebuild fixes these two
specific PHP CVEs, not all historical OS/runtime vulnerabilities. Plan migration
to the already available PHP 8.4 service.
