#!/usr/bin/env bash

set -euo pipefail

error() {
    echo "[ERROR] $*" >&2
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

check "PG_IMAGE" "PG_HOST" "PG_PORT" "PG_USER" "PG_PASS" "PG_BASE"

psql() {
    sudo docker run --rm --network host -e "PGPASSWORD=${PG_PASS}" -e "PGSSLMODE=${PG_SSL:-disable}" "${PG_IMAGE}" psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" "$@"
}

run_vacuumdb() {
    sudo docker run --rm --network host -e "PGPASSWORD=${PG_PASS}" -e "PGSSLMODE=${PG_SSL:-disable}" "${PG_IMAGE}" vacuumdb -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" "$@"
}

echo "Performing vacuum for ${PG_BASE}"
psql -d "${PG_BASE}" -c "ALTER ROLE ${PG_USER} SET statement_timeout = 300000"

run_vacuumdb -d "${PG_BASE}" --echo --analyze-in-stages -j4

psql -d "${PG_BASE}" -c "ALTER ROLE ${PG_USER} RESET statement_timeout"
echo "Done!"
