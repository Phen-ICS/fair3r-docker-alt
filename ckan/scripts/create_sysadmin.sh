#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <username> <email> <password>"
  exit 1
fi

USERNAME="$1"
EMAIL="$2"
PASSWORD="$3"
CKAN_BIN="ckan"
CKAN_INI="${CKAN_INI:-/srv/app/ckan.ini}"

if ! su -s /bin/bash ckan -c "${CKAN_BIN} -c ${CKAN_INI} user show ${USERNAME}" >/dev/null 2>&1; then
  su -s /bin/bash ckan -c "${CKAN_BIN} -c ${CKAN_INI} user add ${USERNAME} email=${EMAIL} password=${PASSWORD}"
fi

if ! su -s /bin/bash ckan -c "${CKAN_BIN} -c ${CKAN_INI} sysadmin add ${USERNAME}"; then
  echo "User may already be sysadmin. Verify with:"
  echo "  ${CKAN_BIN} -c ${CKAN_INI} user show ${USERNAME}"
fi
