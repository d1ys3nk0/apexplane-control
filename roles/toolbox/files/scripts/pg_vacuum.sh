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

_require_pg_connection_vars
_require_vars "PG_BASE"

_info "Performing vacuum for ${PG_BASE}"
_pg_psql_cmd -d "${PG_BASE}" -c "ALTER ROLE ${PG_USER} SET statement_timeout = 300000"

_pg_vacuumdb_cmd -d "${PG_BASE}" --echo --analyze-in-stages -j4

_pg_psql_cmd -d "${PG_BASE}" -c "ALTER ROLE ${PG_USER} RESET statement_timeout"
_info "Done!"
