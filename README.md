![Docker](https://img.shields.io/badge/docker-24.x-blue)
![CKAN](https://img.shields.io/badge/CKAN-2.11.4-orange)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-14-blueviolet)
![Redis](https://img.shields.io/badge/Redis-7-red)

# CKAN 2.11 Docker Compose Deployment

This project deploys CKAN `2.11.4` with:

- `ckan` (ckan web instance + xloader worker, managed by `supervisord`)
- `db` (a database for ckan and extensions: `postgres:14`)
- `solr` (the search engine: `ckan/ckan-solr:2.11-solr9`)
- `redis` (`redis:7-alpine`)
- `nginx` (webserver for browser access)

## 1) Prerequisites

- Docker Engine + Docker Compose plugin
- Needed ports:
  - `8085` (HTTPS through nginx)
  - `5000` (direct CKAN in dev override)
  - `5435` (optional DB access from host)

## 2) Setup `.env`

Create your local env file:

```bash
cp .env.example .env
```

Update at least the following values in `.env`:

- Secrets:
  - `CKAN_SESSION_SECRET`
  - `CKAN_APP_INSTANCE_UUID`
  - `CKAN_DB_PASSWORD`
  - `CKAN_DATASTORE_DB_PASSWORD`
  - `CKAN_DATASTORE_READONLY_PASSWORD`
- CKAN URLs:
  - `CKAN_SITE_URL` (public URL used by users, eg `https://localhost:8085`, or `https://mydomain.eu`)
  - `CKAN_INTERNAL_SITE_URL` (container-internal URL for xloader, keep `http://ckan:5000`)
- Extension context:
  - `FAIR3R_CONTEXT` must be one of `DEV`, `TEST`, `DEMO`, `PROD`

Mode behavior:

- `FAIR3R_CONTEXT=DEV`:
  - dev supervisor profile
  - CKAN reloader enabled
  - editable install from `/plugins` mount
- `FAIR3R_CONTEXT=TEST|DEMO|PROD`:
  - prod supervisor profile
  - CKAN reloader disabled
  - extension install at image build time (from git URLs)

## 3) Install extensions at image build time (not development)

Use this mode for test/demo/prod-like environments.

In `.env`:

- `FAIR3R_CONTEXT=PROD` (or `TEST` / `DEMO`)
- `CKAN_DEBUG` = **false**
- Set git URLs:
  - `FAIR3R_EXTENSION_GIT_URL`
  - `PAGE_EXTENSION_GIT_URL`
  - `DOI_EXTENSION_GIT_URL`
- Enable plugins:
  - `CKAN_EXTRA_PLUGINS="fair3r doi pages plotly_explorer"`
  - `CKAN_EXTRA_VIEWS="plotly_explorer"`

Then build and start:

```bash
docker compose up -d --build
```

## 4) Install extensions for development (editable mode)

Use this mode when actively modifying extension code.

In `.env`:

- `FAIR3R_CONTEXT=DEV`
- `CKAN_DEBUG` = **true**
- `CKAN_EXTRA_PLUGINS="fair3r doi pages plotly_explorer"`
- `CKAN_EXTRA_VIEWS="plotly_explorer"`

Clone your extensions into `src_extensions`:

```bash
git clone <fair3r_repo_url> src_extensions/ckanext-fair3r
git clone <doi_repo_url> src_extensions/ckanext-doi
git clone <pages_repo_url> src_extensions/ckanext-pages
```

Then start:

```bash
docker compose up -d --build
```

In this mode, extensions under `src_extensions` are installed/editable in container startup, and CKAN reload is enabled.

## 5) Start, restart, stop services

Start (or start again in background):

```bash
docker compose up -d
```

Rebuild changed images and restart:

```bash
docker compose up -d --build
```

Restart running containers (no rebuild):

```bash
docker compose restart
```

Stop and remove containers/networks:

```bash
docker compose down
```

**Full reset** (ALSO REMOVE VOLUMES):

```bash
docker compose down -v --remove-orphans
```

Useful checks:

```bash
docker compose ps
docker compose logs -f ckan
```

## 6) Create a sysadmin user

Use the helper script:

```bash
docker compose exec ckan /srv/app/scripts/create_sysadmin.sh admin admin@example.com "StrongPassword123!"
```

Or use automatic bootstrap at startup by setting in `.env`:

- `CKAN_BOOTSTRAP_SYSADMIN_NAME`
- `CKAN_BOOTSTRAP_SYSADMIN_EMAIL`
- `CKAN_BOOTSTRAP_SYSADMIN_PASSWORD`

## 7) Notes

- `CKAN_INTERNAL_SITE_URL` should stay reachable from inside the `ckan` container (default `http://ckan:5000`), otherwise xloader will fail (for exemple, you will not be able to upload csv(s) into the datastore).
- Startup is idempotent:
  - fresh DB: `ckan db init`
  - existing DB: `ckan db upgrade`
