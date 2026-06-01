#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
TOOLBOX_REDACT_VARS="PG_PASS"
# shellcheck source=../lib/helpers.sh
source "${SCRIPT_DIR}/../lib/helpers.sh"

PG_IMAGE="${PG_IMAGE:-}"
PG_HOST="${PG_HOST:-}"
PG_PORT="${PG_PORT:-}"
PG_USER="${PG_USER:-}"
PG_PASS="${PG_PASS:-}"
PG_BASE="${PG_BASE:-}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PSQLRC="${PWD}/psqlrc"

_require_vars "PG_IMAGE" "PG_HOST" "PG_PORT" "PG_USER" "PG_PASS" "PG_BASE"

if [ ! -f "${PSQLRC}" ]; then
    PSQLRC="${SCRIPT_DIR}/psqlrc"
fi

_cmd sudo docker run \
    --rm \
    --network host \
    -it \
    -v "${PSQLRC}:/var/lib/postgresql/.psqlrc:ro" \
    -e "PGPASSWORD=${PG_PASS}" \
    -e "PGSSLMODE=${PG_SSL:-disable}" \
    "${PG_IMAGE}" \
    psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${PG_BASE}" "$@"
