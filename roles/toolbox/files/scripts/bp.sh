#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=../lib/helpers.sh
source "${SCRIPT_DIR}/../lib/helpers.sh"

main() {
    local target="${1:-}"
    local dir pattern file answer
    local -a matches=()

    if [ "$#" -ne 1 ] || [ -z "$target" ]; then
        printf 'Usage: bp <file-or-directory-path>\n' >&2
        return 1
    fi

    if [[ -d "$target" ]]; then
        dir="$target"
        pattern='*'
    else
        dir="$(dirname "$target")"
        pattern="$(basename "$target")"
    fi

    while IFS= read -r -d '' file; do
        matches+=("$file")
    done < <(
        find "$dir" -maxdepth 1 -type f -name "${pattern}.*~" -print0 | sort -z
    )

    if [ "${#matches[@]}" -eq 0 ]; then
        _info "No backup files found."
        return 0
    fi

    for file in "${matches[@]}"; do
        case "$(basename "$file")" in
        ${pattern}.[0-9]*.[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]@[0-9][0-9]:[0-9][0-9]:[0-9][0-9]~)
            read -r -p "Delete '${file}'? [y/N] " answer
            case "$answer" in
            [Yy] | [Yy][Ee][Ss])
                _cmd rm -f -- "$file"
                _info "Deleted: ${file}"
                ;;
            *)
                _info "Skipped: ${file}"
                ;;
            esac
            ;;
        esac
    done
}

main "$@"
