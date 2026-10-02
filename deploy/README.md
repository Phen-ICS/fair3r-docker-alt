# Fair3R Deploy — Ansible deployment for `validation`, `integration`, and `production`

This directory provisions a Fair3R CKAN instance as a **native Ubuntu package
install** on one of three target VMs: `validation`, `integration`, and
`production`. This repo never names a specific organization's hosts or
domains - every host, site URL and contact address is supplied at deploy
time via GitLab CI/CD variables (see "Required GitLab CI/CD variables"
below), so the same pipeline works for any deployment of Fair3R CKAN.

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
    ├── fair3r_deploy.yml         # Main playbook (dynamic add_host, no inventory file)
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
| `ckan db upgrade -p doi`, `ckan db upgrade -p pages`            | `ckan_bootstrap`                                                                    |
| supervisord `ckan-web` + `xloader-worker`                       | `ckan_services` (systemd `ckan-web.service` + `ckan-worker.service`)                |

## Required GitLab CI/CD variables

All of the following must be set in **Settings → CI/CD → Variables** before the
corresponding `deploy_validation` / `deploy_integration` / `deploy_production` job can succeed.

### Per-context secrets (one value per environment)

Mask these; never log them in jobs. Set one variable per context, prefixed
`VALIDATION_`, `INTEGRATION_`, or `PRODUCTION_`:

| Variable                                                         | Purpose                                                         |
|-------------------------------------------------------------------|-----------------------------------------------------------------|
| `*_CKAN_SESSION_SECRET`                                         | `beaker.session.secret`                                         |
| `*_CKAN_SECRET_KEY`                                             | Flask `SECRET_KEY`                                              |
| `*_CKAN_APP_INSTANCE_UUID`                                      | `app_instance_uuid`                                             |
| `*_CKAN_DB_PASSWORD`                                            | Password for the `ckan` Postgres role                           |
| `*_CKAN_DATASTORE_DB_PASSWORD`                                  | Password for the `ckan_datastore` (read-write) role             |
| `*_CKAN_DATASTORE_READONLY_PASSWORD`                            | Password for the `ckan_datastore_ro` role                       |
| `*_CKAN_BOOTSTRAP_SYSADMIN_PASSWORD`                            | Password of the bootstrap sysadmin user                         |
| `*_DOI_ACCOUNT_NAME`                                            | DataCite account name                                           |
| `*_DOI_ACCOUNT_PASSWORD`                                        | DataCite account password                                       |
| `*_DOI_PREFIX`                                                  | DOI prefix (e.g. `10.12345`)                                    |

### Per-context identifying values (not secret, but still environment-specific)

Not masked, but set as **environment-scoped** project variables (Settings →
CI/CD → Variables → "Environment scope" = `validation` / `integration` /
`production`) so the *same* variable name resolves to a different value per
deploy job - this is also how each job reaches the right host without this
repo ever naming it:

| Variable          | Purpose                                                              |
|-------------------|-----------------------------------------------------------------------|
| `SSH_HOST`        | Hostname/IP Ansible deploys to and `ckanext_test.py` SSHes into      |
| `CKAN_SITE_URL`   | `ckan.site_url`; also used as the GitLab Environment's URL           |
| `CONTACT_MAIL`    | Address shown on `contact.mail_to` (ckanext-contact)                 |
| `DOI_PUBLISHER`   | `datacite.publisher` default                                         |
| `DOI_SITE_TITLE`  | DataCite resource title prefix                                       |

### Shared secrets and identifying values (same across every context)

| Variable                        | Purpose                                             |
|----------------------------------|------------------------------------------------------|
| `CKAN_EMAIL_SMTP_PASSWORD`      | SMTP auth password (secret, mask it)                 |
| `CKAN_EMAIL_SMTP_SERVER`        | `ckan.smtp.server`, e.g. `smtp.example.org:587`      |
| `CKAN_EMAIL_SMTP_USER`          | `ckan.smtp.user`                                      |
| `CKAN_EMAIL_SMTP_MAIL_FROM`     | `ckan.smtp.mail_from`                                 |
| `CKAN_EMAIL_SMTP_REPLY_TO`      | `ckan.smtp.reply_to`                                  |
| `CKAN_BOOTSTRAP_SYSADMIN_EMAIL` | Email of the bootstrap sysadmin user                  |
| `SANDBOX_DOI_ACCOUNT_NAME` / `SANDBOX_DOI_ACCOUNT_PASSWORD` / `SANDBOX_DOI_PREFIX` | DataCite **sandbox** credentials, shared by `integration` and `validation` (production uses its own `PRODUCTION_DOI_*` instead) |

## Non-identifying configuration (lives in `deploy/ansible/group_vars/`, committed)

Everything else non-secret is tracked in git, since none of it identifies a
specific organization:

- **`group_vars/all.yml`** — shared by every context: `ckan_bootstrap_sysadmin_name`
  (default `admin`), `fair3r_enable_fdf_integration`, `ckan_max_resource_size`
  (default `"10"` MB), plus infrastructure defaults (paths, ports, plugin
  list, Solr/Redis URLs, CKAN deb URL, non-identifying SMTP flags).
- **`group_vars/validation.yml`** — `ckan_max_resource_size: "20"` (explicit
  override, distinct from the `all.yml` default, to make it easy to confirm a
  deploy actually picked it up), `doi_test_mode: "true"`.
- **`group_vars/integration.yml`** — `doi_test_mode: "true"` (DataCite
  sandbox, like validation); `ckan_max_resource_size` not overridden, inherits
  the `all.yml` default.
- **`group_vars/production.yml`** — `doi_test_mode: "false"` (live DataCite
  API), `ckan_max_resource_size: "100"`.

Edit these files and commit for non-identifying changes; no CI variable
change needed. But after changing `ckan_site_url` (whether via a new
`CKAN_SITE_URL` CI variable or anything else in `[app:main]` that CKAN reads
only at startup), the deploy must **restart `ckan-web` and `ckan-worker`** so
the live process reloads `/etc/ckan/default/ckan.ini`. The `ckan_config` role
notifies; `ckan_services` flushes handlers so restarts occur before
nginx/verification. Without that restart, redirects and
`/api/action/status_show` continue to expose the previous `site_url`.

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

`--host` doesn't need to be declared anywhere first: `ansible_deploy.py` runs
`ansible-playbook` with no `-i` at all, and the playbook's own first play
(`add_host`) registers `--host` into its `--env` context's group at runtime -
creating that group on the fly - which is also what makes
`group_vars/<context>.yml` apply to it. No organization's real hostname is
committed anywhere in this repo.

```bash
pip install ansible
ansible-galaxy collection install -r deploy/ansible/requirements.yml

python3 deploy/ansible_deploy.py \
  --env validation \
  --host your-validation-host.example.org \
  --ckan-session-secret "$VALIDATION_CKAN_SESSION_SECRET" \
  --ckan-secret-key "$VALIDATION_CKAN_SECRET_KEY" \
  --ckan-app-instance-uuid "$VALIDATION_CKAN_APP_INSTANCE_UUID" \
  --ckan-db-password "$VALIDATION_CKAN_DB_PASSWORD" \
  --ckan-datastore-db-password "$VALIDATION_CKAN_DATASTORE_DB_PASSWORD" \
  --ckan-datastore-readonly-password "$VALIDATION_CKAN_DATASTORE_READONLY_PASSWORD" \
  --ckan-bootstrap-sysadmin-password "$VALIDATION_CKAN_BOOTSTRAP_SYSADMIN_PASSWORD" \
  --doi-account-name "$VALIDATION_DOI_ACCOUNT_NAME" \
  --doi-account-password "$VALIDATION_DOI_ACCOUNT_PASSWORD" \
  --doi-prefix "$VALIDATION_DOI_PREFIX" \
  --ckan-site-url "https://validation.your-domain.example.org" \
  --contact-mail "admin@example.org" \
  --doi-publisher "Your Organization" \
  --doi-site-title "Your Portal" \
  --ckan-email-smtp-password "$CKAN_EMAIL_SMTP_PASSWORD" \
  --ckan-email-smtp-server "smtp.example.org:587" \
  --ckan-email-smtp-user "no-reply@example.org" \
  --ckan-email-smtp-mail-from "no-reply@example.org" \
  --ckan-email-smtp-reply-to "no-reply@example.org" \
  --ckan-bootstrap-sysadmin-email "admin@example.org"
```

Use `--env integration` / `$INTEGRATION_*`, or `--env production` / `$PRODUCTION_*`
for the other contexts (secrets and group_vars load from the matching prefix
/ file); swap `--host` and the identifying flags above for that environment's
real values.

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
  --host your-integration-host.example.org \
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
(`127.0.0.1:8080`). Public HTTPS (e.g. with Let's Encrypt) is expected on an
**upstream reverse proxy**; you do not
need certificates under `/etc/letsencrypt` on the VM for that. If you ever
terminate TLS on this host instead, add `listen 443 ssl` and certificate paths
here (or use certbot on the VM) and keep `X-Forwarded-Proto` in sync.
