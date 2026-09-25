#!/usr/bin/env bash
set -euo pipefail

wait_for_service() {
  local host="$1"
  local port="$2"
  local name="$3"
  local retries=60

  echo "Waiting for ${name} at ${host}:${port}..."
  while ! (echo >"/dev/tcp/${host}/${port}") >/dev/null 2>&1; do
    retries=$((retries - 1))
    if [ "${retries}" -le 0 ]; then
      echo "ERROR: ${name} not reachable at ${host}:${port}"
      exit 1
    fi
    sleep 2
  done
  echo "${name} is reachable."
}

fair3r_gitlab_pypi_install() {
  local pkg="$1"
  local token="$2"
  local host="$3"
  local proj_id="$4"

  [ -n "$token" ] || return 0

  echo "Installing ${pkg} from GitLab Package Registry (${host}, project ${proj_id})..."
  local encoded
  encoded="$(TOKEN="${token}" python3 -c 'import os, urllib.parse; print(urllib.parse.quote(os.environ["TOKEN"], safe=""))')"
  pip install --no-cache-dir --upgrade --no-deps "${pkg}" \
    --index-url "https://pypi.org/simple" \
    --extra-index-url "https://__token__:${encoded}@${host}/api/v4/projects/${proj_id}/packages/pypi/simple"
}

install_fair3r_extensions_from_gitlab_pypi() {
  local host="${GITLAB_EXTENSIONS_PYPI_HOST:-}"
  export PIP_PROGRESS_BAR=off

  fair3r_gitlab_pypi_install "ckanext-fair3r" "${FAIR3R_EXTENSION_PYPI_TOKEN:-}" \
    "${host}" "${FAIR3R_PYPI_PROJECT_ID:-}"
  fair3r_gitlab_pypi_install "ckanext-fair3r-pages" "${PAGE_EXTENSION_PYPI_TOKEN:-}" \
    "${host}" "${PAGE_PYPI_PROJECT_ID:-}"
  fair3r_gitlab_pypi_install "ckanext-fair3r-doi" "${DOI_EXTENSION_PYPI_TOKEN:-}" \
    "${host}" "${DOI_PYPI_PROJECT_ID:-}"
  fair3r_gitlab_pypi_install "ckanext-fair3r-plotly" "${PLOTLY_EXTENSION_PYPI_TOKEN:-}" \
    "${host}" "${PLOTLY_PYPI_PROJECT_ID:-}"
}

wait_for_service "${CKAN_DB_HOST}" "${CKAN_DB_PORT}" "PostgreSQL"
wait_for_service "solr" "8983" "Solr"
wait_for_service "redis" "6379" "Redis"

echo "Rendering CKAN config from template..."
envsubst < "${CKAN_INI_TEMPLATE}" > "${CKAN_INI}"

FAIR3R_CONTEXT="$(printf '%s' "${FAIR3R_CONTEXT}" | tr '[:lower:]' '[:upper:]')"

# CKAN 2.11 asserts that legacy config option "lang" is not set.
# In container environments LANG can leak into CKAN config as "lang",
# so clear locale env vars before invoking CKAN CLI commands.
unset LANG
unset LC_ALL

mkdir -p /var/lib/ckan /var/lib/ckan/storage
chown -R ckan /var/lib/ckan
chmod 640 "${CKAN_INI}"
chown ckan "${CKAN_INI}"

echo "Installing Fair3R CKAN extensions from GitLab Package Registry (skipped if tokens unset in .env)..."
install_fair3r_extensions_from_gitlab_pypi

# Mounted source trees (DEV): editable installs run after Package Registry installs so local code wins.
echo "Installing custom CKAN plugins from mounted sources (DEV context only)..."

shopt -s nullglob

if [ "${FAIR3R_CONTEXT}" = "DEV" ]; then
  for plugin_dir in /plugins/*; do
    [ -d "$plugin_dir" ] || continue

    plugin_name=$(basename "$plugin_dir")

    # Install dev requirements if the file exists
    if [ -f "$plugin_dir/dev-requirements.txt" ]; then
        echo "Installing dev dependencies for ${plugin_name}"
        pip install --ignore-installed --no-deps -r "$plugin_dir/dev-requirements.txt"
    fi

    # Install the plugin in editable mode if it has a Python project file
    if [ -f "$plugin_dir/setup.py" ] || [ -f "$plugin_dir/pyproject.toml" ]; then
      echo "Installing plugin (dev mode): ${plugin_name}"
      pip install --no-deps -e "$plugin_dir"
    else
      echo "Skipping ${plugin_name} (not a Python project)"
    fi
  done
fi

# pip runs as root, but ckan CLI commands (including fair3r update-schema) run
# as the ckan user and need write access to the bundled schema directory when
# downloading from GitHub. DEV with a local clone reads /fdf-schema instead.
echo "Ensuring ckan user can write to ckanext-fair3r schema directory..."
FAIR3R_SCHEMA_DIR="$(su -s /bin/bash ckan -c "python -c \"import ckanext.fair3r.tasks as t; print(t.SCHEMA_DIR)\"")"
mkdir -p "${FAIR3R_SCHEMA_DIR}/i18n"
chown -R ckan "${FAIR3R_SCHEMA_DIR}"
chmod -R 0755 "${FAIR3R_SCHEMA_DIR}"
echo "Schema directory ${FAIR3R_SCHEMA_DIR} ready for ckan user."


echo "Ensuring DataStore database and user exist..."
if ! PGPASSWORD="${CKAN_DB_PASSWORD}" psql \
  -h "${CKAN_DB_HOST}" \
  -p "${CKAN_DB_PORT}" \
  -U "${CKAN_DB_USER}" \
  -d postgres \
  -tAc "SELECT 1 FROM pg_roles WHERE rolname='${CKAN_DATASTORE_DB_USER}'" | grep -q 1; then
  PGPASSWORD="${CKAN_DB_PASSWORD}" psql \
    -h "${CKAN_DB_HOST}" \
    -p "${CKAN_DB_PORT}" \
    -U "${CKAN_DB_USER}" \
    -d postgres \
    -c "CREATE ROLE ${CKAN_DATASTORE_DB_USER} LOGIN PASSWORD '${CKAN_DATASTORE_DB_PASSWORD}';"
fi
PGPASSWORD="${CKAN_DB_PASSWORD}" psql \
  -h "${CKAN_DB_HOST}" \
  -p "${CKAN_DB_PORT}" \
  -U "${CKAN_DB_USER}" \
  -d postgres \
  -c "ALTER ROLE ${CKAN_DATASTORE_DB_USER} WITH LOGIN PASSWORD '${CKAN_DATASTORE_DB_PASSWORD}';"

if ! PGPASSWORD="${CKAN_DB_PASSWORD}" psql \
  -h "${CKAN_DB_HOST}" \
  -p "${CKAN_DB_PORT}" \
  -U "${CKAN_DB_USER}" \
  -d postgres \
  -tAc "SELECT 1 FROM pg_roles WHERE rolname='${CKAN_DATASTORE_READONLY_USER}'" | grep -q 1; then
  PGPASSWORD="${CKAN_DB_PASSWORD}" psql \
    -h "${CKAN_DB_HOST}" \
    -p "${CKAN_DB_PORT}" \
    -U "${CKAN_DB_USER}" \
    -d postgres \
    -c "CREATE ROLE ${CKAN_DATASTORE_READONLY_USER} LOGIN PASSWORD '${CKAN_DATASTORE_READONLY_PASSWORD}';"
fi
PGPASSWORD="${CKAN_DB_PASSWORD}" psql \
  -h "${CKAN_DB_HOST}" \
  -p "${CKAN_DB_PORT}" \
  -U "${CKAN_DB_USER}" \
  -d postgres \
  -c "ALTER ROLE ${CKAN_DATASTORE_READONLY_USER} WITH LOGIN PASSWORD '${CKAN_DATASTORE_READONLY_PASSWORD}';"

if ! PGPASSWORD="${CKAN_DB_PASSWORD}" psql \
  -h "${CKAN_DB_HOST}" \
  -p "${CKAN_DB_PORT}" \
  -U "${CKAN_DB_USER}" \
  -d postgres \
  -tAc "SELECT 1 FROM pg_database WHERE datname='${CKAN_DATASTORE_DB_NAME}'" | grep -q 1; then
  PGPASSWORD="${CKAN_DB_PASSWORD}" psql \
    -h "${CKAN_DB_HOST}" \
    -p "${CKAN_DB_PORT}" \
    -U "${CKAN_DB_USER}" \
    -d postgres \
    -c "CREATE DATABASE ${CKAN_DATASTORE_DB_NAME} OWNER ${CKAN_DATASTORE_DB_USER};"
fi
PGPASSWORD="${CKAN_DB_PASSWORD}" psql \
  -h "${CKAN_DB_HOST}" \
  -p "${CKAN_DB_PORT}" \
  -U "${CKAN_DB_USER}" \
  -d postgres \
  -c "ALTER DATABASE ${CKAN_DATASTORE_DB_NAME} OWNER TO ${CKAN_DATASTORE_DB_USER};"

echo "Creating test databases..."
# Create CKAN test database if it doesn't exist
if ! PGPASSWORD="${CKAN_DB_PASSWORD}" psql \
  -h "${CKAN_DB_HOST}" \
  -p "${CKAN_DB_PORT}" \
  -U "${CKAN_DB_USER}" \
  -d postgres \
  -tAc "SELECT 1 FROM pg_database WHERE datname='${CKAN_TEST_DB_NAME}'" | grep -q 1; then
  PGPASSWORD="${CKAN_DB_PASSWORD}" psql \
    -h "${CKAN_DB_HOST}" \
    -p "${CKAN_DB_PORT}" \
    -U "${CKAN_DB_USER}" \
    -d postgres \
    -c "CREATE DATABASE ${CKAN_TEST_DB_NAME} OWNER ${CKAN_DB_USER};"
  echo "Created ${CKAN_TEST_DB_NAME} database."
else
  echo "${CKAN_TEST_DB_NAME} database already exists."
fi

# Create DataStore test database if it doesn't exist
if ! PGPASSWORD="${CKAN_DB_PASSWORD}" psql \
  -h "${CKAN_DB_HOST}" \
  -p "${CKAN_DB_PORT}" \
  -U "${CKAN_DB_USER}" \
  -d postgres \
  -tAc "SELECT 1 FROM pg_database WHERE datname='${CKAN_DATASTORE_TEST_DB_NAME}'" | grep -q 1; then
  PGPASSWORD="${CKAN_DB_PASSWORD}" psql \
    -h "${CKAN_DB_HOST}" \
    -p "${CKAN_DB_PORT}" \
    -U "${CKAN_DB_USER}" \
    -d postgres \
    -c "CREATE DATABASE ${CKAN_DATASTORE_TEST_DB_NAME} OWNER ${CKAN_DATASTORE_DB_USER};"
  echo "Created ${CKAN_DATASTORE_TEST_DB_NAME} database."
else
  echo "${CKAN_DATASTORE_TEST_DB_NAME} database already exists."
fi

echo "Checking CKAN database state..."
if PGPASSWORD="${CKAN_DB_PASSWORD}" psql \
  -h "${CKAN_DB_HOST}" \
  -p "${CKAN_DB_PORT}" \
  -U "${CKAN_DB_USER}" \
  -d "${CKAN_DB_NAME}" \
  -tAc "SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='package'" | grep -q 1; then
  echo "Existing CKAN database found. Running migrations..."
  su -s /bin/bash ckan -c "ckan -c ${CKAN_INI} db upgrade"
else
  echo "No CKAN tables found. Running initial database setup..."
  su -s /bin/bash ckan -c "ckan -c ${CKAN_INI} db init"
fi

echo "Applying DataStore permissions..."
su -s /bin/bash ckan -c \
  "ckan -c ${CKAN_INI} datastore set-permissions | awk 'BEGIN {emit=0} /^\\/\\*/ {emit=1} emit {print}'" \
  | PGPASSWORD="${CKAN_DB_PASSWORD}" psql \
      -v ON_ERROR_STOP=1 \
      -h "${CKAN_DB_HOST}" \
      -p "${CKAN_DB_PORT}" \
      -U "${CKAN_DB_USER}" \
      -d postgres

echo "Ensuring admin user '${CKAN_BOOTSTRAP_SYSADMIN_NAME}' exists and password matches .env..."
admin_exists="$(
  PGPASSWORD="${CKAN_DB_PASSWORD}" psql \
    -h "${CKAN_DB_HOST}" \
    -p "${CKAN_DB_PORT}" \
    -U "${CKAN_DB_USER}" \
    -d "${CKAN_DB_NAME}" \
    -tAc "SELECT 1 FROM \"user\" WHERE name='${CKAN_BOOTSTRAP_SYSADMIN_NAME}' LIMIT 1;" \
    | tr -d '[:space:]'
)"
if [ "${admin_exists}" = "1" ]; then
  su -s /bin/bash ckan -c \
    "ckan -c ${CKAN_INI} user setpass ${CKAN_BOOTSTRAP_SYSADMIN_NAME} -p ${CKAN_BOOTSTRAP_SYSADMIN_PASSWORD}" \
    >/dev/null
else
  su -s /bin/bash ckan -c \
    "ckan -c ${CKAN_INI} user add ${CKAN_BOOTSTRAP_SYSADMIN_NAME} email=${CKAN_BOOTSTRAP_SYSADMIN_EMAIL} password=${CKAN_BOOTSTRAP_SYSADMIN_PASSWORD}" \
    >/dev/null
fi

if ! su -s /bin/bash ckan -c "ckan -c ${CKAN_INI} sysadmin add ${CKAN_BOOTSTRAP_SYSADMIN_NAME}" >/dev/null 2>&1; then
  if ! su -s /bin/bash ckan -c "ckan -c ${CKAN_INI} user show ${CKAN_BOOTSTRAP_SYSADMIN_NAME}" | grep -qi "sysadmin"; then
    echo "WARNING: User '${CKAN_BOOTSTRAP_SYSADMIN_NAME}' is not sysadmin and cannot be promoted automatically."
  fi
fi

# Optional technical sysadmin account used as the actor for harvest jobs
# (ckanext-harvest based harvesters, e.g. oaipmh_harvester), so that
# harvested datasets show a real, identifiable creator instead of an
# unresolved username. Skipped entirely unless CKAN_HARVEST_USER_NAME is set.
if [ -n "${CKAN_HARVEST_USER_NAME:-}" ]; then
  echo "Ensuring harvest user '${CKAN_HARVEST_USER_NAME}' exists and password matches .env..."
  harvest_user_exists="$(
    PGPASSWORD="${CKAN_DB_PASSWORD}" psql \
      -h "${CKAN_DB_HOST}" \
      -p "${CKAN_DB_PORT}" \
      -U "${CKAN_DB_USER}" \
      -d "${CKAN_DB_NAME}" \
      -tAc "SELECT 1 FROM \"user\" WHERE name='${CKAN_HARVEST_USER_NAME}' LIMIT 1;" \
      | tr -d '[:space:]'
  )"
  if [ "${harvest_user_exists}" = "1" ]; then
    su -s /bin/bash ckan -c \
      "ckan -c ${CKAN_INI} user setpass ${CKAN_HARVEST_USER_NAME} -p ${CKAN_HARVEST_USER_PASSWORD}" \
      >/dev/null
  else
    su -s /bin/bash ckan -c \
      "ckan -c ${CKAN_INI} user add ${CKAN_HARVEST_USER_NAME} email=${CKAN_HARVEST_USER_EMAIL} password=${CKAN_HARVEST_USER_PASSWORD}" \
      >/dev/null
  fi

  if ! su -s /bin/bash ckan -c "ckan -c ${CKAN_INI} sysadmin add ${CKAN_HARVEST_USER_NAME}" >/dev/null 2>&1; then
    if ! su -s /bin/bash ckan -c "ckan -c ${CKAN_INI} user show ${CKAN_HARVEST_USER_NAME}" | grep -qi "sysadmin"; then
      echo "WARNING: User '${CKAN_HARVEST_USER_NAME}' is not sysadmin and cannot be promoted automatically."
    fi
  fi
fi

# Extract JWT from output (CKAN CLI may mix INFO logs with token on stdout)
extract_jwt() {
  grep -oE 'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+' | tail -1
}

# Ensure Xloader API token exists for admin user (rotate on every entrypoint run)
# Revoke via psql (fast, no CKAN startup) then create via single ckan invocation
XLOADER_TOKEN_NAME="Xloader"
XLOADER_TOKEN_FILE="/var/lib/ckan/xloader.token"
if [ -n "${CKAN_BOOTSTRAP_SYSADMIN_NAME}" ]; then
  echo "Ensuring Xloader API token for admin user '${CKAN_BOOTSTRAP_SYSADMIN_NAME}' (rotating)..."
  PGPASSWORD="${CKAN_DB_PASSWORD}" psql \
    -h "${CKAN_DB_HOST}" \
    -p "${CKAN_DB_PORT}" \
    -U "${CKAN_DB_USER}" \
    -d "${CKAN_DB_NAME}" \
    -tAc "DELETE FROM api_token WHERE name = '${XLOADER_TOKEN_NAME}' AND user_id = (SELECT id FROM \"user\" WHERE name = '${CKAN_BOOTSTRAP_SYSADMIN_NAME}');" \
    >/dev/null 2>&1 || true
  raw_output="$(su -s /bin/bash ckan -c "ckan -c ${CKAN_INI} user token add ${CKAN_BOOTSTRAP_SYSADMIN_NAME} ${XLOADER_TOKEN_NAME} -q" 2>/dev/null)"
  xloader_token="$(echo "${raw_output}" | extract_jwt)"
  if [ -n "${xloader_token}" ]; then
    echo "${xloader_token}" > "${XLOADER_TOKEN_FILE}"
    chown ckan "${XLOADER_TOKEN_FILE}"
    chmod 600 "${XLOADER_TOKEN_FILE}"
    ckan config-tool "${CKAN_INI}" "ckanext.xloader.api_token = ${xloader_token}"
    echo "Created new Xloader API token for admin user."
  else
    echo "WARNING: Could not create Xloader API token; xloader may not work correctly."
  fi
fi

echo "=== Set Fair3R Configuration ==="
[ -n "$FAIR3R_CONTEXT" ] && ckan config-tool "$CKAN_INI" "ckanext.fair3r.context = ${FAIR3R_CONTEXT}"
[ -n "$FAIR3R_ENABLE_FDF_INTEGRATION" ] && ckan config-tool "$CKAN_INI" "ckanext.fair3r.enable_fdf_integration = ${FAIR3R_ENABLE_FDF_INTEGRATION}"

FDF_SCHEMA_CONTAINER_DIR="${CKANEXT_FAIR3R_FDF_SCHEMA_DIR:-/fdf-schema}"
if [ -f "${FDF_SCHEMA_CONTAINER_DIR}/fdf_schema.json" ]; then
  echo "Using local FDF schema at ${FDF_SCHEMA_CONTAINER_DIR} (host path: ${FDF_SCHEMA_LOCAL_PATH:-unset})"
  ckan config-tool "$CKAN_INI" "ckanext.fair3r.fdf_schema_dir = ${FDF_SCHEMA_CONTAINER_DIR}"
  echo "Skipping GitHub schema download (local clone is mounted)."
elif [ -n "${FDF_SCHEMA_LOCAL_PATH:-}" ]; then
  echo "ERROR: FDF_SCHEMA_LOCAL_PATH is set to '${FDF_SCHEMA_LOCAL_PATH}' but ${FDF_SCHEMA_CONTAINER_DIR}/fdf_schema.json was not found."
  echo "Point FDF_SCHEMA_LOCAL_PATH at a clone of https://github.com/Phen-ICS/fair3r-fdf-schema (the directory that contains fdf_schema.json)."
  exit 1
else
  echo "Downloading and updating FDF schema from GitHub..."
  su -s /bin/bash ckan -c "ckan -c ${CKAN_INI} fair3r update-schema"
fi

echo "=== Set Contact Configuration ==="
[ -n "$CONTACT_MAIL" ] && ckan config-tool "$CKAN_INI" "ckanext.contact.mail_to = ${CONTACT_MAIL}"

echo "=== Set SMTP Configuration ==="
[ -n "$CKAN_EMAIL_SMTP_SERVER" ] && ckan config-tool "$CKAN_INI" "smtp.server = ${CKAN_EMAIL_SMTP_SERVER}"
[ -n "$CKAN_EMAIL_SMTP_STARTTLS" ] && ckan config-tool "$CKAN_INI" "smtp.starttls = ${CKAN_EMAIL_SMTP_STARTTLS}"
[ -n "$CKAN_EMAIL_SMTP_STARTTLS_VERIFY" ] && ckan config-tool "$CKAN_INI" "smtp.starttls_verify = ${CKAN_EMAIL_SMTP_STARTTLS_VERIFY}"
[ -n "$CKAN_EMAIL_SMTP_USER" ] && ckan config-tool "$CKAN_INI" "smtp.user = ${CKAN_EMAIL_SMTP_USER}"
[ -n "$CKAN_EMAIL_SMTP_PASSWORD" ] && ckan config-tool "$CKAN_INI" "smtp.password = ${CKAN_EMAIL_SMTP_PASSWORD}"
[ -n "$CKAN_EMAIL_SMTP_MAIL_FROM" ] && ckan config-tool "$CKAN_INI" "smtp.mail_from = ${CKAN_EMAIL_SMTP_MAIL_FROM}"
[ -n "$CKAN_EMAIL_SMTP_REPLY_TO" ] && ckan config-tool "$CKAN_INI" "smtp.reply_to = ${CKAN_EMAIL_SMTP_REPLY_TO}"
[ -n "$CKAN_EMAIL_SMTP_EMAIL_TO" ] && ckan config-tool "$CKAN_INI" "smtp.email_to = ${CKAN_EMAIL_SMTP_EMAIL_TO:-}"
[ -n "$CKAN_EMAIL_SMTP_ERROR_EMAIL_FROM" ] && ckan config-tool "$CKAN_INI" "smtp.error_email_from = ${CKAN_EMAIL_SMTP_ERROR_EMAIL_FROM:-}"

echo "=== Set DOI Configuration ==="
[ -n "$DOI_ACCOUNT_NAME" ] && ckan config-tool "$CKAN_INI" "ckanext.doi.account_name = ${DOI_ACCOUNT_NAME}"
[ -n "$DOI_ACCOUNT_PASSWORD" ] && ckan config-tool "$CKAN_INI" "ckanext.doi.account_password = ${DOI_ACCOUNT_PASSWORD}"
[ -n "$DOI_PREFIX" ] && ckan config-tool "$CKAN_INI" "ckanext.doi.prefix = ${DOI_PREFIX}"
[ -n "$DOI_PUBLISHER" ] && ckan config-tool "$CKAN_INI" "ckanext.doi.publisher = ${DOI_PUBLISHER}"
[ -n "$DOI_TEST_MODE" ] && ckan config-tool "$CKAN_INI" "ckanext.doi.test_mode = ${DOI_TEST_MODE}"
[ -n "$DOI_SITE_TITLE" ] && ckan config-tool "$CKAN_INI" "ckanext.doi.site_title = ${DOI_SITE_TITLE}"

ckan --config="$CKAN_INI" db upgrade -p doi

echo "=== Set Pages Configuration ==="
ckan config-tool "$CKAN_INI" "ckanext.pages.organization = True"
ckan config-tool "$CKAN_INI" "ckanext.pages.group = True"
ckan config-tool "$CKAN_INI" "ckanext.pages.allow_html = True"
ckan config-tool "$CKAN_INI" "ckanext.pages.editor = ckeditor"

ckan --config="$CKAN_INI" db upgrade -p pages

if [ "${FAIR3R_CONTEXT}" = "DEV" ]; then
  SUPERVISORD_CONFIG="/etc/supervisor/conf.d/ckan-supervisord-dev.conf"
else
  SUPERVISORD_CONFIG="/etc/supervisor/conf.d/ckan-supervisord-prod.conf"
fi

echo "Starting CKAN web and xloader worker via supervisord (${SUPERVISORD_CONFIG})..."
exec /usr/bin/supervisord -c "${SUPERVISORD_CONFIG}"
