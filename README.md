![CKAN](https://img.shields.io/badge/CKAN-2.12.0-orange)
![Python](https://img.shields.io/badge/Python-3.12-blue)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-14-blueviolet)
![Solr](https://img.shields.io/badge/Solr-9-orange)

# FAIR3R catalogue - deployment

Everything needed to run the **FAIR3R** research data catalogue: a
[CKAN](https://ckan.org) 2.12 site with the FAIR3R extensions - a
structured metadata form (FDF), DataCite DOIs, large files on Zenodo,
citation tracking, organization pages, charts - plus PostgreSQL, Solr,
Redis and nginx.

## Choose your path

| I want to... | Use | Guide |
|---|---|---|
| **Try it** on my own machine | Docker Compose, extensions from PyPI | [docs/quick-start.md](docs/quick-start.md#try-it) |
| **Work on the code** of an extension | Docker Compose, with my clones in `src_extensions/` | [docs/quick-start.md](docs/quick-start.md#work-on-the-code) |
| **Install it on servers** (integration, validation, production) | Ansible, from GitLab CI or by hand | [docs/deploy-ansible.md](docs/deploy-ansible.md) |

### Try it in 3 commands

With Docker and git installed:

```bash
git clone https://github.com/Phen-ICS/fair3r-docker-alt.git && cd fair3r-docker-alt
cp .env.example .env   # then set the administrator account and plugin list: docs/quick-start.md, step 2
docker compose up -d --build
```

Then open http://localhost:5000. Step-by-step instructions, the developer
setup and what to do if it doesn't start: [docs/quick-start.md](docs/quick-start.md).

## Documentation

| Guide | For |
|---|---|
| [Quick start](docs/quick-start.md) | Running the catalogue locally with Docker |
| [Deploying with Ansible](docs/deploy-ansible.md) | Installing on Ubuntu servers: requirements, CI variables, pipeline, manual run, checks |
| [Configuration](docs/configuration.md) | Every setting of `.env`, and the optional services (DataCite, Zenodo, email) |
| [Administration](docs/administration.md) | Users and administrators, services, useful commands, common problems |
| [Development](docs/development.md) | Working on the extensions, tests, translations, the FDF form schema |
| [deploy/README.md](deploy/README.md) | Technical reference of the Ansible project |

## What's in this repository

| Path | Contents |
|---|---|
| `docker-compose.yml`, `docker-compose.override.yml` | The Docker stack; the override adds the development settings |
| `ckan/` | CKAN image (`Dockerfile`), startup script, `ckan.ini` template, pinned requirements |
| `nginx/` | nginx image for the Docker stack |
| `deploy/` | Ansible deployment for the servers, and its CI helpers |
| `.gitlab-ci.yml` | Pipeline: lint, deploy to integration and test, deploy to validation and production |
| `src_extensions/` | Your clones of the extensions you work on (not part of this repository); they replace the PyPI releases in DEV |

## The FAIR3R extensions

Separate repositories, published on PyPI and on
[GitHub](https://github.com/Phen-ICS):

| Extension | Adds |
|---|---|
| [ckanext-fair3r](https://github.com/Phen-ICS/ckanext-fair3r) | The FDF metadata form, completeness score, DCAT / Croissant / schema.org metadata, upload form, "Publish" button |
| [ckanext-doi](https://github.com/Phen-ICS/ckanext-doi) | DataCite DOIs for public datasets |
| [ckanext-zenodo](https://github.com/Phen-ICS/ckanext-zenodo) | Large or non-tabular files stored and published on Zenodo |
| [ckanext-citations](https://github.com/Phen-ICS/ckanext-citations) | Works citing a dataset, disruption index, S-index |
| [ckanext-pages](https://github.com/Phen-ICS/ckanext-pages) | Site and organization pages |
| [ckanext-plotly](https://github.com/Phen-ICS/ckanext-plotly) | Chart view for tabular data |

The form itself is defined in
[fair3r-fdf-schema](https://github.com/Phen-ICS/fair3r-fdf-schema).

## License

See [LICENSE](LICENSE).
