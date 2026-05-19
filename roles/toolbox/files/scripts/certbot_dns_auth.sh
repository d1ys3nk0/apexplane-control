#!/usr/bin/env bash

set -euo pipefail

state_dir="${1:?state directory is required}"
mkdir -p "$state_dir"
chmod 700 "$state_dir"
umask 077

identifier="${CERTBOT_IDENTIFIER:?CERTBOT_IDENTIFIER is required}"
validation="${CERTBOT_VALIDATION:?CERTBOT_VALIDATION is required}"
remaining="${CERTBOT_REMAINING_CHALLENGES:-0}"
dns_identifier="$identifier"
if [[ "$dns_identifier" == \*.* ]]; then
    dns_identifier="${dns_identifier#\*.}"
fi
record_name="_acme-challenge.${dns_identifier}"

challenge_file="${state_dir}/challenges.tsv"
lock_dir="${state_dir}/lock"
while ! mkdir "$lock_dir" 2>/dev/null; do
    sleep 0.2
done
trap 'rmdir "$lock_dir"' EXIT
printf '%s\t%s\t%s\n' "$record_name" "$validation" "$identifier" >>"$challenge_file"
sort -u -o "$challenge_file" "$challenge_file"
rmdir "$lock_dir"
trap - EXIT

if [[ "$remaining" == "0" ]]; then
    touch "${state_dir}/ready"
    timeout="${CERTBOT_MANUAL_DNS_TIMEOUT:-3600}"
    elapsed=0
    while [[ ! -f "${state_dir}/continue" ]]; do
        if ((elapsed >= timeout)); then
            echo "Timed out waiting for manual dns approval for ${identifier}" >&2
            exit 1
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
fi
