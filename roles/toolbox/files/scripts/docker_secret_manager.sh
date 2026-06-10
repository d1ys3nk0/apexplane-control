#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=../lib/helpers.sh
source "${SCRIPT_DIR}/../lib/helpers.sh"

usage() {
    cat <<'EOF'
usage:
  docker_secret_manager upsert --prefix <secret-prefix> --file <dotenv-file> [--check]
  docker_secret_manager read <secret-name> [--image <image>] [--timeout <seconds>]
  docker_secret_manager prune --prefix <secret-prefix> [--check]

Create a versioned Docker secret named <prefix>-<YYMMDDHHMMSS>-<hash>.
The hash is the first 12 characters of the dotenv file SHA-256 digest.
EOF
}

versioned_secret_names() {
    local prefix="$1"

    _docker secret ls --format '{{.Name}}' |
        awk -v prefix="${prefix}" '
            function valid_timetag(value) { return value ~ /^[0-9]{12}$/ }
            function valid_hash(value) { return value ~ /^[0-9a-f]{12}$/ }
            {
                prefix_part = prefix "-"
                if (substr($0, 1, length(prefix_part)) != prefix_part) next
                suffix = substr($0, length(prefix_part) + 1)
                part_count = split(suffix, parts, "-")
                if (length(suffix) != 25 || part_count != 2) next
                if (valid_timetag(parts[1]) && valid_hash(parts[2])) print $0
            }
        ' |
        sort
}

latest_secret_name() {
    local prefix="$1"

    versioned_secret_names "${prefix}" | tail -n 1
}

require_secret_prefix() {
    local prefix="$1"

    if [ -z "${prefix}" ]; then
        _usage_error "docker_secret_manager: --prefix is required"
    fi
    if [[ ! "${prefix}" =~ ^[A-Za-z0-9_.-]+$ ]]; then
        _usage_error "docker_secret_manager: --prefix may contain only letters, numbers, dot, underscore, and hyphen"
    fi
}

upsert_secret() {
    local check=0
    local file=""
    local hash
    local latest_hash
    local latest_name
    local name
    local prefix=""
    local timetag

    while [ "$#" -gt 0 ]; do
        case "$1" in
        --prefix)
            prefix="${2:-}"
            shift 2
            ;;
        --file)
            file="${2:-}"
            shift 2
            ;;
        --check)
            check=1
            shift
            ;;
        -h | --help)
            usage
            return 0
            ;;
        *)
            _usage_error "docker_secret_manager: unknown argument: $1"
            ;;
        esac
    done

    require_secret_prefix "${prefix}"
    if [ -z "${file}" ]; then
        _usage_error "docker_secret_manager: --file is required"
    fi
    if [ ! -f "${file}" ]; then
        _error "docker_secret_manager: file is not found: ${file}"
    fi

    hash="$(sha256sum "${file}" | awk '{ print substr($1, 1, 12) }')"
    latest_name="$(latest_secret_name "${prefix}")"
    latest_hash="${latest_name##*-}"

    if [ -n "${latest_name}" ] && [ "${latest_hash}" = "${hash}" ]; then
        printf 'status=existing name=%s\n' "${latest_name}"
        return 0
    fi

    timetag="$(date -u +%y%m%d%H%M%S)"
    name="${prefix}-${timetag}-${hash}"

    if [ "${check}" -eq 1 ]; then
        printf 'status=would-create name=%s\n' "${name}"
        return 0
    fi

    _docker secret create "${name}" "${file}" >/dev/null
    printf 'status=created name=%s\n' "${name}"
}

read_secret() {
    local completed=0
    local image="${DOCKER_SECRET_READ_IMAGE:-alpine:3.20}"
    local secret_name=""
    local service_name
    local state
    local status
    local timeout=60
    local wait_remaining

    while [ "$#" -gt 0 ]; do
        case "$1" in
        --image)
            image="${2:-}"
            shift 2
            ;;
        --timeout)
            timeout="${2:-}"
            shift 2
            ;;
        -h | --help)
            usage
            return 0
            ;;
        --*)
            _usage_error "docker_secret_manager: unknown argument: $1"
            ;;
        *)
            if [ -n "${secret_name}" ]; then
                _usage_error "docker_secret_manager: read accepts exactly one secret name"
            fi
            secret_name="$1"
            shift
            ;;
        esac
    done

    if [ -z "${secret_name}" ]; then
        _usage_error "docker_secret_manager: read requires a secret name"
    fi
    if [ -z "${image}" ]; then
        _usage_error "docker_secret_manager: --image cannot be empty"
    fi
    _require_positive_integer "${timeout}" "--timeout"

    service_name="toolbox-secret-read-$(date +%s)-$$"

    _docker secret inspect "${secret_name}" >/dev/null

    _docker service create \
        --detach=true \
        --name "${service_name}" \
        --restart-condition none \
        --secret "source=${secret_name},target=secret,mode=0400" \
        "${image}" \
        cat /run/secrets/secret >/dev/null

    for ((wait_remaining = timeout; wait_remaining > 0; wait_remaining--)); do
        state="$(_docker service ps --no-trunc --format '{{.CurrentState}}' "${service_name}" | head -n 1)"
        case "${state}" in
        Complete*)
            completed=1
            break
            ;;
        Failed* | Rejected*)
            _docker service logs --raw "${service_name}" 2>/dev/null
            _docker service rm "${service_name}" >/dev/null
            return 1
            ;;
        esac
        sleep 1
    done

    if [ "${completed}" -ne 1 ]; then
        printf 'docker_secret_manager: service did not complete within %s seconds: %s\n' "${timeout}" "${state:-unknown}" >&2
        _docker service logs --raw "${service_name}" 2>/dev/null
        _docker service rm "${service_name}" >/dev/null
        return 1
    fi

    _docker service logs --raw "${service_name}"
    status=$?
    _docker service rm "${service_name}" >/dev/null
    return "${status}"
}

prune_secrets() {
    local check=0
    local latest_name
    local prefix=""
    local pruned=0
    local secret_name
    local secret_names=()

    while [ "$#" -gt 0 ]; do
        case "$1" in
        --prefix)
            prefix="${2:-}"
            shift 2
            ;;
        --check)
            check=1
            shift
            ;;
        -h | --help)
            usage
            return 0
            ;;
        *)
            _usage_error "docker_secret_manager: unknown argument: $1"
            ;;
        esac
    done

    require_secret_prefix "${prefix}"
    mapfile -t secret_names < <(versioned_secret_names "${prefix}")

    if [ "${#secret_names[@]}" -le 1 ]; then
        printf 'status=noop prefix=%s count=0\n' "${prefix}"
        return 0
    fi

    latest_name="${secret_names[$((${#secret_names[@]} - 1))]}"
    for secret_name in "${secret_names[@]}"; do
        if [ "${secret_name}" = "${latest_name}" ]; then
            continue
        fi

        if [ "${check}" -eq 1 ]; then
            printf 'status=would-prune name=%s\n' "${secret_name}"
        else
            _docker secret rm "${secret_name}" >/dev/null
            printf 'status=pruned name=%s\n' "${secret_name}"
        fi
        pruned=$((pruned + 1))
    done
    printf 'status=%s prefix=%s latest=%s count=%s\n' "$([ "${check}" -eq 1 ] && printf would-prune || printf pruned)" "${prefix}" "${latest_name}" "${pruned}"
}

main() {
    local command="${1:-}"

    case "${command}" in
    upsert)
        shift
        _require_command docker
        _require_command sha256sum
        _require_command awk
        _require_command date
        upsert_secret "$@"
        ;;
    read)
        shift
        _require_command docker
        _require_command date
        read_secret "$@"
        ;;
    prune)
        shift
        _require_command docker
        _require_command awk
        prune_secrets "$@"
        ;;
    -h | --help)
        usage
        ;;
    "")
        _usage_error "docker_secret_manager: command is required"
        ;;
    *)
        _usage_error "docker_secret_manager: unknown command: ${command}"
        ;;
    esac
}

main "$@"
