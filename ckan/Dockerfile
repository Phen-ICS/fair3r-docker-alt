ARG CKAN_VERSION=2.12.0
FROM ckan/ckan-base:${CKAN_VERSION}

#Build args
ARG FAIR3R_CONTEXT=""


USER root

# Common packages
# g++/libpq-dev (build-essential + Postgres headers) are needed to compile
# psycopg2 and other C-extension Python deps. CKAN 2.11's base image kept
# these in its final stage, but CKAN 2.12's base image strips them down to
# libpq5 (runtime only) - install them ourselves rather than depend on that,
# so we don't need to track upstream's base-image internals.
RUN if command -v apt-get >/dev/null 2>&1; then \
      apt-get update && \
      apt-get install -y --no-install-recommends \
        bash \
        curl \
        g++ \
        gettext-base \
        git \
        libpq-dev \
        postgresql-client \
        supervisor && \
      rm -rf /var/lib/apt/lists/*; \
    elif command -v apk >/dev/null 2>&1; then \
      apk add --no-cache \
        bash \
        curl \
        g++ \
        gettext \
        git \
        postgresql-dev \
        postgresql-client \
        supervisor; \
    else \
      echo "Unsupported base image: no apt-get or apk found" >&2; \
      exit 1; \
    fi

COPY requirements.txt dev-requirements.txt /srv/app/
RUN pip install --no-cache-dir --no-deps -r /srv/app/requirements.txt


# WORKAROUND: CKAN 2.11+ build_js_translations() requires an i18n/ directory per enabled plugin; upstream sometimes omits it.
RUN python3 -c "import pathlib, ckanext.dsaudit; p = pathlib.Path(ckanext.dsaudit.__file__).parent / 'i18n'; p.mkdir(parents=True, exist_ok=True)"

# Dev-only extensions
RUN if [ "$FAIR3R_CONTEXT" = "DEV" ]; then \
      echo "Installing dev-only extensions..."; \
      pip install --no-cache-dir --no-deps -r /srv/app/dev-requirements.txt; \
    fi

# Copy configs & scripts
COPY config/ckan.ini.template /srv/app/config/ckan.ini.template
COPY supervisord.prod.conf /etc/supervisor/conf.d/ckan-supervisord-prod.conf
COPY supervisord.dev.conf /etc/supervisor/conf.d/ckan-supervisord-dev.conf
COPY scripts/entrypoint.sh /srv/app/scripts/entrypoint.sh
COPY scripts/create_sysadmin.sh /srv/app/scripts/create_sysadmin.sh

RUN chmod +x /srv/app/scripts/entrypoint.sh /srv/app/scripts/create_sysadmin.sh

ENTRYPOINT ["/srv/app/scripts/entrypoint.sh"]
