# Fair3R Deploy — Ansible deployment for `validation`, `integration`, and `production`

This directory provisions a Fair3R CKAN instance as a **native Ubuntu package
install** on one of three target VMs:

| Context        | Host                                    | Public URL (see `group_vars/*`, `ckan.site_url`)              |
|----------------|-----------------------------------------|--------------------------------------------------------------|
| `validation`   | `serv-ics-fair3r-d-01`                  | `https://validation.fair3r.fr` (DNS in front of reverse proxy) |
| `integration`  | `serv-ics-fair3r-t-01`                  | `https://fair3r.integration.igbmc.u-strasbg.fr` (DNS in front of reverse proxy) |
| `production`   | `serv-ics-fair3r-p-02`                  | `https://fair3r.fr` (see `group_vars/production.yml`) |

The **`dev`** context is not touched by this folder — developers keep running
`docker compose up -d --build` from the repo root. See the top-level
[`README.md`](../README.md) and the [CKAN 2.11 install-from-package
docs](https://docs.ckan.org/en/2.11/maintaining/installing/install-from-package.html)
for background.

## Layout

```
deploy/
├── ansible_deploy.py             # CLI wrapper -> ansible-playbook
├── ckanext_test.py               # CLI wrapper -> remote pytest on integration VM for our custom ckan extensions
├── nginx_validation.conf         # HTTP :80 to CKAN (see file header; TLS upstream)
├── nginx_integration.conf        # same pattern as validation for integration VM
├── nginx_production.conf         # same pattern + optional proxy_cache
└── ansible/
    ├── fair3r_deploy.yml         # Main playbook
    ├── inventory.ini             # Groups: validation, integration, production
    ├── requirements.yml          # Galaxy collections
    ├── group_vars/all.yml        # Non-secret defaults (paths, ports, names)
    └── roles/
        ├── system                # apt baseline, locales, timezone
        ├── postgres              # PostgreSQL + ckan/datastore roles and DBs
        ├── solr                  # Solr 9 + ckan core + CKAN schema
        ├── redis                 # redis-server on loopback
        ├── ckan_package          # python-ckan_2.11-noble_amd64.deb install
        ├── ckan_extensions       # pip-installs all CKAN extensions
        ├── ckan_config           # envsubst-renders /etc/ckan/default/ckan.ini
        ├── ckan_bootstrap        # port of entrypoint.sh steps 4-10
        ├── ckan_services         # systemd units ckan-web + ckan-worker
        ├── nginx                 # reverse proxy config + reload
        └── verification          # status_show smoke test + systemd checks
```

## Mapping of `entrypoint.sh` -> Ansible roles

| `entrypoint.sh` step                                            | Role / task                                                                         |
|-----------------------------------------------------------------|-------------------------------------------------------------------------------------|
| `wait_for_service` db/solr/redis                                | `postgres`, `solr`, `redis` (all started + enabled before `ckan_bootstrap`)         |
| `envsubst < ckan.ini.template > ckan.ini`                       | `ckan_config` (same template, same env vars)                                        |
| Create datastore roles + databases                              | `postgres` (`community.postgresql.postgresql_user` / `postgresql_db`)                |
| Create `ckan_test` / `datastore_test` databases                 | `postgres` (same)                                                                   |
| `ckan db init` / `ckan db upgrade`                              | `ckan_bootstrap` (decides from `information_schema.tables`)                          |
| `ckan datastore set-permissions \| psql`                        | `ckan_bootstrap` (exact same shell pipeline)                                        |
| Sysadmin create-or-setpass + `sysadmin add`                     | `ckan_bootstrap`                                                                    |
| Xloader API token rotation (`extract_jwt`)                      | `ckan_bootstrap` — ported 1:1 as `files/rotate_xloader_token.sh`                    |
| `ckan config-tool` for `fair3r.*` / `contact.mail_to` / `doi.*` / `pages.*` | `ckan_bootstrap`                                                         |
| `fair3r update-schema` (GitHub download; skipped in DEV Docker only when `FDF_SCHEMA_LOCAL_PATH` is mounted) | Daily cron in `ckan_extensions` (native VMs only) |
| `ckan doi initdb`, `ckan db upgrade -p pages`                   | `ckan_bootstrap`                                                                    |
| supervisord `ckan-web` + `xloader-worker`                       | `ckan_services` (systemd `ckan-web.service` + `ckan-worker.service`)                |

## Required GitLab CI/CD variables

All of the following must be set in **Settings → CI/CD → Variables** before the
corresponding `deploy_validation` / `deploy_integration` / `deploy_production` job can succeed. Every one of
them is a **secret**. Mask **GitLab** and **DataCite** tokens; never log them in jobs.

| Variable (one per context: `VALIDATION_`, `INTEGRATION_`, or `PRODUCTION_`) | Purpose                                                         |
|-----------------------------------------------------------------|-----------------------------------------------------------------|
| `*_CKAN_SESSION_SECRET`                                         | `beaker.session.secret`                                         |
| `*_CKAN_SECRET_KEY`                                             | Flask `SECRET_KEY`                                              |
| `*_CKAN_APP_INSTANCE_UUID`                                      | `app_instance_uuid`                                             |
| `*_CKAN_DB_PASSWORD`                                            | Password for the `ckan` Postgres role                           |
| `*_CKAN_DATASTORE_DB_PASSWORD`                                  | Password for the `ckan_datastore` (read-write) role             |
| `*_CKAN_DATASTORE_READONLY_PASSWORD`                            | Password for the `ckan_datastore_ro` role                       |
| `*_CKAN_BOOTSTRAP_SYSADMIN_PASSWORD`                            | Password of the bootstrap sysadmin user                         |
| `FAIR3R_EXTENSION_PYPI_TOKEN`                                   | Deploy token or PAT for the **GitLab Package Registry PyPI** of **ckanext-fair3r** (used as `__token__` password in the `--extra-index-url`). Shared across contexts in CI. |
| `PAGE_EXTENSION_PYPI_TOKEN`                                       | Same for **ckanext-pages**. Shared across contexts. |
| `DOI_EXTENSION_PYPI_TOKEN`                                      | Same for **ckanext** (DOI extension). Shared across contexts. |
| `PLOTLY_EXTENSION_PYPI_TOKEN`                                   | Same for **ckanext-plotly**. Shared across contexts. |
| `*_DOI_ACCOUNT_NAME`                                            | DataCite account name (e.g. `CNRS.IGBMC`)                       |
| `*_DOI_ACCOUNT_PASSWORD`                                        | DataCite account password                                       |
| `*_DOI_PREFIX`                                                  | DOI prefix (e.g. `10.83249`)                                    |

## Non-secret configuration (lives in `deploy/ansible/group_vars/`, committed)

These values used to be GitLab CI variables but are now tracked in git:

- **`group_vars/all.yml`** — values shared by all native-deploy contexts:
  - `ckan_bootstrap_sysadmin_name` (default `admin`)
  - `ckan_bootstrap_sysadmin_email` (default `admin@igbmc.u-strasbg.fr`)
  - `fair3r_enable_fdf_integration` (default `true`)
  - `gitlab_extensions_pypi_host`, `ckan_extensions_gitlab_pypi_project_ids` (GitLab **project ID** per pip package, keys must match `extension_pypi_tokens` in the playbook)
  - Infrastructure defaults (paths, ports, plugin list, Solr/Redis URLs, CKAN deb URL).
- **`group_vars/validation.yml`** — values loaded automatically for any host in `[validation]`:
  - `ckan_site_url: https://validation.fair3r.fr` (public hostname; `nginx_validation.conf` `server_name` must match)
  - `contact_mail`, `doi_publisher`, `doi_test_mode: "true"`, `doi_site_title`.

- **`group_vars/integration.yml`** — same pattern for `[integration]`:
  - `ckan_site_url: https://fair3r.integration.igbmc.u-strasbg.fr` (`nginx_integration.conf` `server_name` must match)
  - `doi_test_mode: "true"` (DataCite sandbox, like validation).

- **`group_vars/production.yml`** — same keys as `validation.yml`, with
  `ckan_site_url: https://fair3r.fr` and
  `doi_test_mode: "false"`.

Edit these files and commit; no CI variable change needed. After you change
`ckan_site_url` (or anything else in [app:main] that CKAN reads only at
startup), the deploy must **restart `ckan-web` and `ckan-worker`** so the live
process reloads `/etc/ckan/default/ckan.ini`. The `ckan_config` role notifies;
`ckan_services` flushes handlers so restarts occur before nginx/verification.
Without that restart, redirects and `/api/action/status_show` continue to expose
the previous `site_url`.

## How `deploy/ansible_deploy.py` forwards secrets

Exactly the same indirection as
`/opt/ics-standalone-app-template/deploy/ansible_deploy.py`: every per-context
CLI flag (e.g. `--ckan-db-password`) is translated into an Ansible variable
prefixed with the context name (e.g. `-e validation_ckan_db_password=…`). The
playbook's `pre_tasks` resolve the right one via `lookup('vars', context + '_…')`.

The GitLab runner is expected to have a Fair3R CI SSH key at
`/runner-ssh/id_rsa` that is authorised as `devics` on all target VMs, matching the
convention used by the ics-standalone-app-template pipeline.

## Running manually from a developer workstation

```bash
pip install ansible
ansible-galaxy collection install -r deploy/ansible/requirements.yml

python3 deploy/ansible_deploy.py \
  --env validation \
  --host serv-ics-fair3r-d-01 \
  --ckan-session-secret "$VALIDATION_CKAN_SESSION_SECRET" \
  --ckan-secret-key "$VALIDATION_CKAN_SECRET_KEY" \
  --ckan-app-instance-uuid "$VALIDATION_CKAN_APP_INSTANCE_UUID" \
  --ckan-db-password "$VALIDATION_CKAN_DB_PASSWORD" \
  --ckan-datastore-db-password "$VALIDATION_CKAN_DATASTORE_DB_PASSWORD" \
  --ckan-datastore-readonly-password "$VALIDATION_CKAN_DATASTORE_READONLY_PASSWORD" \
  --ckan-bootstrap-sysadmin-password "$VALIDATION_CKAN_BOOTSTRAP_SYSADMIN_PASSWORD" \
  --fair3r-extension-pypi-token "$FAIR3R_EXTENSION_PYPI_TOKEN" \
  --page-extension-pypi-token "$PAGE_EXTENSION_PYPI_TOKEN" \
  --doi-extension-pypi-token "$DOI_EXTENSION_PYPI_TOKEN" \
  --plotly-extension-pypi-token "$PLOTLY_EXTENSION_PYPI_TOKEN" \
  --doi-account-name "$VALIDATION_DOI_ACCOUNT_NAME" \
  --doi-account-password "$VALIDATION_DOI_ACCOUNT_PASSWORD" \
  --doi-prefix "$VALIDATION_DOI_PREFIX"
```

Use `--env integration` / `$INTEGRATION_*` for `serv-ics-fair3r-t-01`, or `--env production` /
`$PRODUCTION_*` for `serv-ics-fair3r-p-02` (secrets and group_vars load from the matching prefix / file).

(Site URL, contact mail, DOI publisher / test_mode / site_title are read from
`deploy/ansible/group_vars/<context>.yml` and no longer need to be passed on
the command line.)

Add `--check` for a dry-run (adds `--check --diff` to the underlying
`ansible-playbook` invocation).

## Integration test jobs (`deploy/ckanext_test.py`)

After `deploy_integration`, the `test:integration:*` jobs SSH to the same VM,
run each extension's pytest suite with the **test.ini shipped in the installed
package**, and copy the JUnit XML back to the runner. GitLab CI uses the
`.ckanext_test` anchor (mirroring `.deploy_via_ansible`): the anchor runs
`python3 deploy/ckanext_test.py`; each job supplies host secrets and
extension-specific variables (`CKAN_TESTS_MODULE`, report paths).

Example (pages — no DB/Solr env exports):

```bash
python3 deploy/ckanext_test.py \
  --host serv-ics-fair3r-t-01 \
  --ckan-db-password "$INTEGRATION_CKAN_DB_PASSWORD" \
  --ckan-datastore-db-password "$INTEGRATION_CKAN_DATASTORE_DB_PASSWORD" \
  --ckan-datastore-readonly-password "$INTEGRATION_CKAN_DATASTORE_READONLY_PASSWORD" \
  --tests-module ckanext.pages.tests \
  --remote-report /tmp/pages-report.xml \
  --local-report report-pages.xml
```

## Manual QA checklist

Run through these after a `deploy_validation`, `deploy_integration`, or `deploy_production` succeeds:

1. **SSH + sudo** — `ssh devics@<host> sudo -n true` returns 0.
2. **CKAN package** — `dpkg -l python-ckan` shows `2.11.*`.
3. **Solr core** — `curl -fsS http://127.0.0.1:8983/solr/ckan/admin/ping` returns `"status":"OK"`.
4. **Postgres** — `sudo -u postgres psql -l` lists `ckan`, `datastore`, `ckan_test`, `datastore_test`.
5. **systemd** — `systemctl is-active ckan-web ckan-worker nginx` all report `active`.
6. **status_show** — `curl -fsS https://<host>/api/3/action/status_show` returns `{"success": true, …}`; `result.ckan_version` is `2.11.5`; `result.extensions` includes `xloader`, `pdf_view`, `contact`, `dsaudit`, `fair3r`, `doi`, `pages`, `plotly_explorer`.
7. **Xloader token** — `sudo cat /var/lib/ckan/xloader.token` starts with `eyJ` and differs from the value captured before the deploy.
8. **Xloader round-trip** — upload a CSV resource through the UI; within a minute the resource's datastore tab should show the ingested rows.
9. **Admin login** — log in as the bootstrap sysadmin with the current `*_CKAN_BOOTSTRAP_SYSADMIN_PASSWORD`. The password must work on first deploy AND after a re-deploy (idempotency).
10. **Re-deploy** — re-run the same deploy job; no data is lost, `ckan db upgrade` is run instead of `db init`, and the xloader token file mtime changes.

## TLS

The nginx configs in `deploy/` are **HTTP-only on port 80** to CKAN
(`127.0.0.1:8080`). Public HTTPS (for example `https://validation.fair3r.fr`
with Let's Encrypt) is expected on an **upstream reverse proxy**; you do not
need certificates under `/etc/letsencrypt` on the VM for that. If you ever
terminate TLS on this host instead, add `listen 443 ssl` and certificate paths
here (or use certbot on the VM) and keep `X-Forwarded-Proto` in sync.
