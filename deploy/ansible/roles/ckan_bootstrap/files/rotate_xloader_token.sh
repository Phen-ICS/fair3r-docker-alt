#!/usr/bin/env bash
#
# Port of the Xloader API token rotation logic from
# ckan/scripts/entrypoint.sh. Runs idempotently: deletes any pre-existing
# token named "Xloader" for the given sysadmin, creates a new one, writes it
# to /var/lib/ckan/xloader.token and injects it into ckan.ini via
# `ckan config-tool`.
#
# Required environment variables (injected by the Ansible task):
#   CKAN_INI                           path to ckan.ini
#   CKAN_VENV_BIN                      /usr/lib/ckan/default/bin
#   CKAN_OS_USER                       'ckan' (system user)
#   CKAN_DB_HOST, CKAN_DB_PORT, CKAN_DB_USER, CKAN_DB_PASSWORD, CKAN_DB_NAME
#   CKAN_BOOTSTRAP_SYSADMIN_NAME
#   XLOADER_TOKEN_FILE

set -euo pipefail

XLOADER_TOKEN_NAME="Xloader"
CKAN_BIN="${CKAN_VENV_BIN}/ckan"

extract_jwt() {
  grep -oE 'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+' | tail -1
}

PGPASSWORD="${CKAN_DB_PASSWORD}" psql \
  -h "${CKAN_DB_HOST}" \
  -p "${CKAN_DB_PORT}" \
  -U "${CKAN_DB_USER}" \
  -d "${CKAN_DB_NAME}" \
  -tAc "DELETE FROM api_token WHERE name = '${XLOADER_TOKEN_NAME}' AND user_id = (SELECT id FROM \"user\" WHERE name = '${CKAN_BOOTSTRAP_SYSADMIN_NAME}');" \
  >/dev/null 2>&1 || true

raw_output="$(su -s /bin/bash "${CKAN_OS_USER}" -c \
  "${CKAN_BIN} -c ${CKAN_INI} user token add ${CKAN_BOOTSTRAP_SYSADMIN_NAME} ${XLOADER_TOKEN_NAME} -q" \
  2>/dev/null)"

xloader_token="$(echo "${raw_output}" | extract_jwt)"

if [ -z "${xloader_token}" ]; then
  echo "ERROR: Could not create Xloader API token" >&2
  exit 1
fi

umask 077
echo "${xloader_token}" > "${XLOADER_TOKEN_FILE}"
chown "${CKAN_OS_USER}" "${XLOADER_TOKEN_FILE}"
chmod 600 "${XLOADER_TOKEN_FILE}"

"${CKAN_BIN}" config-tool "${CKAN_INI}" "ckanext.xloader.api_token = ${xloader_token}"

echo "Rotated Xloader API token."
