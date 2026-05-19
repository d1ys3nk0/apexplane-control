#!/usr/bin/env bash

set -euo pipefail

CERT_NAME=$(basename "${RENEWED_LINEAGE}")
read -r -a RENEWED_DOMAIN_LIST <<<"${RENEWED_DOMAINS}"
CERT_DOMAINS=$(printf '%s\n' "${RENEWED_DOMAIN_LIST[@]}" | sort | paste -sd, -)
CERT_HASH=$(printf '%s' "${CERT_DOMAINS}" | md5sum | awk '{print $1}')
CERT_DST="/etc/ssl/haproxy/${CERT_NAME}-${CERT_HASH}.pem"
TMP_FILE=$(mktemp "${CERT_DST}.tmp.XXXXXX")

trap 'rm -f "${TMP_FILE}"' EXIT
sed '/^$/d' "${RENEWED_LINEAGE}/privkey.pem" "${RENEWED_LINEAGE}/fullchain.pem" >"${TMP_FILE}"
chown haproxy:haproxy "${TMP_FILE}"
chmod 600 "${TMP_FILE}"
mv "${TMP_FILE}" "${CERT_DST}"
trap - EXIT

echo "Validating HAProxy config..."
haproxy -c -f /etc/haproxy/haproxy.cfg -f /etc/haproxy/conf.d

echo "Reloading HAProxy..."
systemctl reload haproxy
systemctl is-active haproxy >/dev/null
