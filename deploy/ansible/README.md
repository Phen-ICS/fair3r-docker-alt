# Ansible playbook — Fair3R CKAN native deploy

Modular Ansible project that installs a Fair3R CKAN instance from the
official `python-ckan_2.11-noble_amd64.deb` package on a single Ubuntu
Noble VM. See [`../README.md`](../README.md) for required GitLab CI
variables and the end-to-end deploy flow.

## Files

- `fair3r_deploy.yml` — main playbook. Resolves per-context secrets via
  `lookup('vars', context + '_…')` and applies each role in order.
- `inventory.ini` — `[validation]`, `[integration]`, and `[production]` groups.
- `requirements.yml` — Galaxy collections (`community.postgresql`,
  `community.general`, `ansible.posix`).
- `group_vars/all.yml` — non-secret defaults (paths, ports, plugin list).
- `roles/*/tasks/main.yml` — one responsibility per role:

| Role              | Responsibility                                                      |
|-------------------|---------------------------------------------------------------------|
| `system`          | apt baseline, locales, timezone, Java for Solr                       |
| `postgres`        | PostgreSQL + roles (`ckan`, `ckan_datastore`, `ckan_datastore_ro`) + databases (`ckan`, `datastore`, `ckan_test`, `datastore_test`) |
| `solr`            | Solr 9, `ckan` core, CKAN 2.11 schema                                |
| `redis`           | `redis-server` bound to loopback                                    |
| `ckan_package`    | Download + `dpkg -i` the CKAN deb, disable apache2, neutralise supervisord configs |
| `ckan_extensions` | pip-install into `/usr/lib/ckan/default`: xloader, pdfview, contact, dsaudit, + Our curstom ext from **GitLab Package Registry PyPI** (see `group_vars/all.yml` + CI token) |
| `ckan_config`     | envsubst-render `/etc/ckan/default/ckan.ini` from the repo's `ckan/config/ckan.ini.template` |
| `ckan_bootstrap`  | Port of `ckan/scripts/entrypoint.sh`: db init/upgrade, datastore permissions, sysadmin bootstrap, Xloader token rotation, extension config-tool settings, DOI + pages migrations |
| `ckan_services`   | Install systemd units `ckan-web.service` and `ckan-worker.service`, enable + start |
| `nginx`           | Install `fair3r` site, templated from `deploy/nginx_{context}.conf` (`server_name` comes from `CKAN_SITE_URL`), remove default/ckan sites, reload |
| `verification`    | Smoke test: `/api/3/action/status_show` returns 200 and success, systemd units active |

## Idempotency

- `ckan_package` downloads the deb from `ckan_deb_url`, reads its upstream `Version`
  with `dpkg-deb`, and compares it to `ckan_version` in `group_vars/all.yml`. If
  `python-ckan` is already installed and those differ (for example the URL now
  ships a newer patch than your pin), the role **does not** reinstall the package
  and the play continues. A host with no `python-ckan` must have a deb matching
  `ckan_version`, or the play fails with a clear assert.
- `ckan db init` only runs if the schema is missing; otherwise `ckan db upgrade`.
- Sysadmin creation only runs if the user row is missing; the password is
  always synced to the current `*_CKAN_BOOTSTRAP_SYSADMIN_PASSWORD` secret.
- The Xloader API token is **always** deleted and recreated; the new JWT is
  written to `/var/lib/ckan/xloader.token` and injected into `ckan.ini`
  via `ckan config-tool`.
- All `community.postgresql.*` tasks use `state: present`; re-running the
  playbook with unchanged inputs produces no changes.
