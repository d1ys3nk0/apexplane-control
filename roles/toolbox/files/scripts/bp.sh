#!/usr/bin/env bash

set -euo pipefail

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
        printf 'No backup files found.\n'
        return 0
    fi

    for file in "${matches[@]}"; do
        case "$(basename "$file")" in
        ${pattern}.[0-9]*.[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]@[0-9][0-9]:[0-9][0-9]:[0-9][0-9]~)
            read -r -p "Delete '${file}'? [y/N] " answer
            case "$answer" in
            [Yy] | [Yy][Ee][Ss])
                rm -f -- "$file"
                printf 'Deleted: %s\n' "$file"
                ;;
            *)
                printf 'Skipped: %s\n' "$file"
                ;;
            esac
            ;;
        esac
    done
}

main "$@"
