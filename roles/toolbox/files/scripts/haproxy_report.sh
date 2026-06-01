#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=../lib/helpers.sh
source "${SCRIPT_DIR}/../lib/helpers.sh"

DEFAULT_LOG_FILE="/var/log/haproxy/traffic.log"

usage() {
    cat <<'EOF'
Usage: haproxy_report [log-file-or-glob ...]

Reports HAProxy request counts per effective client IP from traffic logs.
Defaults to /var/log/haproxy/traffic.log.

Examples:
  haproxy_report
  haproxy_report /var/log/haproxy/traffic.log /var/log/haproxy/traffic.log.1
  haproxy_report '/var/log/haproxy/traffic.log*'
EOF
}

expand_inputs() {
    local input
    local match

    for input in "$@"; do
        if compgen -G "$input" >/dev/null; then
            while IFS= read -r match; do
                printf '%s\n' "$match"
            done < <(compgen -G "$input")
        else
            printf '%s\n' "$input"
        fi
    done
}

read_log_file() {
    local path="$1"

    case "$path" in
    *.gz)
        zcat -f -- "$path"
        ;;
    *)
        cat -- "$path"
        ;;
    esac
}

main() {
    local inputs=()
    local paths=()
    local readable_paths=()
    local path

    if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
        usage
        return 0
    fi

    if [ "$#" -eq 0 ]; then
        inputs=("$DEFAULT_LOG_FILE")
    else
        inputs=("$@")
    fi

    while IFS= read -r path; do
        paths+=("$path")
    done < <(expand_inputs "${inputs[@]}")
    for path in "${paths[@]}"; do
        if [ -f "$path" ] && [ -r "$path" ]; then
            readable_paths+=("$path")
        fi
    done

    if [ "${#readable_paths[@]}" -eq 0 ]; then
        printf 'haproxy_report: no readable log files found\n' >&2
        return 1
    fi

    {
        for path in "${readable_paths[@]}"; do
            read_log_file "$path"
        done
    } | awk '
        {
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^s=/) {
                    source = substr($i, 3)
                    sub(/:[0-9]+$/, "", source)
                    if (source != "") {
                        requests[source]++
                    }
                    break
                }
            }
        }
        END {
            for (source in requests) {
                printf "%d %s\n", requests[source], source
            }
        }
    ' | sort -k1,1nr -k2,2 | awk 'BEGIN { printf "%-8s %s\n", "REQUESTS", "IP" } { printf "%-8s %s\n", $1, $2 }'
}

main "$@"
