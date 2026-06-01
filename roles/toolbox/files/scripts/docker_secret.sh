#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=../lib/helpers.sh
source "${SCRIPT_DIR}/../lib/helpers.sh"

usage() {
    cat <<'EOF'
Docker Secret Manager

Usage:
  docker_secret view <app>/<realm>/<environment>/<service>
  docker_secret edit <app>/<realm>/<environment>/<service>
  docker_secret push <app>/<realm>/<environment>/<service>
  docker_secret prune [<app>[/<realm>[/<environment>[/<service>]]]]
  docker_secret help
  docker_secret -h
  docker_secret --help

Actions:
  view     Print the source secret JSON file.
  edit     Open the source secret JSON file in vi.
  push     Validate the source secret JSON with jq, then create a timestamped Docker secret.
  prune    Remove outdated timestamped managed Docker secrets, leaving only the latest version per prefix.

Target:
  Full target format:  <app>/<realm>/<environment>/<service>
  Prune prefix:        omitted, <app>, <app>/<realm>, <app>/<realm>/<environment>, or full target

Remote paths and names:
  Source file:
    /home/<app>/secrets/<realm>_<environment>_<service>.json

  Docker secret:
    <app>-<realm>-<environment>-<service>-<SECVER>

Examples:
  docker_secret view app/eng/test01/api
  docker_secret edit app/eng/test01/api
  docker_secret push app/eng/test01/api
  docker_secret prune
  docker_secret prune app
  docker_secret prune app/eng
EOF
}

validate_slug() {
    local name="$1"
    local value="$2"
    local slug_regex='^[a-z][a-z0-9-]*$'

    if [[ ! "${value}" =~ ${slug_regex} ]]; then
        _die "Invalid ${name} '${value}'"
    fi
}

validate_target_parts() {
    validate_slug app "${APP_NAME}"
    validate_slug realm "${REALM}"
    validate_slug environment "${ENVIRONMENT}"
    validate_slug service "${SERVICE}"
}

parse_full_target() {
    local target="$1"
    local extra

    IFS=/ read -r APP_NAME REALM ENVIRONMENT SERVICE extra <<<"${target}"
    if [ -z "${APP_NAME}" ] || [ -z "${REALM}" ] || [ -z "${ENVIRONMENT}" ] || [ -z "${SERVICE}" ] || [ -n "${extra}" ]; then
        _die "Invalid target '${target}'"
    fi

    validate_target_parts

    SECRET_FILE="/home/${APP_NAME}/secrets/${REALM}_${ENVIRONMENT}_${SERVICE}.json"
    SECRET_PREFIX="${APP_NAME}-${REALM}-${ENVIRONMENT}-${SERVICE}"
}

parse_prune_prefix() {
    local target="${1:-}"
    local extra

    PRUNE_SECRET_PREFIX=""
    if [ -z "${target}" ]; then
        return 0
    fi

    IFS=/ read -r APP_NAME REALM ENVIRONMENT SERVICE extra <<<"${target}"
    if [ -z "${APP_NAME}" ] || [ -n "${extra}" ]; then
        _die "Invalid prune prefix '${target}'"
    fi

    validate_slug app "${APP_NAME}"
    PRUNE_SECRET_PREFIX="${APP_NAME}-"

    if [ -n "${REALM}" ]; then
        validate_slug realm "${REALM}"
        PRUNE_SECRET_PREFIX="${PRUNE_SECRET_PREFIX}${REALM}-"
    fi

    if [ -n "${ENVIRONMENT}" ]; then
        validate_slug environment "${ENVIRONMENT}"
        PRUNE_SECRET_PREFIX="${PRUNE_SECRET_PREFIX}${ENVIRONMENT}-"
    fi

    if [ -n "${SERVICE}" ]; then
        validate_slug service "${SERVICE}"
        PRUNE_SECRET_PREFIX="${PRUNE_SECRET_PREFIX}${SERVICE}-"
    fi
}

require_file() {
    local file_path="$1"

    if [ ! -f "${file_path}" ]; then
        _die "File '${file_path}' not found"
    fi

    if [ ! -r "${file_path}" ]; then
        _die "File '${file_path}' is not readable"
    fi
}

docker_secret_exists() {
    local secret_name="$1"

    docker secret ls --format "{{.Name}}" | grep -Fxq "${secret_name}"
}

is_docker_secret_name() {
    local secret_name="$1"
    local secret_regex='^[a-z][a-z0-9-]*-[a-z][a-z0-9-]*-[a-z][a-z0-9-]*-[a-z][a-z0-9-]*-[0-9]{12}$'

    [[ "${secret_name}" =~ ${secret_regex} ]]
}

matches_prune_prefix() {
    local secret_name="$1"

    if [ -z "${PRUNE_SECRET_PREFIX}" ]; then
        return 0
    fi

    case "${secret_name}" in
    "${PRUNE_SECRET_PREFIX}"*) return 0 ;;
    *) return 1 ;;
    esac
}

secret_prefix_without_timestamp() {
    local secret_name="$1"
    local timestamp="${secret_name##*-}"
    local prefix="${secret_name%-"${timestamp}"}"

    printf '%s\n' "${prefix}"
}

view_secret_file() {
    parse_full_target "$1"
    require_file "${SECRET_FILE}"

    cat "${SECRET_FILE}"
}

edit_secret_file() {
    parse_full_target "$1"

    vi "${SECRET_FILE}"
}

push_secret() {
    parse_full_target "$1"
    require_file "${SECRET_FILE}"

    _cmd_output /dev/null jq -e . "${SECRET_FILE}"

    local secver="${SECVER:-}"
    local force_mode=false
    if [ -z "${secver}" ]; then
        secver="$(date -u +'%y%m%d%H%M%S')"
    else
        force_mode=true
    fi

    local secret_name="${SECRET_PREFIX}-${secver}"

    if [ "${force_mode}" = true ] && docker_secret_exists "${secret_name}"; then
        _info "Secret '${secret_name}' already exists. Deleting it before creating a new one..."
        _cmd_output /dev/null docker secret rm "${secret_name}"
    fi

    _info "Creating Docker secret: ${secret_name}"
    local secret_id
    secret_id="$(docker secret create "${secret_name}" "${SECRET_FILE}")"
    _info "Successfully created secret: ${secret_name}:${secret_id}"
    printf '%s\n' "${secret_name}"
}

prune_secrets() {
    local target="${1:-}"
    parse_prune_prefix "${target}"

    local temp_dir
    temp_dir="$(mktemp -d)"
    DOCKER_SECRET_PRUNE_TEMP_DIR="${temp_dir}"
    trap 'rm -rf "${DOCKER_SECRET_PRUNE_TEMP_DIR:-}"' RETURN

    local candidate_file="${temp_dir}/candidates"
    local sorted_file="${temp_dir}/sorted"
    local kept_file="${temp_dir}/kept"

    docker secret ls --format "{{.Name}}" | while IFS= read -r secret_name; do
        if is_docker_secret_name "${secret_name}" && matches_prune_prefix "${secret_name}"; then
            printf '%s\n' "${secret_name}"
        fi
    done >"${candidate_file}"

    if [ ! -s "${candidate_file}" ]; then
        _info "No managed Docker secrets found for pruning."
        return 0
    fi

    sort -r "${candidate_file}" >"${sorted_file}"
    : >"${kept_file}"

    local removed_count=0
    local kept_count=0
    local secret_name
    while IFS= read -r secret_name; do
        local secret_prefix
        secret_prefix="$(secret_prefix_without_timestamp "${secret_name}")"

        if grep -Fxq "${secret_prefix}" "${kept_file}"; then
            _info "Removing outdated Docker secret: ${secret_name}"
            _cmd_output /dev/null docker secret rm "${secret_name}"
            removed_count=$((removed_count + 1))
        else
            printf '%s\n' "${secret_prefix}" >>"${kept_file}"
            _info "Keeping latest Docker secret: ${secret_name}"
            kept_count=$((kept_count + 1))
        fi
    done <"${sorted_file}"

    _info "Prune completed. Kept ${kept_count} latest secret(s); removed ${removed_count} outdated secret(s)."
}

main() {
    local action="${1:-}"

    case "${action}" in
    view)
        [ "$#" -eq 2 ] || _die "view requires exactly one target"
        view_secret_file "$2"
        ;;
    edit)
        [ "$#" -eq 2 ] || _die "edit requires exactly one target"
        edit_secret_file "$2"
        ;;
    push)
        [ "$#" -eq 2 ] || _die "push requires exactly one target"
        push_secret "$2"
        ;;
    prune)
        [ "$#" -le 2 ] || _die "prune accepts at most one prefix"
        prune_secrets "${2:-}"
        ;;
    help | -h | --help)
        usage
        ;;
    "")
        usage
        exit 1
        ;;
    *)
        _die "Invalid action '${action}'"
        ;;
    esac
}

main "$@"
