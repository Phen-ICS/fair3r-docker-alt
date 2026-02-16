#!/usr/bin/env bash
set -euo pipefail

: "${CKAN_INI_TEMPLATE:=/srv/app/config/ckan.ini.template}"
: "${CKAN_INI:=/srv/app/ckan.ini}"
: "${CKAN_DB_HOST:=db}"
: "${CKAN_DB_PORT:=5432}"
: "${CKAN_DB_NAME:=ckan}"
: "${CKAN_DB_USER:=ckan}"
: "${CKAN_DB_PASSWORD:=ckan}"
: "${CKAN_DATASTORE_DB_NAME:=datastore}"
: "${CKAN_DATASTORE_DB_USER:=ckan_datastore}"
: "${CKAN_DATASTORE_DB_PASSWORD:=ckan_datastore}"
: "${CKAN_DATASTORE_READONLY_USER:=ckan_datastore_ro}"
: "${CKAN_DATASTORE_READONLY_PASSWORD:=ckan_datastore_ro}"
: "${CKAN_SOLR_URL:=http://solr:8983/solr/ckan}"
: "${CKAN_REDIS_URL:=redis://redis:6379/1}"
: "${CKAN_SITE_URL:=http://localhost:5000}"
: "${CKAN_XLOADER_API_TOKEN:=}"
: "${CKAN_XLOADER_TOKEN_USER:=}"
: "${CKAN_XLOADER_TOKEN_NAME:=xloader}"
: "${CKAN_BOOTSTRAP_SYSADMIN_NAME:=}"
: "${CKAN_BOOTSTRAP_SYSADMIN_EMAIL:=}"
: "${CKAN_BOOTSTRAP_SYSADMIN_PASSWORD:=}"

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

wait_for_service "${CKAN_DB_HOST}" "${CKAN_DB_PORT}" "PostgreSQL"
wait_for_service "solr" "8983" "Solr"
wait_for_service "redis" "6379" "Redis"

echo "Rendering CKAN config from template..."
envsubst < "${CKAN_INI_TEMPLATE}" > "${CKAN_INI}"

mkdir -p /var/lib/ckan /var/lib/ckan/storage
chown -R ckan:ckan /var/lib/ckan
chown -R ckan:ckan /srv/app/src/ckan/ckan/public/base/i18n
chmod 640 "${CKAN_INI}"
chown ckan:ckan "${CKAN_INI}"

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

echo "Applying DataStore permissions..."
su -s /bin/bash ckan -c \
  "ckan -c ${CKAN_INI} datastore set-permissions | awk 'BEGIN {emit=0} /^\\/\\*/ {emit=1} emit {print}'" \
  | PGPASSWORD="${CKAN_DB_PASSWORD}" psql \
      -v ON_ERROR_STOP=1 \
      -h "${CKAN_DB_HOST}" \
      -p "${CKAN_DB_PORT}" \
      -U "${CKAN_DB_USER}" \
      -d postgres

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

if [ -n "${CKAN_BOOTSTRAP_SYSADMIN_NAME}" ]; then
  echo "Ensuring bootstrap sysadmin '${CKAN_BOOTSTRAP_SYSADMIN_NAME}' exists..."

  if ! su -s /bin/bash ckan -c "ckan -c ${CKAN_INI} user show ${CKAN_BOOTSTRAP_SYSADMIN_NAME}" >/dev/null 2>&1; then
    if [ -z "${CKAN_BOOTSTRAP_SYSADMIN_EMAIL}" ] || [ -z "${CKAN_BOOTSTRAP_SYSADMIN_PASSWORD}" ]; then
      echo "WARNING: Bootstrap sysadmin user missing and CKAN_BOOTSTRAP_SYSADMIN_EMAIL/PASSWORD not provided."
      echo "         Skipping bootstrap user creation."
    else
      su -s /bin/bash ckan -c \
        "ckan -c ${CKAN_INI} user add ${CKAN_BOOTSTRAP_SYSADMIN_NAME} email=${CKAN_BOOTSTRAP_SYSADMIN_EMAIL} password=${CKAN_BOOTSTRAP_SYSADMIN_PASSWORD}" \
        >/dev/null
    fi
  fi

  # Keep this non-fatal to avoid restart loops.
  su -s /bin/bash ckan -c "ckan -c ${CKAN_INI} sysadmin add ${CKAN_BOOTSTRAP_SYSADMIN_NAME}" >/dev/null 2>&1 || true
fi

if [ -n "${CKAN_XLOADER_TOKEN_USER}" ]; then
  echo "Rotating xloader API token '${CKAN_XLOADER_TOKEN_NAME}' for user '${CKAN_XLOADER_TOKEN_USER}'..."
  can_rotate_token=true

  if ! su -s /bin/bash ckan -c "ckan -c ${CKAN_INI} user show ${CKAN_XLOADER_TOKEN_USER}" >/dev/null 2>&1; then
    echo "WARNING: User '${CKAN_XLOADER_TOKEN_USER}' not found. Skipping xloader token rotation and keeping current CKAN_XLOADER_API_TOKEN."
    can_rotate_token=false
  fi

  if [ "${can_rotate_token}" = true ]; then
    echo "Ensuring '${CKAN_XLOADER_TOKEN_USER}' is sysadmin..."
    if ! su -s /bin/bash ckan -c "ckan -c ${CKAN_INI} sysadmin add ${CKAN_XLOADER_TOKEN_USER}" >/dev/null 2>&1; then
      # If already sysadmin, CKAN may return non-zero in some setups.
      # Confirm role explicitly to avoid using a token with insufficient permissions.
      if ! su -s /bin/bash ckan -c "ckan -c ${CKAN_INI} user show ${CKAN_XLOADER_TOKEN_USER}" | grep -qi "sysadmin"; then
        echo "WARNING: User '${CKAN_XLOADER_TOKEN_USER}' is not sysadmin and cannot be promoted automatically."
        echo "         Skipping xloader token rotation and keeping current CKAN_XLOADER_API_TOKEN."
        can_rotate_token=false
      fi
    fi
  fi

  if [ "${can_rotate_token}" = true ]; then
    existing_token_ids="$(
      su -s /bin/bash ckan -c "ckan -c ${CKAN_INI} user token list ${CKAN_XLOADER_TOKEN_USER}" \
        | awk -v token_name="${CKAN_XLOADER_TOKEN_NAME}" '
            match($0, /^\t?\[([^]]+)\] (.*) - /, m) {
              if (m[2] == token_name) {
                print m[1]
              }
            }'
    )"

    if [ -n "${existing_token_ids}" ]; then
      while IFS= read -r token_id; do
        [ -n "${token_id}" ] || continue
        su -s /bin/bash ckan -c "ckan -c ${CKAN_INI} user token revoke ${token_id}" >/dev/null
      done <<< "${existing_token_ids}"
    fi

    CKAN_XLOADER_API_TOKEN="$(
      su -s /bin/bash ckan -c "ckan -c ${CKAN_INI} user token add ${CKAN_XLOADER_TOKEN_USER} ${CKAN_XLOADER_TOKEN_NAME} -q" \
        | tr -d '\r\n'
    )"

    if [[ ! "${CKAN_XLOADER_API_TOKEN}" =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]]; then
      echo "WARNING: Generated xloader token is not JWT-like. Keeping current CKAN_XLOADER_API_TOKEN."
    elif grep -q "^ckanext.xloader.api_token = " "${CKAN_INI}"; then
      sed -i "s|^ckanext.xloader.api_token = .*|ckanext.xloader.api_token = ${CKAN_XLOADER_API_TOKEN}|" "${CKAN_INI}"
    else
      printf "\nckanext.xloader.api_token = %s\n" "${CKAN_XLOADER_API_TOKEN}" >> "${CKAN_INI}"
    fi
  fi
elif [[ ! "${CKAN_XLOADER_API_TOKEN}" =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]]; then
  echo "WARNING: CKAN_XLOADER_API_TOKEN is not a JWT-like token; xloader hooks may fail with 403."
else
  echo "WARNING: CKAN_XLOADER_TOKEN_USER is empty; using static CKAN_XLOADER_API_TOKEN as-is."
  echo "         If uploads fail with NotAuthorized, set CKAN_XLOADER_TOKEN_USER to a sysadmin user."
fi

echo "Starting CKAN web and xloader worker via supervisord..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/ckan-supervisord.conf
