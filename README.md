![Docker](https://img.shields.io/badge/docker-24.x-blue)
![CKAN](https://img.shields.io/badge/CKAN-2.11.5-orange)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-14-blueviolet)
![Redis](https://img.shields.io/badge/Redis-7-red)

# CKAN 2.11 Fair3r Docker Compose Deployment

This project deploys CKAN `2.11.5` with:

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
  - `FAIR3R_CONTEXT` must be one of `DEV`, `INTEGRATION`, `VALIDATION`, `PRODUCTION`
- FDF schema (DEV only):
  - `FDF_SCHEMA_LOCAL_PATH` — absolute path on the host to a clone of
    [`fair3r-fdf-schema`](https://github.com/Phen-ICS/fair3r-fdf-schema)
    (the directory that contains `fdf_schema.json`). Leave empty in
    `INTEGRATION` / `VALIDATION` / `PRODUCTION`.

Mode behavior:

- `FAIR3R_CONTEXT=DEV`:
  - dev supervisor profile
  - CKAN reloader enabled
  - editable install from `/plugins` mount
  - FDF schema: if `FDF_SCHEMA_LOCAL_PATH` points at a local clone, Fair3R reads
    `fdf_schema.json` and `i18n/` from that mount (no GitHub download). If unset,
    the entrypoint downloads the latest schema from GitHub like other contexts.
- `FAIR3R_CONTEXT=INTEGRATION|VALIDATION|PRODUCTION`:
  - production supervisor profile (same as packaged `supervisord.prod.conf` in the image)
  - CKAN reloader disabled
  - extension install at image build time (from git URLs)

## 3) Fair3R extensions via GitLab PyPI (`INTEGRATION` / `VALIDATION` / `PRODUCTION`)

For non-development contexts, extensions are pulled from GitLab Package Registry PyPI **when the CKAN container starts** (credentials from `.env`, not bundled in the image).

In `.env`:

- `FAIR3R_CONTEXT=PRODUCTION` (or `INTEGRATION` / `VALIDATION`)
- `CKAN_DEBUG` = **false**
- `GITLAB_EXTENSIONS_PYPI_HOST` (in our case `gitlab.igbmc.u-strasbg.fr`)
  - `FAIR3R_EXTENSION_PYPI_TOKEN`
  - `PAGE_EXTENSION_PYPI_TOKEN`
  - `DOI_EXTENSION_PYPI_TOKEN`
  - `PLOTLY_EXTENSION_PYPI_TOKEN`
  - `FAIR3R_PYPI_PROJECT_ID`
  - `PAGE_PYPI_PROJECT_ID`
  - `DOI_PYPI_PROJECT_ID`
  - `PLOTLY_PYPI_PROJECT_ID`
- Enable plugins:
  - `CKAN_EXTRA_PLUGINS="fair3r doi pages plotly_explorer"`
  - `CKAN_EXTRA_VIEWS="plotly_explorer"`

Then build and start:

```bash
docker compose up -d --build
```

Details and project ID defaults match [`deploy/README.md`](./deploy/README.md) and `deploy/ansible/group_vars/all.yml`.

## 4) Development (`DEV`): GitLab PyPI and/or editable `src_extensions`

Use **`FAIR3R_CONTEXT=DEV`** when developing.

Leave the GitLab PyPI token variables (and host) in `.env` empty. On startup the entrypoint will not installs the four extensions from the registry.

Clone into `src_extensions` (mounted as `/plugins`; directory names must match the pip distribution names, e.g. `src_extensions/ckanext-fair3r`, `src_extensions/ckanext` for the DOI extension).
2. Set the same GitLab tokens if you **also** want wheels for extensions you are **not** mounting; for any directory under `/plugins`, the entrypoint runs `pip install -e` **after** the registry step so your tree wins.

In `.env`:

- `FAIR3R_CONTEXT=DEV`
- `CKAN_DEBUG=true`
- Tokens and/or mounted repos as needed
- `CKAN_EXTRA_PLUGINS="fair3r doi pages plotly_explorer"`
- `CKAN_EXTRA_VIEWS="plotly_explorer"`
- `FDF_SCHEMA_LOCAL_PATH=/absolute/path/to/fair3r-fdf-schema` (your local clone
  of [`fair3r-fdf-schema`](https://github.com/Phen-ICS/fair3r-fdf-schema))

Clone your extensions into `src_extensions`:

```bash
git clone <fair3r_repo_url> src_extensions/ckanext-fair3r
git clone <doi_repo_url> src_extensions/ckanext
git clone <pages_repo_url> src_extensions/ckanext-pages
git clone <plotly_repo_url> src_extensions/ckanext-plotly
```

Clone the FDF schema repo anywhere on your machine (it does **not** live under
`src_extensions`). Edit schema files on a feature branch of that clone; Fair3R
DEV reads them live from the mount, so you do not copy JSON into
`ckanext-fair3r` and a container restart cannot overwrite your work. A reviewer
checks out the same branch in their own clone, sets `FDF_SCHEMA_LOCAL_PATH`,
and recreates the stack (`docker compose up -d`) to test the form.

```bash
git clone git@github.com:Phen-ICS/fair3r-fdf-schema.git /path/to/fair3r-fdf-schema
```

After changing `FDF_SCHEMA_LOCAL_PATH`, recreate the CKAN container so Compose
reattaches the bind mount (`docker compose up -d` is enough; `restart` is not).
Schema JSON edits themselves are picked up on the next page load — no restart.

Then start:

```bash
docker compose up -d --build
```

Editable installs apply on each container start while CKAN’s dev reloader watches code changes where supported.

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

## 6) Create users

### Create a regular user

#### In DEV

```bash
docker compose exec ckan ckan -c /srv/app/ckan.ini user add jdoe \
  email=jdoe@example.com \
  password=StrongPassword123! \
  fullname="John Doe"
```

- `jdoe` is the username (required, first positional argument)
- `email=` is required
- `password=` is required (minimum 8 characters); if omitted, CKAN prompts for it
- `fullname=` is optional

Useful related commands:

```bash
docker compose exec ckan ckan -c /srv/app/ckan.ini user list
docker compose exec ckan ckan -c /srv/app/ckan.ini user show jdoe
docker compose exec ckan ckan -c /srv/app/ckan.ini user remove jdoe
```

#### In integration, validation or production

```bash
sudo ckan -c /etc/ckan/default/ckan.ini user add jdoe \
  email=jdoe@example.com \
  password=StrongPassword123! \
  fullname="John Doe"
```

### Create a sysadmin user

#### In DEV

Use the helper script:

```bash
docker compose exec ckan /srv/app/scripts/create_sysadmin.sh admin admin@example.com "StrongPassword123!"
```

Or use automatic bootstrap at startup by setting in `.env`:

- `CKAN_BOOTSTRAP_SYSADMIN_NAME`
- `CKAN_BOOTSTRAP_SYSADMIN_EMAIL`
- `CKAN_BOOTSTRAP_SYSADMIN_PASSWORD`

### In integration, validation or production:

```bash
sudo ckan -c /etc/ckan/default/ckan.ini sysadmin add admin email=admin@example.com name=admin
```

## 7) Notes

- `CKAN_INTERNAL_SITE_URL` should stay reachable from inside the `ckan` container (default `http://ckan:5000`), otherwise xloader will fail (for exemple, you will not be able to upload csv(s) into the datastore).
- Startup is idempotent:
  - fresh DB: `ckan db init`
  - existing DB: `ckan db upgrade`

## 8) Updating translations

The UI is available in **English** (default) and **French** (`ckan.locale_default`
and `ckan.locales_offered` in `ckan/config/ckan.ini.template`). CKAN core ships
its own French catalog; maintain translations in three of the four Fair3R extensions under
`src_extensions/` (`ckanext-fair3r`, `ckanext-doi`, `ckanext-pages`). Each ships `i18n/<domain>.pot` and
`i18n/fr/LC_MESSAGES/<domain>.{po,mo}` — commit both `.po` and `.mo`.

Wrap new user-visible strings before extracting: Python `toolkit._()`, Jinja
`{{ _('…') }}` / `{% trans %}`, CKAN JS modules `_("…")`.

In **DEV**, run Babel inside the `ckan` container (extensions mounted at
`/plugins/ckanext-*`):

```bash
docker compose exec ckan bash -lc '
  for ext in fair3r doi pages; do
    cd /plugins/ckanext-$ext
    python setup.py extract_messages
    python setup.py update_catalog -l fr
  done
'
```

Edit i18n/fr/LC_MESSAGES/*.po — fill empty msgstr, remove fuzzy flags.
Then, execute following command:
```bash
docker compose exec ckan bash -lc '
  for ext in fair3r doi pages; do
    cd /plugins/ckanext-$ext
    python setup.py compile_catalog -l fr
  done
'
docker compose restart ckan
```

**fair3r FDF schema** — user-facing strings in `fdf_schema.json` are translated
via sidecar files in `i18n/<locale>.json`, maintained in the
[`fair3r-fdf-schema`](https://github.com/Phen-ICS/fair3r-fdf-schema) repository
(separate from Babel).

On **validation / integration / production**, the nightly `fair3r update-schema`
cron downloads both the schema and locale files into `schema/` and
`schema/i18n/` inside the installed extension.

In **DEV**, set `FDF_SCHEMA_LOCAL_PATH` in `.env` when you work on a schema
branch: the Compose override mounts that clone at `/fdf-schema` and Fair3R reads
it live (no GitHub download on startup). Leave `FDF_SCHEMA_LOCAL_PATH` empty to
use the GitHub download at container start instead — same as validation /
integration / production (nightly cron on the VMs).

Contributors edit translations in the schema repo:

```bash
cd /path/to/fair3r-fdf-schema
python tools/i18n.py template --locale fr   # refresh keys after schema edits
python tools/i18n.py check --locale fr      # verify all keys are translated
```

Sidecar keys use stable ids, e.g.
`sections.title.fields.publication_year.help`. English text in
`fdf_schema.json` is the fallback when a translation is missing.

On **validation / integration / production** VMs, publish updated extension
wheels to GitLab PyPI and re-deploy; restart `ckan-web` and `ckan-worker` so
gettext reloads.

## 9) Deployment

Fair3R runs in four deployment contexts (`dev` plus three native VMs):

| Context        | Where it runs                                                         | How it is triggered                                                                 |
|----------------|-----------------------------------------------------------------------|-------------------------------------------------------------------------------------|
| `dev`          | Developer workstation, Docker Compose stack (the sections above)      | `docker compose up -d --build` from this repo root with a local `.env`              |
| `validation`   | Ubuntu Noble VM `serv-ics-fair3r-d-01`, native package install        | Manual GitLab CI job **`deploy_validation`**                                        |
| `integration`  | Ubuntu Noble VM `serv-ics-fair3r-t-01`, native package install      | Manual GitLab CI job **`deploy_integration`**                                       |
| `production`     | Ubuntu Noble VM `serv-ics-fair3r-p-02`, native package install        | Manual GitLab CI job **`deploy_production`**                                        |

### `validation`, `integration`, and `production` (native install on Ubuntu Noble)

These contexts do **not** use Docker. They install CKAN 2.11 from the
official `python-ckan_2.11-noble_amd64.deb` package (see the [CKAN 2.11
install-from-package
docs](https://docs.ckan.org/en/2.11/maintaining/installing/install-from-package.html))
and provision the VM end-to-end — Postgres, Solr 9, Redis, nginx, systemd
units — via the Ansible project under [`deploy/`](./deploy/).

The pipeline's `deploy_validation` / `deploy_integration` / `deploy_production` jobs (defined in the root
[`.gitlab-ci.yml`](./.gitlab-ci.yml)) run
[`deploy/ansible_deploy.py`](./deploy/ansible_deploy.py), which wraps
`ansible-playbook` and forwards every secret as a per-context Ansible
variable (`validation_ckan_db_password`, `integration_fair3r_extension_pypi_token`, `production_ckan_db_password`, …).
All secrets must be configured as GitLab CI/CD variables — see
[`deploy/README.md`](./deploy/README.md) for the full table.

The resulting instance is supposed to be **identical** to the `dev` stack:

- Same CKAN version (2.11.5), same extensions (`xloader`, `pdf_view`,
  `contact`, `dsaudit`, `fair3r`, `doi`, `pages`, `plotly_explorer`) and
  same default views.
- Same `ckan.ini` (rendered by `envsubst` from the authoritative
  `ckan/config/ckan.ini.template`; only the output path differs:
  `/etc/ckan/default/ckan.ini` on the VM vs `/srv/app/ckan.ini` in the
  container).
- Same bootstrap flow (sysadmin create-or-sync, Xloader token rotation,
  fair3r / doi / pages `config-tool` settings, `doi initdb`,
  `db upgrade -p pages`).
- Same two long-running processes — `ckan-web` and `ckan jobs worker` —
  but managed by **systemd** (`ckan-web.service`, `ckan-worker.service`)
  instead of supervisord.

### Running the Ansible playbook manually

Requirements:

- A clean Ubuntu 24 Virtual machine (e.g: host "serv-ics-fair3r-d-01")
- Access without password to the VM. Using SSH key.
- Ansible installed on the machine running the command.

```bash
pip install ansible
ansible-galaxy collection install -r deploy/ansible/requirements.yml

python3 deploy/ansible_deploy.py \
  --env validation \
  --host serv-ics-fair3r-d-01 \
  --ckan-session-secret ... \
  --ckan-secret-key ... \
  --ckan-db-password ... \
  --fair3r-extension-pypi-token ... \
  --page-extension-pypi-token ... \
  --doi-extension-pypi-token ... \
  --plotly-extension-pypi-token ... \
  ... \
  --check   # dry-run (adds --check --diff to ansible-playbook)
```

Non-secret per-context values (site URL, contact mail, DOI publisher /
`test_mode` / site title) and pipeline-level non-secrets (sysadmin name +
email, `fair3r_enable_fdf_integration`) live in
[`deploy/ansible/group_vars/`](./deploy/ansible/group_vars/) — edit those
files and commit; no CLI flag needed.

See [`deploy/README.md`](./deploy/README.md) for the full CLI flag list
and the post-deploy QA checklist.

### Important note :

DEV environnement is using python 3.12.13 (because of docker ckan-base:2.11.5 that is using a python 3.12.13 trixie image)
Validation and production will be using 3.12.3 python, because we cannot get ubuntu 22 VMs from IT and because Ubuntu LTS usually stays on the patch level they shipped without jumping to the latest upstream micro release like 3.12.13. This remains a minor difference between environments.
