#!/usr/bin/env bash

set -euo pipefail

error() {
    echo "[ERROR] $*"
    exit 1
}

check() {
    local arg

    for arg in "$@"; do
        if [ -z "${!arg:-}" ]; then
            error "${arg} is not set"
        fi
    done
}

PG_IMAGE="${PG_IMAGE:-}"
PG_HOST="${PG_HOST:-}"
PG_PORT="${PG_PORT:-}"
PG_USER="${PG_USER:-}"
PG_PASS="${PG_PASS:-}"
PG_BASE="${PG_BASE:-}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PSQLRC="${PWD}/psqlrc"

check "PG_IMAGE" "PG_HOST" "PG_PORT" "PG_USER" "PG_PASS" "PG_BASE"

if [ ! -f "${PSQLRC}" ]; then
    PSQLRC="${SCRIPT_DIR}/psqlrc"
fi

sudo docker run \
    --rm \
    --network host \
    -it \
    -v "${PSQLRC}:/var/lib/postgresql/.psqlrc:ro" \
    -e "PGPASSWORD=${PG_PASS}" \
    -e "PGSSLMODE=${PG_SSL:-disable}" \
    "${PG_IMAGE}" \
    psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${PG_BASE}" "$@"
