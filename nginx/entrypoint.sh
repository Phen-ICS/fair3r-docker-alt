#!/bin/sh
set -e

# Generate self-signed certificate if not exists
if [ ! -f /etc/nginx/certs/ckan-local.crt ]; then
  openssl req \
    -subj '/C=DE/ST=Berlin/L=Berlin/O=None/CN=localhost' \
    -x509 -newkey rsa:4096 \
    -nodes \
    -keyout /etc/nginx/certs/ckan-local.key \
    -out /etc/nginx/certs/ckan-local.crt \
    -days 365
fi

FAIR3R_CONTEXT="$(printf '%s' "${FAIR3R_CONTEXT}" | tr '[:lower:]' '[:upper:]')"

if [ "$FAIR3R_CONTEXT" = "DEV" ]; then
  CACHE_DIRECTIVE=""
else
  CACHE_DIRECTIVE="proxy_cache_valid 30m;"
fi

envsubst '${CACHE_DIRECTIVE}' < /etc/nginx/templates/default.conf.template > /etc/nginx/conf.d/default.conf

exec nginx -g 'daemon off;'