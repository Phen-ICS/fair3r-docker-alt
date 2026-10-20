# Quick start: try FAIR3R on your machine

This runs the whole catalogue - CKAN 2.12 with the FAIR3R extensions,
PostgreSQL, Solr, Redis and nginx - in Docker on your own machine, to try
it out or to work on it. The first start takes around 10 minutes (image
build); later ones, about a minute.

Nothing here is meant for a public server: use [deploy-ansible.md](deploy-ansible.md)
for that.

## 1. What you need

- **Docker** with the Compose plugin (`docker compose version` works).
- **git**.
- About **10 GB** of free disk space and **4 GB** of RAM for Docker.
- Free ports **5000** (CKAN), **8085** (nginx, HTTPS) and **5435**
  (PostgreSQL, from your machine). They can be changed in `.env`.
- Internet access during the first start (images, Python packages, the
  FDF form schema).

## 2. Get the code

The deployment repository, then the FAIR3R extensions inside its
`src_extensions/` folder (mounted into the container and installed from
there):

```bash
git clone https://github.com/Phen-ICS/fair3r-docker-alt.git
cd fair3r-docker-alt

for repo in ckanext-fair3r ckanext-doi ckanext-pages ckanext-plotly ckanext-citations ckanext-zenodo; do
  git clone "https://github.com/Phen-ICS/${repo}.git" "src_extensions/${repo}"
done
```

The folder names don't have to match the package names
(`src_extensions/ckanext-doi` installs `ckanext-fair3r-doi`, and so on).

## 3. Configure

```bash
cp .env.example .env
```

Then edit `.env` and set:

```ini
# Development mode: extensions installed from src_extensions/, code reloads
FAIR3R_CONTEXT=DEV
CKAN_DEBUG=true

# Your administrator account, created at startup
CKAN_BOOTSTRAP_SYSADMIN_NAME=admin
CKAN_BOOTSTRAP_SYSADMIN_EMAIL=admin@example.org
CKAN_BOOTSTRAP_SYSADMIN_PASSWORD=choose-a-password

# No DataCite account? Leave doi out - otherwise making a dataset public fails.
CKAN_EXTRA_PLUGINS=fair3r pages plotly_explorer citations
```

Set the administrator account: besides letting you log in, it's what the
background loader of CSV files (xloader) runs as - without it, uploaded
CSV files aren't loaded into the data viewer.

Everything else can stay as it is for a local try. The full list of
settings is in [configuration.md](configuration.md); the optional services
(DataCite DOIs, Zenodo, email) are described there too.

## 4. Start

```bash
docker compose up -d --build
```

`docker compose` automatically adds `docker-compose.override.yml`, which
holds the development settings (the `src_extensions/` mount, CKAN's port
5000, the database port).

Follow the startup until CKAN reports it's ready:

```bash
docker compose logs -f ckan
```

The first start builds the image, creates the databases and the
administrator, and downloads the FDF form schema. `docker compose ps`
shows `ckan-app` as `healthy` when it's done.

## 5. Use it

- **http://localhost:5000** - CKAN directly (simplest).
- **https://localhost:8085** - through nginx, as on a server. The
  certificate is self-signed: your browser will warn you the first time.

Log in with the administrator account from `.env`. To try the catalogue:
create an organization, then a dataset (the FAIR3R metadata form), add a
CSV file, and make the dataset public.

## 6. Day-to-day commands

| Task | Command |
|---|---|
| Stop | `docker compose stop` |
| Start again | `docker compose up -d` |
| See CKAN's logs | `docker compose logs -f ckan` |
| Rebuild after changing the Dockerfile, requirements or `.env` | `docker compose up -d --build` |
| Remove everything, **including all data** | `docker compose down -v` |

Code changes in `src_extensions/` are picked up without rebuilding:
Python code by CKAN's reloader, templates on the next page load. See
[development.md](development.md) for working on the extensions.

## Optional services

| Service | Needed for | How |
|---|---|---|
| DataCite | Minting a DOI when a dataset is made public | A DataCite test account; set `DOI_*` in `.env` and add `doi` back to `CKAN_EXTRA_PLUGINS` |
| Zenodo | Storing large files on Zenodo | A token from [sandbox.zenodo.org](https://sandbox.zenodo.org/) and a community; set `ZENODO_*` and add `zenodo audio_view video_view` to `CKAN_EXTRA_PLUGINS` |
| Email | Password reset, notifications | An SMTP server; set `CKAN_EMAIL_SMTP_*` |

After changing `.env`: `docker compose up -d` (a plain `restart` doesn't
reload `.env`).

## When it doesn't start

| Symptom | Cause / fix |
|---|---|
| `port is already allocated` | Another program uses 5000, 8085 or 5435: change `CKAN_PORT`, `NGINX_SSLPORT_HOST` or `CKAN_DB_PORT_EXT` in `.env` |
| `ckan-app` restarts in a loop | `docker compose logs ckan` shows the failing step - usually a plugin listed in `CKAN_EXTRA_PLUGINS` whose repository isn't in `src_extensions/`, or a typo in `.env` |
| "Plugin ... not found" | The extension isn't cloned in `src_extensions/`, or `FAIR3R_CONTEXT` isn't `DEV` |
| CSV files show no data | `CKAN_BOOTSTRAP_SYSADMIN_*` not set (see step 3), then `docker compose up -d` |
| Making a dataset public fails with a DataCite error | `doi` is enabled without a DataCite account - remove it from `CKAN_EXTRA_PLUGINS` |
| Start over from scratch | `docker compose down -v`, then `docker compose up -d --build` |
