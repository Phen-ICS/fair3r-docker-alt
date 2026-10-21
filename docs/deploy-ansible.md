# Deploying on servers with Ansible

The `integration`, `validation` and `production` environments run on
**Ubuntu 24.04 (Noble) virtual machines, without Docker**: CKAN 2.12 is
installed from its official `.deb` package, with PostgreSQL, Solr 9,
Redis and nginx, all set up by the Ansible playbook in `deploy/ansible/`.
Normally the GitLab pipeline runs it; it can also be run by hand.

The resulting site is the same as the Docker stack: same CKAN version,
same extensions, same `ckan.ini` (rendered from the same template), same
startup steps - with two systemd services, `ckan-web` and `ckan-worker`,
instead of supervisord.

## 1. What you need

**A virtual machine per environment**
- Ubuntu 24.04, reachable over SSH.
- A user **`devics`** with passwordless `sudo`, accepting the deploy SSH
  key. (The playbook connects as `devics` - `remote_user` in
  `deploy/ansible/fair3r_deploy.yml`.)
- Enough disk for the data, plus - if ckanext-zenodo is enabled - the
  largest file accepted for Zenodo (10 GB by default) and a 5 GB margin:
  each upload is written to a temporary file before being sent on.
- Outbound internet access (Ubuntu packages, the CKAN package, PyPI,
  GitHub, and DataCite/Zenodo at runtime).

**A public address**
- A DNS name for the site, and an HTTPS reverse proxy in front of the VM
  (the VM's nginx listens on plain HTTP, port 80, and forwards to CKAN on
  `127.0.0.1:8080`). To end TLS on the VM itself instead, see
  [deploy/README.md](../deploy/README.md#tls).

**External accounts**
- DataCite: a test account for integration/validation, a production
  account for production.
- SMTP server for the site's emails.
- Zenodo (only where ckanext-zenodo is enabled): a token on
  sandbox.zenodo.org and/or zenodo.org, and a community.

**For the pipeline**
- A GitLab runner tagged `ics-docker`, with the deploy SSH key mounted at
  `/mnt/ssh/` (`id_rsa`, `known_hosts`).
- The CI/CD variables below.

## 2. What the playbook does

In order, on the target VM (roles in `deploy/ansible/roles/`):

| Step | Role |
|---|---|
| Base packages, locales, time zone, Java | `system` |
| PostgreSQL, CKAN and DataStore users and databases (and the test databases) | `postgres` |
| Solr 9 with the CKAN core and schema | `solr` |
| Redis on localhost | `redis` |
| CKAN 2.12 `.deb` package | `ckan_package` |
| Extensions from public PyPI: FAIR3R, DOI, pages, plotly, citations, Zenodo (if enabled), plus the pinned third-party ones from `ckan/requirements.txt` | `ckan_extensions` |
| `/etc/ckan/default/ckan.ini` from `ckan/config/ckan.ini.template` | `ckan_config` |
| Database init or upgrade, DataStore permissions, administrator account, xloader token, extension settings and migrations, cron jobs | `ckan_bootstrap` |
| systemd services `ckan-web` and `ckan-worker` | `ckan_services` |
| nginx site from `deploy/nginx_<environment>.conf`: 20M body limit, 10G for `/zenodo/upload/` | `nginx` |
| Check that CKAN answers and the services are running | `verification` |

It's safe to run again: existing data is kept (`db upgrade`, not
`db init`), the administrator's password is re-synced, the xloader token
is renewed.

Cron jobs installed: FDF form schema update (daily, 00:00), citation
refresh (Sundays, 03:00), and Zenodo publish retries (every 30 minutes,
only where Zenodo is enabled).

## 3. GitLab CI/CD variables

Settings -> CI/CD -> Variables. Mask every secret. Variables marked
"per environment" exist once per environment, prefixed `INTEGRATION_`,
`VALIDATION_` or `PRODUCTION_`.

### Secrets, per environment

| Variable | Use |
|---|---|
| `*_CKAN_SESSION_SECRET`, `*_CKAN_SECRET_KEY` | Session signing keys |
| `*_CKAN_APP_INSTANCE_UUID` | Instance identifier (a UUID) |
| `*_CKAN_DB_PASSWORD` | PostgreSQL `ckan` user |
| `*_CKAN_DATASTORE_DB_PASSWORD`, `*_CKAN_DATASTORE_READONLY_PASSWORD` | DataStore users |
| `*_CKAN_BOOTSTRAP_SYSADMIN_PASSWORD` | Administrator account |
| `*_CKAN_HARVEST_USER_PASSWORD` | Optional harvest account |

### DataCite and Zenodo accounts

| Variable | Use |
|---|---|
| `SANDBOX_DOI_ACCOUNT_NAME`, `SANDBOX_DOI_ACCOUNT_PASSWORD`, `SANDBOX_DOI_PREFIX` | DataCite test account (integration and validation) |
| `PRODUCTION_DOI_ACCOUNT_NAME`, `PRODUCTION_DOI_ACCOUNT_PASSWORD`, `PRODUCTION_DOI_PREFIX` | DataCite production account |
| `SANDBOX_ZENODO_ACCESS_TOKEN` | Zenodo sandbox token (not protected: merge-request pipelines deploy integration) |
| `PRODUCTION_ZENODO_ACCESS_TOKEN` | zenodo.org token - protected, environment scope `production` |
| `ZENODO_COMMUNITY_IDENTIFIER` | Zenodo community (same name on both sites) |

### Values that identify the organization, environment-scoped

Not secret, but kept out of the repository (which is published): one
variable per name, with GitLab's **environment scope** set to
`integration`, `validation` or `production`.

| Variable | Use |
|---|---|
| `SSH_HOST` | Host name or IP of the VM |
| `CKAN_SITE_URL` | Public URL of the site |
| `CONTACT_MAIL` | Address of the contact form |
| `DOI_PUBLISHER`, `DOI_SITE_TITLE` | Publisher and site name in DOI metadata |

### Shared by all environments

| Variable | Use |
|---|---|
| `CKAN_EMAIL_SMTP_SERVER`, `CKAN_EMAIL_SMTP_USER`, `CKAN_EMAIL_SMTP_PASSWORD`, `CKAN_EMAIL_SMTP_MAIL_FROM`, `CKAN_EMAIL_SMTP_REPLY_TO` | SMTP |
| `CKAN_BOOTSTRAP_SYSADMIN_EMAIL` | Administrator's email |

## 4. Settings kept in the repository

`deploy/ansible/group_vars/` - nothing here identifies the organization:

| File | Holds |
|---|---|
| `all.yml` | Defaults for every environment: CKAN version and package URL, plugin list, paths and ports, administrator name, `ckan_max_resource_size` (MB, 10 by default), `zenodo_enabled: false` |
| `integration.yml` | DataCite test mode, Zenodo enabled on the sandbox |
| `validation.yml` | DataCite test mode, 20 MB upload limit |
| `production.yml` | Live DataCite, 20 MB upload limit, Zenodo set to zenodo.org (still disabled) |

To change one of these, edit the file, commit and deploy. To enable
ckanext-zenodo on an environment: `zenodo_enabled: true` in its file,
with its Zenodo token variable set.

## 5. The pipeline

| Job | When | Does |
|---|---|---|
| `ansible_lint` | Every pipeline | Checks the playbook |
| `deploy_integration` | Every pipeline, automatically | Deploys integration |
| `test:integration:*` | After `deploy_integration` | Runs each extension's test suite on the integration VM (`deploy/ckanext_test.py`) |
| `deploy_validation` | **Manual** | Deploys validation |
| `deploy_production` | **Manual**, once validation was deployed in the same pipeline | Deploys production |

A merge request on one of the extensions triggers this pipeline with the
extension's own build (`fetch:preview:<extension>` jobs): integration is
deployed and tested with that merge request's code instead of the latest
PyPI release.

## 6. Running the playbook by hand

From a machine with SSH access to the VM as `devics`:

```bash
pip install ansible
cd fair3r-docker-alt

python3 deploy/ansible_deploy.py \
  --env validation \
  --host validation.example.org \
  --ckan-session-secret '...' \
  --ckan-secret-key '...' \
  --ckan-app-instance-uuid '...' \
  --ckan-db-password '...' \
  --ckan-datastore-db-password '...' \
  --ckan-datastore-readonly-password '...' \
  --ckan-bootstrap-sysadmin-password '...' \
  --ckan-bootstrap-sysadmin-email admin@example.org \
  --doi-account-name '...' --doi-account-password '...' --doi-prefix 10.12345 \
  --ckan-site-url https://validation.example.org \
  --contact-mail contact@example.org \
  --doi-publisher 'Your organization' --doi-site-title 'Your catalogue' \
  --ckan-email-smtp-server smtp.example.org:587 \
  --ckan-email-smtp-user no-reply@example.org \
  --ckan-email-smtp-password '...' \
  --ckan-email-smtp-mail-from no-reply@example.org \
  --ckan-email-smtp-reply-to no-reply@example.org
```

- `--env` is `integration`, `validation` or `production`; it selects
  `group_vars/<env>.yml`.
- Add `--zenodo-access-token '...' --zenodo-community-identifier fair3r`
  where Zenodo is enabled; `--ckan-harvest-user-password` if you use the
  harvest account.
- `--check` runs a dry run (`ansible-playbook --check --diff`); `-v` to
  `-vvvv` for more output.
- The script installs the Ansible collections it needs
  (`deploy/ansible/requirements.yml`) before running.

## 7. After a deploy

1. The `verification` step already checked that CKAN answers and the
   services run. Open `CKAN_SITE_URL`: the home page loads, and
   `<site>/api/3/action/status_show` shows CKAN 2.12 and the extensions.
2. Log in as the administrator.
3. Add a CSV file to a test dataset: its data appear in the data viewer
   within a minute (xloader and the worker work).
4. Where Zenodo is enabled:
   `sudo -u ckan /usr/lib/ckan/default/bin/ckan -c /etc/ckan/default/ckan.ini zenodo check`.
5. Run the deploy again: nothing is lost, the site comes back the same.

On the VM:

```bash
systemctl status ckan-web ckan-worker nginx
journalctl -u ckan-web -f
sudo -u ckan /usr/lib/ckan/default/bin/ckan -c /etc/ckan/default/ckan.ini <command>
```

More technical detail (playbook layout, how each startup step maps to a
role, how secrets reach Ansible): [deploy/README.md](../deploy/README.md).
