#!/usr/bin/env bash

set -euo pipefail

DEFAULT_HAPROXY_CERT_DIR="/etc/ssl/haproxy"
DEFAULT_STATE_ROOT="/run/toolbox-certbot-dns"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=../lib/helpers.sh
source "${SCRIPT_DIR}/../lib/helpers.sh"

usage() {
    cat <<'EOF'
Usage: certbot_dns_issue --cert-name <name> --email <email> --domain <domain> [--domain <domain> ...]

Issues or renews a manual DNS-01 Certbot certificate and installs the combined HAProxy PEM.

Options:
  --cert-name <name>          Certbot lineage name and HAProxy cert name.
  --email <email>            Let's Encrypt account email.
  --domain, -d <domain>      Domain to include. Repeat for every SAN, including wildcards.
  --domains <domains>        Comma-separated domain list.
  --haproxy-cert-dir <dir>   HAProxy PEM directory. Defaults to /etc/ssl/haproxy.
  --state-root <dir>         Runtime state directory root. Defaults to /run/toolbox-certbot-dns.
  -h, --help                 Show this help.

Environment:
  CERTBOT_DNS_WAIT_RETRIES   TXT lookup attempts after operator confirmation. Defaults to 120.
  CERTBOT_DNS_WAIT_DELAY     Seconds between TXT lookup attempts. Defaults to 10.
  CERTBOT_DNS_HOOK_TIMEOUT   Seconds to wait for Certbot hook output. Defaults to 600.
  CERTBOT_MANUAL_DNS_TIMEOUT Seconds Certbot hooks wait for operator confirmation. Defaults to 3600.
EOF
}

add_domain() {
    local domain="$1"

    if [ -z "$domain" ]; then
        _usage_error "domain values must be non-empty"
    fi
    domains+=("$domain")
}

add_domains_arg() {
    local raw="$1"
    local part
    local -a parts=()

    IFS=',' read -r -a parts <<<"$raw"
    for part in "${parts[@]}"; do
        add_domain "$part"
    done
}

join_by_comma() {
    local IFS=,

    printf '%s' "$*"
}

cleanup() {
    local rc=$?

    if [ -n "${certbot_pid:-}" ] && kill -0 "$certbot_pid" 2>/dev/null; then
        kill "$certbot_pid" 2>/dev/null || true
        wait "$certbot_pid" 2>/dev/null || true
    fi
    if [ -n "${state_dir:-}" ]; then
        _cmd rm -rf -- "$state_dir"
    fi
    exit "$rc"
}

certbot_is_running() {
    jobs -pr | grep -Fx -- "$certbot_pid" >/dev/null
}

wait_for_hook_ready() {
    local elapsed=0

    while ((elapsed < hook_timeout)); do
        if [ -f "${state_dir}/ready" ]; then
            return 0
        fi
        if ! certbot_is_running; then
            wait "$certbot_pid" || true
            _error "Certbot finished before generating manual DNS challenge records"
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done

    _error "timed out waiting for Certbot to generate manual DNS challenge records"
}

show_challenges() {
    local record
    local validation
    local identifier

    _info "Add these DNS TXT records for certificate ${cert_name}:"
    while IFS=$'\t' read -r record validation identifier; do
        printf '  %s TXT "%s" for %s\n' "$record" "$validation" "$identifier"
    done <"${state_dir}/challenges.tsv"
    printf '\n'
}

wait_for_dns_records() {
    local record
    local validation
    local identifier
    local attempt
    local lookup_output

    while IFS=$'\t' read -r record validation identifier; do
        _info "Waiting for ${record} TXT for ${identifier}"
        attempt=1
        while ((attempt <= dns_wait_retries)); do
            lookup_output="$(nslookup -type=TXT "$record" 2>/dev/null || true)"
            if grep -F -- "$validation" <<<"$lookup_output" >/dev/null; then
                break
            fi
            sleep "$dns_wait_delay"
            attempt=$((attempt + 1))
        done
        if ((attempt > dns_wait_retries)); then
            _error "timed out waiting for ${record} TXT value ${validation}"
        fi
    done <"${state_dir}/challenges.tsv"
}

install_haproxy_pem() {
    local lineage_dir="/etc/letsencrypt/live/${cert_name}"
    local pem_path="${haproxy_cert_dir}/${cert_basename}"
    local tmp_file

    _cmd install -d -o haproxy -g haproxy -m 0755 "$haproxy_cert_dir"
    tmp_file="$(mktemp "${pem_path}.tmp.XXXXXX")"
    trap 'rm -f "$tmp_file"; cleanup' EXIT
    sed '/^$/d' "${lineage_dir}/privkey.pem" "${lineage_dir}/fullchain.pem" >"$tmp_file"
    _cmd chown haproxy:haproxy "$tmp_file"
    _cmd chmod 600 "$tmp_file"

    if [ -f "$pem_path" ] && cmp -s "$tmp_file" "$pem_path"; then
        _cmd rm -f "$tmp_file"
    else
        _cmd mv "$tmp_file" "$pem_path"
    fi
    trap cleanup EXIT

    _info "Installed HAProxy certificate: ${pem_path}"
}

cert_name=""
email=""
haproxy_cert_dir="$DEFAULT_HAPROXY_CERT_DIR"
state_root="$DEFAULT_STATE_ROOT"
domains=()

while [ "$#" -gt 0 ]; do
    case "$1" in
    --cert-name)
        [ "$#" -ge 2 ] || _usage_error "--cert-name requires a value"
        cert_name="$2"
        shift 2
        ;;
    --email)
        [ "$#" -ge 2 ] || _usage_error "--email requires a value"
        email="$2"
        shift 2
        ;;
    --domain | -d)
        [ "$#" -ge 2 ] || _usage_error "$1 requires a value"
        add_domain "$2"
        shift 2
        ;;
    --domains)
        [ "$#" -ge 2 ] || _usage_error "--domains requires a value"
        add_domains_arg "$2"
        shift 2
        ;;
    --haproxy-cert-dir)
        [ "$#" -ge 2 ] || _usage_error "--haproxy-cert-dir requires a value"
        haproxy_cert_dir="$2"
        shift 2
        ;;
    --state-root)
        [ "$#" -ge 2 ] || _usage_error "--state-root requires a value"
        state_root="$2"
        shift 2
        ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        _usage_error "unknown argument: $1"
        ;;
    esac
done

[ -n "$cert_name" ] || _usage_error "--cert-name is required"
[ -n "$email" ] || _usage_error "--email is required"
[ "${#domains[@]}" -gt 0 ] || _usage_error "at least one --domain is required"

_require_command certbot
_require_command md5sum
_require_command nslookup
_require_command openssl

auth_hook="${SCRIPT_DIR}/certbot_dns_auth"
cleanup_hook="${SCRIPT_DIR}/certbot_dns_cleanup"
[ -x "$auth_hook" ] || _error "auth hook is not executable: $auth_hook"
[ -x "$cleanup_hook" ] || _error "cleanup hook is not executable: $cleanup_hook"

mapfile -t sorted_domains < <(printf '%s\n' "${domains[@]}" | sort)
domain_arg="$(join_by_comma "${sorted_domains[@]}")"
cert_hash="$(printf '%s' "$domain_arg" | md5sum | awk '{ print $1 }')"
cert_basename="${cert_name}-${cert_hash}.pem"
state_dir="${state_root}/${cert_name}"
dns_wait_retries="${CERTBOT_DNS_WAIT_RETRIES:-120}"
dns_wait_delay="${CERTBOT_DNS_WAIT_DELAY:-10}"
hook_timeout="${CERTBOT_DNS_HOOK_TIMEOUT:-600}"
certbot_pid=""

_cmd install -d -m 0700 "$state_root"
_cmd rm -rf -- "$state_dir"
_cmd install -d -m 0700 "$state_dir"
trap cleanup EXIT

_cmd env CERTBOT_MANUAL_DNS_TIMEOUT="${CERTBOT_MANUAL_DNS_TIMEOUT:-3600}" certbot certonly \
    --non-interactive \
    --keep-until-expiring \
    --renew-with-new-domains \
    --agree-tos \
    --manual \
    --preferred-challenges=dns \
    --manual-auth-hook "${auth_hook} ${state_dir}" \
    --manual-cleanup-hook "${cleanup_hook} ${state_dir}" \
    --email "$email" \
    --cert-name "$cert_name" \
    --domains "$domain_arg" \
    --no-directory-hooks &
certbot_pid=$!

wait_for_hook_ready
show_challenges
read -r -p "Press ENTER after adding the DNS TXT records shown above: " _
wait_for_dns_records
_cmd touch "${state_dir}/continue"

if ! wait "$certbot_pid"; then
    certbot_pid=""
    _error "Certbot manual DNS request failed"
fi
certbot_pid=""

install_haproxy_pem
