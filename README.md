# CKAN 2.10 Docker Compose Deployment

This project deploys CKAN **2.10.9** (latest stable `2.10.x`) with:

- `ckan`: CKAN web app + xloader worker in one container (managed by `supervisord`)
- `db`: PostgreSQL 14
- `solr`: `ckan/ckan-solr:2.10-solr9`
- `redis`: Redis 7

## 1) Prerequisites

- Docker and Docker Compose plugin installed
- Open port `5000` on your machine

## 2) Configure environment

Copy the example environment file:

```bash
cp .env.example .env
```

Edit `.env` and set secure values for:

- `CKAN_SESSION_SECRET`
- `CKAN_APP_INSTANCE_UUID`
- `CKAN_XLOADER_API_TOKEN`
- `CKAN_DB_PASSWORD`
- `CKAN_DATASTORE_DB_PASSWORD`
- `CKAN_DATASTORE_READONLY_PASSWORD`

To auto-install your FAIR3R extension at image build time and enable the
plugin in CKAN, set:

- `FAIR3R_EXTENSION_GIT_URL` (eg `git+http://oauth2:<TOKEN>@serv-gitlab.../ckanext-fair3r.git`)
- `CKAN_EXTRA_PLUGINS=fair3r`

`FAIR3R_EXTENSION_GIT_URL` is passed as a Docker build arg, and if set the
Dockerfile runs `pip install` on it.

For automatic xloader token rotation at startup (recommended), also set:

- `CKAN_XLOADER_TOKEN_USER` (existing CKAN user, usually a sysadmin)
- `CKAN_XLOADER_TOKEN_NAME` (defaults to `xloader`)
- `CKAN_BOOTSTRAP_SYSADMIN_NAME` (optional, create/promote this user at startup)
- `CKAN_BOOTSTRAP_SYSADMIN_EMAIL` (required only when creating the bootstrap user)
- `CKAN_BOOTSTRAP_SYSADMIN_PASSWORD` (required only when creating the bootstrap user)

When `CKAN_XLOADER_TOKEN_USER` is set, startup will:

1. list the user's API tokens,
2. revoke tokens named `CKAN_XLOADER_TOKEN_NAME`,
3. create a new token with that name,
4. inject it into `ckan.ini` as `ckanext.xloader.api_token`.

Note: this is done at container startup (not image build), because token creation needs a live CKAN database and initialized app.
The startup script ensures `CKAN_XLOADER_TOKEN_USER` is sysadmin before issuing the token; otherwise xloader may fail with `NotAuthorized` when downloading resources.
If `CKAN_BOOTSTRAP_SYSADMIN_NAME` is set, startup will create/promote that user before rotating the xloader token, so `CKAN_XLOADER_API_TOKEN` can be left empty.

## 3) Start services

Build and start all services:

```bash
docker compose up -d --build
```

Follow logs:

```bash
docker compose logs -f ckan
```

CKAN will be available at:

- `http://localhost:5000`

## 4) Stop services

Stop without deleting data:

```bash
docker compose down
```

Stop and remove volumes (full reset):

```bash
docker compose down -v
```

## 5) Create a sysadmin user

Use the included helper script:

```bash
docker compose exec ckan /srv/app/scripts/create_sysadmin.sh admin admin@example.com "StrongPassword123!"
```

You can then log in with this user and administer CKAN.

## 6) Verify xloader is running

The xloader worker runs in the same `ckan` container through `supervisord`.

Check both processes:

```bash
docker compose exec ckan supervisorctl status
```

Expected:

- `ckan-web` in `RUNNING`
- `xloader-worker` in `RUNNING`

To verify xloader behavior:

1. Upload a tabular resource (CSV) to a dataset.
2. Ensure DataStore is enabled for the resource.
3. Check worker logs:

```bash
docker compose logs -f ckan
```

Look for `xloader` job execution entries and successful DataStore load messages.

## 7) Notes on initialization

- At container startup, entrypoint script waits for PostgreSQL, Solr, and Redis.
- It renders `/srv/app/ckan.ini` from `ckan/config/ckan.ini.template`.
- It creates the DataStore DB/user if missing and applies `datastore set-permissions`.
- Database setup is idempotent:
  - fresh DB: `ckan db init`
  - existing DB: `ckan db upgrade`

## 8) Production readiness considerations

- Replace all example secrets in `.env`.
- Use a reverse proxy (Nginx/Traefik) with TLS in front of CKAN.
- Restrict DB/Solr/Redis network exposure to private networks only.
- Enable regular backups for PostgreSQL and persistent Docker volumes.
- Monitor logs and container health checks (`docker compose ps`).
