ARG CKAN_VERSION=2.11.5
FROM ckan/ckan-base:${CKAN_VERSION}

#Build args
ARG FAIR3R_CONTEXT=""


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
RUN pip install --no-cache-dir ckanext-xloader==2.3.0 chardet==4.0.0 tabulator==1.53.5 unidecode==1.4.0
RUN pip install --no-cache-dir -e "git+https://github.com/ckan/ckanext-pdfview.git@master#egg=ckanext-pdfview"
RUN pip install --no-cache-dir -e "git+https://github.com/NaturalHistoryMuseum/ckanext-contact.git@main#egg=ckanext-contact"
#RUN pip install --no-cache-dir -e "git+https://github.com/ckan/ckanext-excelforms.git@main#egg=ckanext-excelforms"
RUN pip install --no-cache-dir -e "git+https://github.com/ckan/ckanext-dsaudit.git@master#egg=ckanext-dsaudit"


# WORKAROUND: CKAN 2.11+ build_js_translations() requires an i18n/ directory per enabled plugin; upstream sometimes omits it.
RUN python3 -c "import pathlib, ckanext.dsaudit; p = pathlib.Path(ckanext.dsaudit.__file__).parent / 'i18n'; p.mkdir(parents=True, exist_ok=True)"

# Dev-only extensions
RUN if [ "$FAIR3R_CONTEXT" = "DEV" ]; then \
      echo "Installing dev-only extensions..."; \
      pip install --no-cache-dir flask-debugtoolbar==0.16.0; \
    fi

# Copy configs & scripts
COPY config/ckan.ini.template /srv/app/config/ckan.ini.template
COPY supervisord.prod.conf /etc/supervisor/conf.d/ckan-supervisord-prod.conf
COPY supervisord.dev.conf /etc/supervisor/conf.d/ckan-supervisord-dev.conf
COPY scripts/entrypoint.sh /srv/app/scripts/entrypoint.sh
COPY scripts/create_sysadmin.sh /srv/app/scripts/create_sysadmin.sh

RUN chmod +x /srv/app/scripts/entrypoint.sh /srv/app/scripts/create_sysadmin.sh

ENTRYPOINT ["/srv/app/scripts/entrypoint.sh"]
