ARG CKAN_VERSION=2.10.7
FROM ckan/ckan-base:${CKAN_VERSION}
ARG FAIR3R_EXTENSION_GIT_URL=""
ARG PAGE_EXTENSION_GIT_URL=""
ARG DOI_EXTENSION_GIT_URL=""

USER root

RUN if command -v apt-get >/dev/null 2>&1; then \
      apt-get update && \
      apt-get install -y --no-install-recommends \
        curl \
        gettext-base \
        postgresql-client \
        supervisor && \
      rm -rf /var/lib/apt/lists/*; \
    elif command -v apk >/dev/null 2>&1; then \
      apk add --no-cache \
        bash \
        curl \
        gettext \
        postgresql-client \
        supervisor; \
    else \
      echo "Unsupported base image: no apt-get or apk found" >&2; \
      exit 1; \
    fi

RUN pip install --no-cache-dir ckanext-xloader chardet tabulator unidecode
RUN if [ -n "${FAIR3R_EXTENSION_GIT_URL}" ]; then \
      pip install --no-cache-dir "${FAIR3R_EXTENSION_GIT_URL}"; \
    else \
      echo "No FAIR3R_EXTENSION_GIT_URL provided, skipping fair3r extension install."; \
    fi

RUN if [ -n "${PAGE_EXTENSION_GIT_URL}" ]; then \
      pip install -vvv --no-cache-dir "${PAGE_EXTENSION_GIT_URL}"; \
    else \
      echo "No PAGE_EXTENSION_GIT_URL provided, skipping fair3r extension install."; \
    fi

RUN if [ -n "${DOI_EXTENSION_GIT_URL}" ]; then \
      pip install -vvv --no-cache-dir "${DOI_EXTENSION_GIT_URL}"; \
    else \
      echo "No DOI_EXTENSION_GIT_URL provided, skipping fair3r extension install."; \
    fi

# Plotly Explorer
RUN pip3 install -e "git+https://github.com/USEPA/ckanext-plotly.git@master#egg=ckanext-plotly"

# PDF View
RUN pip3 install -e "git+https://github.com/ckan/ckanext-pdfview.git@master#egg=ckanext-pdfview"

# Contact
RUN pip3 install -e "git+https://github.com/NaturalHistoryMuseum/ckanext-contact.git@main#egg=ckanext-contact"



COPY config/ckan.ini.template /srv/app/config/ckan.ini.template
COPY supervisord.conf /etc/supervisor/conf.d/ckan-supervisord.conf
COPY scripts/entrypoint.sh /srv/app/scripts/entrypoint.sh
COPY scripts/create_sysadmin.sh /srv/app/scripts/create_sysadmin.sh

RUN chmod +x /srv/app/scripts/entrypoint.sh /srv/app/scripts/create_sysadmin.sh

ENTRYPOINT ["/srv/app/scripts/entrypoint.sh"]
