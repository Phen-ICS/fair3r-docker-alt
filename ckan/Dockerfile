ARG CKAN_VERSION=2.10.7
FROM ckan/ckan-base:${CKAN_VERSION}

# Build args
ARG FAIR3R_CONTEXT=""
ARG FAIR3R_EXTENSION_GIT_URL=""
ARG PAGE_EXTENSION_GIT_URL=""
ARG DOI_EXTENSION_GIT_URL=""

USER root

# Common packages
RUN if command -v apt-get >/dev/null 2>&1; then \
      apt-get update && \
      apt-get install -y --no-install-recommends \
        bash \
        curl \
        gettext-base \
        git \
        postgresql-client \
        supervisor && \
      rm -rf /var/lib/apt/lists/*; \
    elif command -v apk >/dev/null 2>&1; then \
      apk add --no-cache \
        bash \
        curl \
        gettext \
        git \
        postgresql-client \
        supervisor; \
    else \
      echo "Unsupported base image: no apt-get or apk found" >&2; \
      exit 1; \
    fi

# Extensions toujours installées
RUN pip install --no-cache-dir ckanext-xloader chardet==4.0.0 tabulator unidecode
RUN pip install --no-cache-dir -e "git+https://github.com/USEPA/ckanext-plotly.git@master#egg=ckanext-plotly"
RUN pip install --no-cache-dir -e "git+https://github.com/ckan/ckanext-pdfview.git@master#egg=ckanext-pdfview"
RUN pip install --no-cache-dir -e "git+https://github.com/NaturalHistoryMuseum/ckanext-contact.git@main#egg=ckanext-contact"

# Dev-only extensions
RUN if [ "$FAIR3R_CONTEXT" = "DEV" ]; then \
      echo "Installing dev-only extensions..."; \
      pip install --no-cache-dir flask-debugtoolbar==0.13.1; \
    fi

# Prod-only extensions
RUN if [ "$FAIR3R_CONTEXT" != "DEV" ]; then \
      echo "Installing prod-only extensions..."; \
      [ -n "$FAIR3R_EXTENSION_GIT_URL" ] && pip install --no-cache-dir "$FAIR3R_EXTENSION_GIT_URL" || echo "No FAIR3R URL, skipping"; \
      [ -n "$PAGE_EXTENSION_GIT_URL" ] && pip install --no-cache-dir "$PAGE_EXTENSION_GIT_URL" || echo "No PAGE URL, skipping"; \
      [ -n "$DOI_EXTENSION_GIT_URL" ] && pip install --no-cache-dir "$DOI_EXTENSION_GIT_URL" || echo "No DOI URL, skipping"; \
    fi

# Copy configs & scripts
COPY config/ckan.ini.template /srv/app/config/ckan.ini.template
COPY supervisord.prod.conf /etc/supervisor/conf.d/ckan-supervisord-prod.conf
COPY supervisord.dev.conf /etc/supervisor/conf.d/ckan-supervisord-dev.conf
COPY scripts/entrypoint.sh /srv/app/scripts/entrypoint.sh
COPY scripts/create_sysadmin.sh /srv/app/scripts/create_sysadmin.sh

RUN chmod +x /srv/app/scripts/entrypoint.sh /srv/app/scripts/create_sysadmin.sh

ENTRYPOINT ["/srv/app/scripts/entrypoint.sh"]
