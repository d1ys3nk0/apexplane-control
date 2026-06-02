#!/bin/sh

exec 1>&2

check_only=1
while [ "$#" -gt 0 ]; do
    case "$1" in
    --fix)
        check_only=0
        shift
        ;;
    --check)
        check_only=1
        shift
        ;;
    *)
        break
        ;;
    esac
done

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

collect_candidate() {
    file="$1"
    [ -f "$file" ] || return 0
    case "$file" in
    */_vault.yml) ;;
    *) return 0 ;;
    esac

    first_line=$(head -1 "$file" 2>/dev/null)
    case "$first_line" in
    \$ANSIBLE_VAULT*) ;;
    *) echo "$file" >>"$tmp" ;;
    esac
}

if [ "$#" -gt 0 ]; then
    for file in "$@"; do
        collect_candidate "$file"
    done
else
    find . \( -path './.*' -prune \) -o -name '_vault.yml' -type f -print 2>/dev/null | while IFS= read -r file; do
        collect_candidate "$file"
    done
fi

[ ! -s "$tmp" ] && exit 0

if [ "$check_only" -eq 1 ]; then
    echo "Unencrypted vault files (encrypt with ansible-vault or task enc):"
    while IFS= read -r f; do
        echo "  $f"
    done <"$tmp"
    exit 1
fi

echo "Encrypting unencrypted vault files..."
while IFS= read -r f; do
    [ -f "$f" ] || continue
    first_line=$(head -1 "$f" 2>/dev/null)
    case "$first_line" in
    \$ANSIBLE_VAULT*) continue ;;
    esac
    echo "  $f"
    encrypt_rc=0
    encrypt_out=$(uv run ansible-vault encrypt "$f" 2>&1) || encrypt_rc=$?
    if [ "$encrypt_rc" -ne 0 ]; then
        first_line=$(head -1 "$f" 2>/dev/null)
        case "$first_line" in
        \$ANSIBLE_VAULT*) ;;
        *)
            printf '%s\n' "$encrypt_out" >&2
            exit 1
            ;;
        esac
    fi
done <"$tmp"
exit 0
