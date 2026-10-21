# Working on FAIR3R

For people changing the extensions, the form schema or this deployment.
Start with [quick-start.md](quick-start.md) to get the stack running in
`DEV` mode.

## The repositories

| Repository | Holds | Default branch |
|---|---|---|
| fair3r-docker-alt (this one) | Docker stack, Ansible deployment, CI | `main` |
| ckanext-fair3r | FDF metadata form, completeness score, DCAT/Croissant/schema.org output, upload form, "Publish" button | `main` |
| ckanext-doi | DataCite DOIs (fork of NaturalHistoryMuseum/ckanext-doi) | `main` |
| ckanext-pages | Pages, including per-organization pages (fork of ckan/ckanext-pages) | `master` |
| ckanext-plotly | Chart view (fork of USEPA/ckanext-plotly) | `master` |
| ckanext-citations | Citations, disruption index, S-index | `main` |
| ckanext-zenodo | Large files on Zenodo | `main` |
| fair3r-fdf-schema | The FDF form's JSON schema and its translations | `main` |

All are on GitHub under [Phen-ICS](https://github.com/Phen-ICS). Each
extension is published on PyPI when merged; the servers install them from
there.

## How DEV mode works

- The image already contains every FAIR3R extension's latest PyPI release
  (`ckan/fair3r-extensions.txt`).
- `src_extensions/` is mounted at `/plugins` in the `ckan` container. At
  each start, with `FAIR3R_CONTEXT=DEV`, every folder in it with a
  `setup.py` or `pyproject.toml` is installed in editable mode
  (`pip install -e`), replacing that extension's release - so your
  working copy is what runs. Clone only the extensions you work on.
- CKAN runs with its reloader: Python changes restart it, template
  changes show on the next page load. A change to `ckan.ini` settings,
  `.env` or the plugin list needs `docker compose up -d`.
- `ckan.ini` is **regenerated** from `ckan/config/ckan.ini.template` and
  `.env` at every container start: edits made inside the container are
  lost. Put lasting settings in the template or in the entrypoint.
- Which branch is checked out in `src_extensions/<repo>` is what runs -
  switching branches changes the running code.

Run CKAN commands in the container:

```bash
docker compose exec ckan ckan -c /srv/app/ckan.ini <command>
```

## Tests

Each extension's README gives its exact test command, of this form:

```bash
docker exec -u ckan -it ckan-app pytest --ckan-ini=/plugins/ckanext-fair3r/test.ini /plugins/ckanext-fair3r/ckanext/fair3r/tests
```

**Always pass `--ckan-ini` with the extension's `test.ini`.** The test
fixtures empty the database they run against; the `test.ini` points them
at the `ckan_test` database, and the extensions' test setup refuses to
run against a database whose name doesn't contain `test`. Without
`--ckan-ini`, pytest would otherwise fall back to the site's own
configuration.

On the integration server, the same suites run with the `test.ini`
shipped inside each package (`test:integration:*` jobs) - keep it in
sync with the repository's own.

Lint before pushing: `ruff check` and `ruff format --check` (each
extension's CI runs them).

## Merge requests and versions

- Every extension's CI has a `version:check` job: a merge request must
  change the package version. If another merge request bumped it in the
  meantime, bump again from the current value on the target branch.
- A merge request on an extension also deploys its build to integration
  and runs the integration tests there (see
  [deploy-ansible.md](deploy-ansible.md#5-the-pipeline)).
- Once merged, the extension is published on PyPI; the next deploy
  installs it.

## Translations

The site is in English (default) and French. CKAN core has its own
French catalogue; each extension has `i18n/<domain>.pot` and
`i18n/fr/LC_MESSAGES/<domain>.po`/`.mo` - commit both the `.po` and the
`.mo`.

Mark new strings for translation: `toolkit._()` in Python,
`{{ _('...') }}` in templates, `_("...")` in CKAN JavaScript modules.

Extract and update, in the container:

```bash
docker compose exec ckan bash -lc '
  for ext in fair3r doi pages; do
    cd /plugins/ckanext-$ext
    python setup.py extract_messages
    python setup.py update_catalog -l fr
  done
'
```

Fill the empty `msgstr` in `i18n/fr/LC_MESSAGES/*.po` (and remove
`fuzzy` flags), then compile and restart:

```bash
docker compose exec ckan bash -lc '
  for ext in fair3r doi pages; do
    cd /plugins/ckanext-$ext
    python setup.py compile_catalog -l fr
  done
'
docker compose restart ckan
```

Strings used in JavaScript are only sent to the browser if they're in
the `.pot` file with a `.js` location.

## The FDF form schema

The metadata form is driven by `fdf_schema.json` in
[fair3r-fdf-schema](https://github.com/Phen-ICS/fair3r-fdf-schema), with
its translations in `i18n/<locale>.json` there (not Babel).

- By default, the schema is downloaded from GitHub at each start (and
  every night on the servers, by cron).
- To work on it, clone it anywhere and set its path in `.env`:

  ```ini
  FDF_SCHEMA_LOCAL_PATH=/home/you/src/fair3r-fdf-schema
  ```

  then `docker compose up -d` (a `restart` doesn't re-attach the mount).
  Schema edits are then read live, on the next page load.
- Translation tools, in the schema clone:

  ```bash
  python tools/i18n.py template --locale fr   # refresh keys after schema edits
  python tools/i18n.py check --locale fr      # check every key is translated
  ```

## Python version

The public `ckan/ckan-base:2.12.0` image ships Python 3.14, while the
servers' Ubuntu 24.04 package runs Python 3.12. To develop on the same
Python as production, build the base image yourself from
[ckan-docker-base](https://github.com/ckan/ckan-docker-base):

```bash
git clone https://github.com/ckan/ckan-docker-base.git
cd ckan-docker-base
docker build -f ckan-2.12/Dockerfile \
  --build-arg CKAN_REF=ckan-2.12.0 --build-arg PYTHON_VERSION=3.12 \
  -t my/ckan-base:2.12.0-py3.12 ckan-2.12
```

and point this stack at it in `.env`:

```ini
CKAN_BASE_IMAGE=my/ckan-base
CKAN_VERSION=2.12.0-py3.12
```

then `docker compose up -d --build`.

## Changing the deployment

- `ckan/config/ckan.ini.template` is used by both the Docker stack and the
  servers: a change there applies everywhere.
- A startup step added to `ckan/scripts/entrypoint.sh` (Docker) usually
  needs its equivalent in `deploy/ansible/roles/ckan_bootstrap` (servers)
  - see the mapping in [deploy/README.md](../deploy/README.md).
- Pinned third-party extensions and Python packages are in
  `ckan/requirements.txt`, also installed on the servers.
