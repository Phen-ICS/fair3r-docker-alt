# deploy/ - Ansible deployment, technical reference

How to deploy (requirements, CI variables, pipeline, manual run, checks):
[docs/deploy-ansible.md](../docs/deploy-ansible.md). This page describes
how the deployment is built.

The Ansible project installs a FAIR3R CKAN site as a **native package
install** on an Ubuntu 24.04 VM, for the `integration`, `validation` and
`production` environments. Local development uses the Docker stack at
the repository root instead. Nothing in this repository names a real
host, domain or address: they all come from GitLab CI variables at
deploy time.

## Layout

```
deploy/
├── ansible_deploy.py        # CLI wrapper -> ansible-playbook (secrets as CLI flags)
├── ckanext_test.py          # Runs an extension's pytest suite on the integration VM
├── nginx_integration.conf   # nginx site per environment: HTTP :80 -> CKAN 127.0.0.1:8080
├── nginx_validation.conf
├── nginx_production.conf
└── ansible/
    ├── fair3r_deploy.yml    # Main playbook (target host added at runtime, no inventory file)
    ├── requirements.yml     # Galaxy collections
    ├── group_vars/          # Non-identifying settings: all.yml + one file per environment
    └── roles/               # system, postgres, solr, redis, ckan_package, ckan_extensions,
                             # ckan_config, ckan_bootstrap, ckan_services, nginx, verification
```

Role by role: [ansible/README.md](ansible/README.md).

## Docker startup vs Ansible roles

The VM goes through the same steps as the Docker container's
`ckan/scripts/entrypoint.sh`; a change to one usually needs the same
change in the other.

| `entrypoint.sh` step | Ansible role |
|---|---|
| Wait for PostgreSQL, Solr, Redis | `postgres`, `solr`, `redis` (installed and started first) |
| `envsubst < ckan.ini.template > ckan.ini` | `ckan_config` (same template, same variables) |
| DataStore users and databases, test databases | `postgres` |
| `ckan db init` or `ckan db upgrade` | `ckan_bootstrap` (decided from `information_schema`) |
| `ckan datastore set-permissions \| psql` | `ckan_bootstrap` (same pipeline) |
| Administrator: create or reset password, make sysadmin | `ckan_bootstrap` |
| Harvest account (optional) | `ckan_bootstrap` |
| xloader API token rotation | `ckan_bootstrap` (`files/rotate_xloader_token.sh`) |
| `ckan config-tool` for fair3r, contact, doi, pages, zenodo | `ckan_bootstrap` |
| `fair3r update-schema` | `ckan_bootstrap` (now and as a daily cron) |
| `db upgrade -p doi / pages / better_stats / citations / zenodo` | `ckan_bootstrap` (zenodo only if `zenodo_enabled`) |
| Extensions from `src_extensions/` (DEV) or a registry | `ckan_extensions`, from public PyPI |
| supervisord `ckan-web` + worker | `ckan_services`: systemd `ckan-web.service`, `ckan-worker.service` |

## How settings reach Ansible

- **Secrets and per-environment accounts** (`ansible_deploy.py`'s
  `CONTEXT_SCOPED`): passed as CLI flags, forwarded as Ansible variables
  prefixed with the environment (`--ckan-db-password` with
  `--env validation` becomes `-e validation_ckan_db_password=...`). The
  playbook's `pre_tasks` pick the right one with
  `lookup('vars', context + '_...')` into `env_config`, and assert the
  required ones are present.
- **Identifying values** (site URL, contact address, DOI publisher and
  title, SMTP identity, administrator email; `PLAIN_PASSTHROUGH`): plain
  `-e` variables, from GitLab's environment-scoped variables.
- **Everything else**: `group_vars/all.yml` and `group_vars/<env>.yml`,
  committed.

The target host isn't declared anywhere: the playbook's first play adds
`--host` to the group named after `--env` at runtime, which is also what
makes `group_vars/<env>.yml` apply.

In CI, the runner mounts the deploy SSH key at `/mnt/ssh/` (copied to
`~/.ssh/` by the `.ssh_setup` anchor); the playbook connects as
`devics`.

## Integration tests (`ckanext_test.py`)

After `deploy_integration`, each `test:integration:<extension>` job runs:

```bash
python3 deploy/ckanext_test.py \
  --host <integration host> \
  --ckan-db-password ... \
  --ckan-datastore-db-password ... \
  --ckan-datastore-readonly-password ... \
  --tests-module ckanext.pages.tests \
  --remote-report /tmp/pages-report.xml \
  --local-report report-pages.xml
```

It SSHes to the VM, runs pytest with the `test.ini` shipped in the
installed package (against the `ckan_test` and `datastore_test`
databases), and copies the JUnit report back to the job.

When an extension's merge request triggers the pipeline, its
`fetch:preview:<extension>` job downloads that merge request's wheel, and
`ckan_extensions` installs it instead of the PyPI release.

## Checks after a deploy

The `verification` role checks that `status_show` answers and that the
services are active. By hand, on the VM:

1. `systemctl is-active ckan-web ckan-worker nginx` - all `active`.
2. `curl -fsS http://127.0.0.1:8983/solr/ckan/admin/ping` - `"status":"OK"`.
3. `sudo -u postgres psql -l` - `ckan`, `datastore`, `ckan_test`, `datastore_test`.
4. `curl -fsS <site>/api/3/action/status_show` - `ckan_version` 2.12.0;
   `extensions` include `xloader`, `pdf_view`, `contact`, `dsaudit`,
   `better_stats`, `fair3r`, `doi`, `pages`, `plotly_explorer`,
   `citations` (and `zenodo` where enabled).
5. `sudo cat /var/lib/ckan/xloader.token` - a JWT (`eyJ...`), changed by
   the deploy.
6. A CSV added through the web interface shows its data within a minute.
7. The administrator can log in with the current password, also after a
   second deploy (which must keep all data).

## TLS

The nginx sites in `deploy/` serve plain HTTP on port 80; HTTPS is
expected on a reverse proxy in front of the VM. To end TLS on the VM
instead, add `listen 443 ssl` and the certificate paths to
`nginx_<env>.conf` (or use certbot there), and keep `X-Forwarded-Proto`
consistent.
