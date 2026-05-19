#!/usr/bin/env bash

# shellcheck disable=SC1090

set -euo pipefail

DOTENV_FILES="${1:-}"

usage() {
    printf 'Usage: %s <dotenv-file[:dotenv-file...]> <command> [args...]\n' "$(basename "$0")" >&2
    exit 1
}

if [[ -z "${DOTENV_FILES}" ]]; then
    usage
fi

shift

if [[ "$#" -eq 0 ]]; then
    printf 'Command is empty\n' >&2
    usage
fi

if [[ "${DOTENV_FILES}" == :* || "${DOTENV_FILES}" == *: || "${DOTENV_FILES}" == *::* ]]; then
    printf 'Dotenv file path is empty\n' >&2
    usage
fi

IFS=':' read -r -a DOTENV_FILE_LIST <<<"${DOTENV_FILES}"

for DOTENV_FILE in "${DOTENV_FILE_LIST[@]}"; do
    case "${DOTENV_FILE}" in
    /*) ;;
    *) DOTENV_FILE="${PWD}/${DOTENV_FILE}" ;;
    esac

    if [[ ! -f "${DOTENV_FILE}" ]]; then
        printf 'File %s is not found\n' "${DOTENV_FILE}" >&2
        exit 1
    fi

    set -a
    source "${DOTENV_FILE}"
    set +a
done

exec env -- "$@"
