#!/usr/bin/env bash

set -euo pipefail

CERT_NAME=$(basename "${RENEWED_LINEAGE}")
read -r -a RENEWED_DOMAIN_LIST <<<"${RENEWED_DOMAINS}"
CERT_DOMAINS=$(printf '%s\n' "${RENEWED_DOMAIN_LIST[@]}" | sort | paste -sd, -)
CERT_HASH=$(printf '%s' "${CERT_DOMAINS}" | md5sum | awk '{print $1}')
CERT_DST="/etc/ssl/haproxy/${CERT_NAME}-${CERT_HASH}.pem"
TMP_FILE=$(mktemp "${CERT_DST}.tmp.XXXXXX")

verify_haproxy_public_listeners() {
    local listener_cgroup
    local listener_comm
    local listener_lines
    local listener_pid
    local listener_pids
    local port

    for port in 80 443; do
        listener_lines=$(ss -H -ltnp "sport = :${port}" || true)
        if [ -z "${listener_lines}" ]; then
            echo "Port ${port} has no TCP listener."
            return 1
        fi

        listener_pids=$(printf '%s\n' "${listener_lines}" | grep -o 'pid=[0-9]\+' | cut -d= -f2 | sort -u)
        if [ -z "${listener_pids}" ]; then
            echo "Port ${port} listener process is not visible:"
            printf '%s\n' "${listener_lines}"
            return 1
        fi

        for listener_pid in ${listener_pids}; do
            listener_comm=$(cat "/proc/${listener_pid}/comm" 2>/dev/null || true)
            listener_cgroup=$(cat "/proc/${listener_pid}/cgroup" 2>/dev/null || true)
            if [ "${listener_comm}" != "haproxy" ] || ! grep -q '/system.slice/haproxy.service' <<<"${listener_cgroup}"; then
                echo "Port ${port} is not owned by haproxy.service:"
                printf '%s\n' "${listener_lines}"
                echo "PID ${listener_pid} command: ${listener_comm:-unknown}"
                echo "PID ${listener_pid} cgroup:"
                printf '%s\n' "${listener_cgroup:-unknown}"
                return 1
            fi
        done
    done
}

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

echo "Verifying HAProxy..."
systemctl is-active haproxy >/dev/null
verify_haproxy_public_listeners
