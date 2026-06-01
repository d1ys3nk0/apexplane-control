#!/usr/bin/env bash

# shellcheck disable=SC1090

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=../lib/helpers.sh
source "${SCRIPT_DIR}/../lib/helpers.sh"

DOTENV_FILES="${1:-}"

usage() {
    printf 'Usage: %s <dotenv-file[:dotenv-file...]> <command> [args...]\n' "$(basename "$0")" >&2
}

if [[ -z "${DOTENV_FILES}" ]]; then
    usage
    exit 1
fi

shift

if [[ "$#" -eq 0 ]]; then
    _usage_error "Command is empty"
fi

if [[ "${DOTENV_FILES}" == :* || "${DOTENV_FILES}" == *: || "${DOTENV_FILES}" == *::* ]]; then
    _usage_error "Dotenv file path is empty"
fi

IFS=':' read -r -a DOTENV_FILE_LIST <<<"${DOTENV_FILES}"

for DOTENV_FILE in "${DOTENV_FILE_LIST[@]}"; do
    case "${DOTENV_FILE}" in
    /*) ;;
    *) DOTENV_FILE="${PWD}/${DOTENV_FILE}" ;;
    esac

    if [[ ! -f "${DOTENV_FILE}" ]]; then
        _error "File ${DOTENV_FILE} is not found"
    fi

    set -a
    source "${DOTENV_FILE}"
    set +a
done

exec env -- "$@"
