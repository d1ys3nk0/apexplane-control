#!/usr/bin/env bash

TOOLBOX_SCRIPT_START="${TOOLBOX_SCRIPT_START:-$(date -u '+%s.%3N')}"
TOOLBOX_REDACT_VARS="${TOOLBOX_REDACT_VARS:-}"

if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    TOOLBOX_COLOR_INFO=$(tput setaf 4)
    TOOLBOX_COLOR_WARN=$(tput setaf 3)
    TOOLBOX_COLOR_COMMAND=$(tput setaf 2)
    TOOLBOX_COLOR_ERROR=$(tput setaf 1)
    TOOLBOX_COLOR_RESET=$(tput sgr0)
else
    TOOLBOX_COLOR_INFO=""
    TOOLBOX_COLOR_WARN=""
    TOOLBOX_COLOR_COMMAND=""
    TOOLBOX_COLOR_ERROR=""
    TOOLBOX_COLOR_RESET=""
fi

_elapsed() {
    local now

    now=$(date -u '+%s.%3N')
    awk -v now="${now}" -v start="${TOOLBOX_SCRIPT_START}" 'BEGIN { printf "%.3f", now - start }'
}

_log() {
    local color="$1"
    shift

    printf '%s%s %s%s\n' "${color}" "$(_elapsed)" "$*" "${TOOLBOX_COLOR_RESET}"
}

_is_quiet() {
    case "${QUIET:-}" in
    1 | true | True | TRUE) return 0 ;;
    *) return 1 ;;
    esac
}

_info() {
    if _is_quiet; then
        return 0
    fi

    _log "${TOOLBOX_COLOR_INFO}" "> $*"
}

_warn() {
    if _is_quiet; then
        return 0
    fi

    _log "${TOOLBOX_COLOR_WARN}" "> $*"
}

_error() {
    _log "${TOOLBOX_COLOR_ERROR}" "! $*" >&2
    exit 1
}

_die() {
    _error "$*"
}

_usage_error() {
    _log "${TOOLBOX_COLOR_ERROR}" "! $*" >&2
    printf '\n' >&2
    usage >&2
    exit 2
}

_redact_log_arg() {
    local arg="$1"
    local secret_var

    for secret_var in ${TOOLBOX_REDACT_VARS}; do
        if [ -n "${!secret_var:-}" ]; then
            arg="${arg//${!secret_var}/***}"
        fi
    done

    printf '%s' "${arg}"
}

_format_command() {
    local arg
    local rendered=()

    for arg in "$@"; do
        arg="$(_redact_log_arg "${arg}")"
        rendered+=("$(printf '%q' "${arg}")")
    done

    printf '%s' "${rendered[*]}"
}

_cmd() {
    if ! _is_quiet; then
        _log "${TOOLBOX_COLOR_COMMAND}" "# $(_format_command "$@")"
    fi

    "$@"
}

_cmd_output() {
    local output="$1"
    shift

    if ! _is_quiet; then
        _log "${TOOLBOX_COLOR_COMMAND}" "# $(_format_command "$@") > $(printf '%q' "${output}")"
    fi

    "$@" >"${output}"
}

_require_vars() {
    local var

    for var in "$@"; do
        if [ -z "${!var:-}" ]; then
            _error "${var} is not set"
        fi
    done
}

_require_command() {
    command -v "$1" >/dev/null 2>&1 || _error "missing required command: $1"
}

_require_positive_integer() {
    if [[ ! "${1}" =~ ^[1-9][0-9]*$ ]]; then
        _usage_error "${2} must be a positive integer"
    fi
}

_is_true() {
    case "${1}" in
    1 | true | True | TRUE) return 0 ;;
    "" | 0 | false | False | FALSE) return 1 ;;
    *) _usage_error "${2} must be true or false" ;;
    esac
}

_require_pg_connection_vars() {
    _require_vars "PG_IMAGE" "PG_HOST" "PG_PORT" "PG_USER" "PG_PASS"
}

_docker_postgres() {
    sudo docker run --rm --network host -e "PGPASSWORD=${PG_PASS}" -e "PGSSLMODE=${PG_SSL:-disable}" "${PG_IMAGE}" "$@"
}
