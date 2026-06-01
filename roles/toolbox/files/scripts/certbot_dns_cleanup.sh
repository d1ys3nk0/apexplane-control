#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=../lib/helpers.sh
source "${SCRIPT_DIR}/../lib/helpers.sh"

state_dir="${1:?state directory is required}"
_cmd mkdir -p "$state_dir"
_cmd chmod 700 "$state_dir"
umask 077

printf '%s\t%s\n' "${CERTBOT_IDENTIFIER:-unknown}" "${CERTBOT_VALIDATION:-unknown}" >>"${state_dir}/cleanups.tsv"
