# Configuration reference

Every setting of the Docker stack is an environment variable in `.env`
(copied from `.env.example`). At each start, the `ckan` container renders
`ckan.ini` from `ckan/config/ckan.ini.template` with these values
(`envsubst`), then applies the extension settings with `ckan config-tool`
(`ckan/scripts/entrypoint.sh`).

The servers deployed with Ansible use the **same template and the same
settings**, but get their values from Ansible variables and GitLab CI
variables instead of `.env` - see [deploy-ansible.md](deploy-ansible.md).

After changing `.env`, apply it with `docker compose up -d` (recreates the
container); `docker compose restart` doesn't re-read `.env`.

## Mode

| Variable | Default | Meaning |
|---|---|---|
| `FAIR3R_CONTEXT` | `PRODUCTION` | `DEV`: clones in `src_extensions/` replace the extensions' PyPI releases (editable installs), code reloader, development tools in the image. `INTEGRATION` / `VALIDATION` / `PRODUCTION`: production process settings, the PyPI releases built into the image. Also passed to the FAIR3R extension. |
| `CKAN_DEBUG` | `false` | `true` for development only (debug toolbar, detailed errors) |
| `CKAN_VERSION` | `2.12.0` | Tag of the CKAN base image |
| `CKAN_BASE_IMAGE` | `ckan/ckan-base` | Base image name - see [development.md](development.md#python-version) to match production's Python |

## Addresses and ports

| Variable | Default | Meaning |
|---|---|---|
| `CKAN_SITE_URL` | `http://localhost:5000` | Public URL of the site, as users reach it. Used in links, emails and API responses - must match how you open the site |
| `CKAN_INTERNAL_SITE_URL` | `http://ckan:5000` | URL the background workers use to reach CKAN inside Docker. Keep the default |
| `CKAN_PORT` | `5000` | Host port for CKAN (development override) |
| `NGINX_SSLPORT_HOST` | `8085` | Host port for nginx (HTTPS, self-signed certificate) |
| `NGINX_SSLPORT` | `443` | nginx's port inside its container |
| `CKAN_DB_PORT_EXT` | `5435` | Host port for PostgreSQL (development override) |

## Secrets

Change all of them for anything else than a local try.

| Variable | Meaning |
|---|---|
| `CKAN_SESSION_SECRET`, `CKAN_SECRET_KEY` | Session signing keys - long random strings |
| `CKAN_APP_INSTANCE_UUID` | Identifier of this instance - a UUID |
| `CKAN_DB_PASSWORD` | PostgreSQL password of the `ckan` user |
| `CKAN_DATASTORE_DB_PASSWORD`, `CKAN_DATASTORE_READONLY_PASSWORD` | Passwords of the DataStore users (tabular data) |

The database names and users (`CKAN_DB_*`, `CKAN_DATASTORE_*`,
`CKAN_TEST_DB_NAME`, `CKAN_DATASTORE_TEST_DB_NAME`) rarely need changing.
The test databases are created for the extensions' test suites.

## Accounts created at startup

| Variable | Meaning |
|---|---|
| `CKAN_BOOTSTRAP_SYSADMIN_NAME`, `..._EMAIL`, `..._PASSWORD` | Administrator account, created if missing, its password reset to this value at every start. Also the account the CSV loader (xloader) uses: leave it empty and CSV files aren't loaded into the data viewer |
| `CKAN_HARVEST_USER_NAME`, `..._EMAIL`, `..._PASSWORD` | Optional technical administrator for harvest jobs; not created when empty |

## Extensions

| Variable | Default | Meaning |
|---|---|---|
| `CKAN_EXTRA_PLUGINS` | `pages fair3r plotly_explorer citations` | Plugins enabled on top of the base list (CKAN core views, DataStore, xloader, DCAT, OAI-PMH, statistics, contact...). Each one's database migration runs only if it's listed. Order matters: the first-listed plugin's templates win - keep `pages` before `fair3r`, or the Pages and Blog links disappear from the header. The default needs no external account; add `doi` and `zenodo audio_view video_view` with their accounts (below). The servers enable `doi` too (`deploy/ansible/group_vars/all.yml`) |
| `CKAN_EXTRA_VIEWS` | `plotly_explorer` | Views created automatically for new resources |
| `CKAN_MAX_RESOURCE_SIZE` | `20` | Largest file stored in CKAN, in MB. Keep it at or below nginx's limit (20M, `nginx/setup/nginx.conf`). With Zenodo enabled, larger files go to Zenodo, through nginx's own `/zenodo/upload/` route (10G) |

The FAIR3R extensions' PyPI releases are built into the image
(`ckan/fair3r-extensions.txt`). Optional private package registry, only
if you have access to a GitLab instance that publishes them; otherwise
leave the tokens empty: `GITLAB_EXTENSIONS_PYPI_HOST`,
`*_EXTENSION_PYPI_TOKEN`, `*_PYPI_PROJECT_ID`. When a token is set, that
extension is reinstalled from the registry at startup; in `DEV`, a clone
in `src_extensions/` still wins.

### FAIR3R (ckanext-fair3r)

| Variable | Meaning |
|---|---|
| `FAIR3R_ENABLE_FDF_INTEGRATION` | `true` to use the FDF metadata form |
| `FDF_SCHEMA_LOCAL_PATH` | `DEV` only: absolute path to a local clone of [fair3r-fdf-schema](https://github.com/Phen-ICS/fair3r-fdf-schema), read live. Empty: the schema is downloaded from GitHub at startup |

### Contact form (ckanext-contact)

| Variable | Meaning |
|---|---|
| `CONTACT_MAIL` | Address the contact form writes to |

### DataCite DOIs (ckanext-doi)

Needs a DataCite account (a test account for anything but production).
Enable with `doi` in `CKAN_EXTRA_PLUGINS`, once the settings below are
filled in: with the plugin on and no account, making a dataset public
fails.

| Variable | Meaning |
|---|---|
| `DOI_ACCOUNT_NAME`, `DOI_ACCOUNT_PASSWORD` | DataCite repository account |
| `DOI_PREFIX` | Your DOI prefix (e.g. `10.12345`) |
| `DOI_PUBLISHER` | Publisher written in the DOI metadata |
| `DOI_SITE_TITLE` | Site name used in the DOI metadata |
| `DOI_TEST_MODE` | `True`: DataCite's test system (test DOIs, not resolvable on doi.org). `False` only in production |

### Zenodo (ckanext-zenodo)

Stores large or non-tabular files on Zenodo. Enable with
`zenodo audio_view video_view` in `CKAN_EXTRA_PLUGINS`. Without a token
for the current mode it stays out of the way (every file stays in CKAN).
Full reference in
[ckanext-zenodo's documentation](https://github.com/Phen-ICS/ckanext-zenodo/blob/main/docs/README.md).

| Variable | Meaning |
|---|---|
| `ZENODO_TEST_MODE` | `True`: sandbox.zenodo.org; `False`: zenodo.org |
| `ZENODO_SANDBOX_ACCESS_TOKEN` | Token of the Zenodo account on the sandbox |
| `ZENODO_ACCESS_TOKEN` | Token on zenodo.org |
| `ZENODO_COMMUNITY_IDENTIFIER` | Community records are filed into (the token's account must be owner, manager or curator of it) |
| `ZENODO_DISK_SAFETY_MARGIN_BYTES` | Disk space always left free by uploads in transit (default 5 GB) |

Check the setup with `docker compose exec ckan ckan -c /srv/app/ckan.ini zenodo check`.

`OPENALEX_API_KEY` (optional, ckanext-citations): a free key from
https://openalex.org/settings/api. Without it, every caller behind the same
IP shares one free OpenAlex budget ($0.10/day, about 1000 list requests);
with it, the site has its own ($1/day).

### Email (SMTP)

| Variable | Meaning |
|---|---|
| `CKAN_EMAIL_SMTP_SERVER` | `host:port` |
| `CKAN_EMAIL_SMTP_STARTTLS`, `CKAN_EMAIL_SMTP_STARTTLS_VERIFY` | TLS settings |
| `CKAN_EMAIL_SMTP_USER`, `CKAN_EMAIL_SMTP_PASSWORD` | Login |
| `CKAN_EMAIL_SMTP_MAIL_FROM`, `CKAN_EMAIL_SMTP_REPLY_TO` | Sender and reply-to |
| `CKAN_EMAIL_SMTP_EMAIL_TO`, `CKAN_EMAIL_SMTP_ERROR_EMAIL_FROM` | Error report recipient and sender |

## Settings that aren't variables

Fixed in `ckan/config/ckan.ini.template` (same on every environment):
languages (English default, French offered), the base plugin list and
default views, Solr and Redis addresses, upload storage path. Pages
extension settings (organization and group pages, HTML, editor) are set
by the entrypoint.
