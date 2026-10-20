# Administration

Everyday tasks on a running site. Commands are given for the Docker stack
and for a server deployed with Ansible.

| | Docker stack | Server (as an admin user on the VM) |
|---|---|---|
| Run a CKAN command | `docker compose exec ckan ckan -c /srv/app/ckan.ini <command>` | `sudo -u ckan /usr/lib/ckan/default/bin/ckan -c /etc/ckan/default/ckan.ini <command>` |

Below, `ckan <command>` stands for the line of your environment.

## Users

```bash
ckan user add jdoe email=jdoe@example.org password='a-long-password' fullname="Jane Doe"
ckan user list
ckan user show jdoe
ckan user setpass jdoe
ckan user remove jdoe
```

Passwords need at least 8 characters; leave `password=` out to be asked
for it.

Administrators (sysadmins) can do everything on the site:

```bash
ckan sysadmin add jdoe
ckan sysadmin list
ckan sysadmin remove jdoe
```

The administrator account from `CKAN_BOOTSTRAP_SYSADMIN_*` (Docker) or
`*_CKAN_BOOTSTRAP_SYSADMIN_PASSWORD` (servers) is created at startup or
deploy, and its password is reset to that value each time: change it
there, not through the web interface.

## Services

| Task | Docker stack | Server |
|---|---|---|
| State | `docker compose ps` | `systemctl status ckan-web ckan-worker nginx` |
| CKAN logs | `docker compose logs -f ckan` | `journalctl -u ckan-web -f` |
| Background jobs logs | `docker compose logs -f ckan` | `journalctl -u ckan-worker -f` |
| Restart CKAN | `docker compose restart ckan` | `sudo systemctl restart ckan-web ckan-worker` |

The background worker runs the CSV loader (xloader) and the extensions'
deferred jobs (Zenodo publishing and file deletions). If it stops,
uploads still work but CSV data and Zenodo records don't appear.

## Useful commands

| Task | Command |
|---|---|
| Rebuild the search index (after a database restore, or if search results look wrong) | `ckan search-index rebuild` |
| List background jobs waiting | `ckan jobs list` |
| Re-load a CSV file into the data viewer | `ckan xloader submit <dataset-name>` |
| Update the FDF form schema now | `ckan fair3r update-schema` |
| Refresh citations now | `ckan citations refresh` |
| Check the Zenodo setup | `ckan zenodo check` |
| Retry failed Zenodo publishes | `ckan zenodo retry-pending` |

## Data

- **Docker**: the database, search index, Redis and uploaded files are in
  Docker volumes (`db_data`, `solr_data`, `redis_data`, `ckan_storage`).
  They survive `docker compose down` and are deleted by
  `docker compose down -v`.
- **Servers**: PostgreSQL databases `ckan` and `datastore`, uploaded
  files under `/var/lib/ckan`.

The search index can always be rebuilt from the database
(`ckan search-index rebuild`); the databases and uploaded files can't be
rebuilt from anything else.

## Common problems

| Symptom | Look at |
|---|---|
| Site down after a configuration change | CKAN logs: a typo in a setting, or a plugin in the list that isn't installed |
| CSV files without data in the viewer | Background worker running? Administrator account configured (xloader uses it)? `ckan jobs list` |
| Making a dataset public fails with a DataCite error | DataCite account settings; in a test setup without an account, disable the `doi` plugin |
| A published dataset has no DOI | CKAN logs (DOIs are minted while the dataset is saved); DataCite account and prefix |
| Zenodo files stay "being archived" | `ckan zenodo check`, worker logs, then `ckan zenodo retry-pending` |
| Search doesn't find a dataset that exists | `ckan search-index rebuild` |
