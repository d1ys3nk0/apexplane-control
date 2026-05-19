#!/usr/bin/env bash

set -euo pipefail

state_dir="${1:?state directory is required}"
mkdir -p "$state_dir"
chmod 700 "$state_dir"
umask 077

printf '%s\t%s\n' "${CERTBOT_IDENTIFIER:-unknown}" "${CERTBOT_VALIDATION:-unknown}" >>"${state_dir}/cleanups.tsv"
