# Quick start: run FAIR3R on your machine

This runs the whole catalogue - CKAN 2.12 with the FAIR3R extensions,
PostgreSQL, Solr, Redis and nginx - in Docker on your own machine. The
first start takes around 10 minutes (image build); later ones, about a
minute.

Two ways to run it:

| | You want to... | Extensions come from |
|---|---|---|
| **[Try it](#try-it)** | See and use the catalogue | Their releases on PyPI, built into the image - nothing else to download |
| **[Work on the code](#work-on-the-code)** | Change an extension and see the result | Your own clones in `src_extensions/`, replacing the PyPI releases |

Nothing here is meant for a public server: use [deploy-ansible.md](deploy-ansible.md)
for that.

## What you need

- **Docker** with the Compose plugin (`docker compose version` works).
- **git**.
- About **10 GB** of free disk space and **4 GB** of RAM for Docker.
- Free ports **5000** (CKAN), **8085** (nginx, HTTPS) and **5435**
  (PostgreSQL, from your machine). They can be changed in `.env`.
- Internet access during the first start (images, Python packages, the
  FDF form schema).

## Try it

### 1. Get the code

```bash
git clone https://github.com/Phen-ICS/fair3r-docker-alt.git
cd fair3r-docker-alt
```

### 2. Configure

```bash
cp .env.example .env
```

Then edit `.env` and set your administrator account, created at startup:

```ini
CKAN_BOOTSTRAP_SYSADMIN_NAME=admin
CKAN_BOOTSTRAP_SYSADMIN_EMAIL=admin@example.org
CKAN_BOOTSTRAP_SYSADMIN_PASSWORD=choose-a-password
```

Besides letting you log in, it's what the loader of CSV files into the
data viewer (xloader) runs as - without it, uploaded CSV files show no
data.

Everything else can stay as it is: the default works without any
external account. DataCite DOIs, Zenodo and email are
[optional services](#optional-services) you add once you have an
account; all settings are in [configuration.md](configuration.md).

### 3. Start

```bash
docker compose up -d --build
```

Follow the startup until CKAN is ready:

```bash
docker compose logs -f ckan
```

The first start builds the image, creates the databases and the
administrator, and downloads the FDF form schema. `docker compose ps`
shows `ckan-app` as `healthy` when it's done.

### 4. Use it

- **http://localhost:5000** - CKAN directly (simplest).
- **https://localhost:8085** - through nginx, as on a server. The
  certificate is self-signed: your browser warns about it the first time.

Log in with the administrator account from `.env`. To try the catalogue:
create an organization, then a dataset (the FAIR3R metadata form), add a
CSV file, and make the dataset public.

## Work on the code

Same as above, plus a clone of each extension you want to change in
`src_extensions/`. At each start, the container installs every clone
found there in editable mode, replacing that extension's PyPI release;
the others keep their release.

### 1. Clone what you'll work on

```bash
git clone https://github.com/Phen-ICS/fair3r-docker-alt.git
cd fair3r-docker-alt

# Only the ones you'll change - for example:
git clone https://github.com/Phen-ICS/ckanext-fair3r.git src_extensions/ckanext-fair3r
```

| Repository | Folder in `src_extensions/` |
|---|---|
| [ckanext-fair3r](https://github.com/Phen-ICS/ckanext-fair3r) | `ckanext-fair3r` |
| [ckanext-doi](https://github.com/Phen-ICS/ckanext-doi) | `ckanext-doi` |
| [ckanext-pages](https://github.com/Phen-ICS/ckanext-pages) | `ckanext-pages` |
| [ckanext-plotly](https://github.com/Phen-ICS/ckanext-plotly) | `ckanext-plotly` |
| [ckanext-citations](https://github.com/Phen-ICS/ckanext-citations) | `ckanext-citations` |
| [ckanext-zenodo](https://github.com/Phen-ICS/ckanext-zenodo) | `ckanext-zenodo` |

The folder name doesn't matter - the package inside does
(`src_extensions/ckanext-doi` replaces `ckanext-fair3r-doi`).

### 2. Configure

As in [Try it](#2-configure), plus development mode:

```ini
FAIR3R_CONTEXT=DEV
CKAN_DEBUG=true
```

### 3. Start

```bash
docker compose up -d --build
```

`docker compose` automatically adds `docker-compose.override.yml`, which
mounts `src_extensions/` into the container (at `/plugins`).

From then on, your changes show without rebuilding: Python code through
CKAN's reloader, templates on the next page load. A clone added or
removed needs `docker compose up -d`. Tests, translations and the FDF
form schema: [development.md](development.md).

## Day-to-day commands

| Task | Command |
|---|---|
| Stop | `docker compose stop` |
| Start again | `docker compose up -d` |
| See CKAN's logs | `docker compose logs -f ckan` |
| Apply a change to `.env` | `docker compose up -d` (a plain `restart` doesn't re-read `.env`) |
| Get the latest extension releases from PyPI | `docker compose build --no-cache ckan && docker compose up -d` |
| Remove everything, **including all data** | `docker compose down -v` |

## Optional services

Each one needs an account with the service. Not enabled by default.

| Service | Needed for | Account | Enable in `.env` |
|---|---|---|---|
| DataCite | A DOI for each dataset made public | DataCite test account (repository) | Set `DOI_*`, add `doi` to `CKAN_EXTRA_PLUGINS` |
| Zenodo | Storing large or non-tabular files on Zenodo | Token from [sandbox.zenodo.org](https://sandbox.zenodo.org/), and a community | Set `ZENODO_*`, add `zenodo audio_view video_view` to `CKAN_EXTRA_PLUGINS` |
| Email | Password reset, notifications | An SMTP server | Set `CKAN_EMAIL_SMTP_*` |

Then `docker compose up -d`. With `doi` enabled, making a dataset public
needs a working DataCite account. Zenodo stays out of the way until its
token is set: `docker compose exec ckan ckan -c /srv/app/ckan.ini zenodo check`
tells what's missing.

## When it doesn't start

| Symptom | Cause / fix |
|---|---|
| `port is already allocated` | Another program uses 5000, 8085 or 5435: change `CKAN_PORT`, `NGINX_SSLPORT_HOST` or `CKAN_DB_PORT_EXT` in `.env` |
| `ckan-app` restarts in a loop | `docker compose logs ckan` shows the failing step - often a typo in `.env` or in `CKAN_EXTRA_PLUGINS` |
| CSV files show no data | `CKAN_BOOTSTRAP_SYSADMIN_*` not set, then `docker compose up -d` |
| Making a dataset public fails with a DataCite error | `doi` is enabled but the `DOI_*` account settings are missing or wrong |
| My code changes don't show | `FAIR3R_CONTEXT=DEV` in `.env`, the clone in `src_extensions/`, then `docker compose up -d --build` |
| Start over from scratch | `docker compose down -v`, then `docker compose up -d --build` |
