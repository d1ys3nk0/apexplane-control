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
  docker_secret list <app>/<realm>/<environment>/<service>
  docker_secret read <app>/<realm>/<environment>/<service>[/<tag>]
  docker_secret prune [<app>[/<realm>[/<environment>[/<service>]]]]
  docker_secret help
  docker_secret -h
  docker_secret --help

Actions:
  view     Print the source secret JSON file.
  edit     Open the source secret JSON file in vi.
  push     Validate the source secret JSON with jq, then create a timestamped Docker secret.
  list     Print created Docker secret names for a target sorted ascending.
  read     Print the latest target Docker Swarm secret, or a specific secret when tag is provided.
  prune    Remove outdated timestamped managed Docker secrets, leaving only the latest version per prefix.

Target:
  Full target format:  <app>/<realm>/<environment>/<service>
  Secret read format:  <app>/<realm>/<environment>/<service> or <app>/<realm>/<environment>/<service>/<tag>
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
  docker_secret list app/eng/test01/api
  docker_secret read app/eng/test01/api
  docker_secret read app/eng/test01/api/260102030405
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

validate_docker_secret_name() {
    local secret_name="$1"
    local secret_name_regex='^[A-Za-z0-9][A-Za-z0-9_.-]*$'

    if [[ ! "${secret_name}" =~ ${secret_name_regex} ]]; then
        _die "Invalid Docker secret name '${secret_name}'"
    fi
}

validate_secret_tag() {
    local tag="$1"
    local tag_regex='^[A-Za-z0-9][A-Za-z0-9_.-]*$'

    if [[ ! "${tag}" =~ ${tag_regex} ]]; then
        _die "Invalid Docker secret tag '${tag}'"
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

parse_secret_read_target() {
    local target="$1"
    local extra

    IFS=/ read -r APP_NAME REALM ENVIRONMENT SERVICE SECRET_TAG extra <<<"${target}"
    if [ -z "${APP_NAME}" ] || [ -z "${REALM}" ] || [ -z "${ENVIRONMENT}" ] || [ -z "${SERVICE}" ] || [ -n "${extra}" ]; then
        _die "Invalid secret target '${target}'"
    fi

    validate_target_parts
    SECRET_PREFIX="${APP_NAME}-${REALM}-${ENVIRONMENT}-${SERVICE}"

    if [ -n "${SECRET_TAG}" ]; then
        validate_secret_tag "${SECRET_TAG}"
        SECRET_NAME="${SECRET_PREFIX}-${SECRET_TAG}"
    else
        SECRET_NAME=""
    fi
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

list_docker_secrets() {
    parse_full_target "$1"

    docker secret ls --format "{{.Name}}" | while IFS= read -r secret_name; do
        case "${secret_name}" in
        "${SECRET_PREFIX}-"*) printf '%s\n' "${secret_name}" ;;
        esac
    done | sort
}

cleanup_read_service() {
    if [ -n "${DOCKER_SECRET_READ_SERVICE_NAME:-}" ] && docker service inspect "${DOCKER_SECRET_READ_SERVICE_NAME}" >/dev/null 2>&1; then
        _info "Removing temporary Docker service: ${DOCKER_SECRET_READ_SERVICE_NAME}" >&2
        docker service rm "${DOCKER_SECRET_READ_SERVICE_NAME}" >/dev/null 2>&1 || true
    fi

    DOCKER_SECRET_READ_SERVICE_NAME=""
}

wait_read_service() {
    local service_name="$1"
    local timeout="${DOCKER_SECRET_READ_TIMEOUT:-60}"
    local elapsed=0
    local task_state

    _require_positive_integer "${timeout}" "DOCKER_SECRET_READ_TIMEOUT"

    while [ "${elapsed}" -lt "${timeout}" ]; do
        task_state="$(docker service ps --no-trunc --format "{{.CurrentState}}" "${service_name}" | head -n 1)"

        case "${task_state}" in
        Complete*) return 0 ;;
        Failed* | Rejected* | Shutdown*) _die "Temporary Docker service failed with state: ${task_state}" ;;
        esac

        sleep 1
        elapsed=$((elapsed + 1))
    done

    _die "Timed out waiting for temporary Docker service '${service_name}'"
}

read_docker_secret() {
    parse_secret_read_target "$1"

    local secret_name="${SECRET_NAME}"
    if [ -z "${secret_name}" ]; then
        secret_name="$(list_docker_secrets "$1" | tail -n 1)"
        if [ -z "${secret_name}" ]; then
            _die "No Docker secrets found for target '${1}'"
        fi
    fi

    validate_docker_secret_name "${secret_name}"

    if ! docker secret inspect "${secret_name}" >/dev/null 2>&1; then
        _die "Docker secret '${secret_name}' not found"
    fi

    local read_image="${DOCKER_SECRET_READ_IMAGE:-busybox:1.37.0}"
    local read_service_name
    read_service_name="toolbox-secret-read-$(date -u +'%y%m%d%H%M%S')-$$"

    DOCKER_SECRET_READ_SERVICE_NAME="${read_service_name}"
    trap 'cleanup_read_service' EXIT

    _info "Creating temporary Docker service: ${read_service_name}" >&2
    docker service create \
        --name "${read_service_name}" \
        --secret "source=${secret_name},target=secret" \
        --restart-condition none \
        --detach=true \
        "${read_image}" \
        sh -c 'cat /run/secrets/secret' >/dev/null

    wait_read_service "${read_service_name}"
    docker service logs --raw --no-trunc "${read_service_name}"
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
    list)
        [ "$#" -eq 2 ] || _usage_error "list requires exactly one target"
        list_docker_secrets "$2"
        ;;
    read)
        [ "$#" -eq 2 ] || _usage_error "read requires exactly one secret target"
        read_docker_secret "$2"
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
