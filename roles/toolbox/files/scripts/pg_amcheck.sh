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

_info "Creating amcheck extension"
_pg_psql_cmd -d "${PG_BASE}" -c "CREATE EXTENSION IF NOT EXISTS amcheck"

_info "Performing amcheck database ${PG_BASE}"
_pg_psql_cmd -d "${PG_BASE}" -c "ALTER ROLE ${PG_USER} SET statement_timeout = 300000"

_info "Performing lightweight B-tree index checks for ${PG_BASE}"
_pg_psql_cmd -d "${PG_BASE}" -c "
SELECT
    schemaname,
    relname as tablename,
    indexrelname as indexname,
    bt_index_check(indexrelid) as check_result
FROM pg_stat_user_indexes
WHERE schemaname != 'information_schema' AND schemaname NOT LIKE 'pg_%'
ORDER BY schemaname, relname, indexrelname;
"

_info "Performing thorough B-tree index checks with heap verification..."
_pg_psql_cmd -d "${PG_BASE}" -c "
DO \$\$
DECLARE
    idx_record RECORD;
    check_result TEXT;
BEGIN
    FOR idx_record IN
        SELECT schemaname, relname as tablename, indexrelname as indexname, indexrelid
        FROM pg_stat_user_indexes
        WHERE schemaname != 'information_schema' AND schemaname NOT LIKE 'pg_%'
        ORDER BY schemaname, relname, indexrelname
    LOOP
        BEGIN
            RAISE NOTICE 'Checking index: %.%.%', idx_record.schemaname, idx_record.tablename, idx_record.indexname;
            SELECT bt_index_check(idx_record.indexrelid, true) INTO check_result;
            RAISE NOTICE 'Index %.%.% - OK', idx_record.schemaname, idx_record.tablename, idx_record.indexname;
        EXCEPTION
            WHEN OTHERS THEN
                RAISE WARNING 'Index %.%.% - ERROR: %', idx_record.schemaname, idx_record.tablename, idx_record.indexname, SQLERRM;
        END;
    END LOOP;
END
\$\$;
"

_info "Checking for potential duplicate indexes..."
_pg_psql_cmd -d "${PG_BASE}" -c "
SELECT
    t.schemaname,
    t.tablename,
    array_agg(t.indexname ORDER BY t.indexname) as duplicate_indexes,
    array_agg(t.indexdef ORDER BY t.indexname) as index_definitions
FROM (
    SELECT
        pi.schemaname,
        pi.tablename,
        pi.indexname,
        pi.indexdef,
        array_to_string(array_agg(pa.attname ORDER BY pa.attnum), ',') as columns
    FROM pg_indexes pi
    JOIN pg_index pgi ON pgi.indexrelid = (pi.schemaname||'.'||pi.indexname)::regclass
    JOIN pg_attribute pa ON pa.attrelid = pgi.indrelid AND pa.attnum = ANY(pgi.indkey)
    WHERE pi.schemaname != 'information_schema' AND pi.schemaname NOT LIKE 'pg_%'
    GROUP BY pi.schemaname, pi.tablename, pi.indexname, pi.indexdef
) t
GROUP BY t.schemaname, t.tablename, t.columns
HAVING count(*) > 1;
"

_info "Index usage statistics (low usage indexes may need review)..."
_pg_psql_cmd -d "${PG_BASE}" -c "
SELECT
    schemaname,
    relname as tablename,
    indexrelname as indexname,
    idx_tup_read,
    idx_tup_fetch,
    idx_scan,
    CASE
        WHEN idx_scan = 0 THEN 'UNUSED'
        WHEN idx_scan < 10 THEN 'LOW_USAGE'
        ELSE 'NORMAL'
    END as usage_status
FROM pg_stat_user_indexes
WHERE schemaname != 'information_schema' AND schemaname NOT LIKE 'pg_%'
ORDER BY idx_scan ASC, schemaname, relname, indexrelname;
"

_pg_psql_cmd -d "${PG_BASE}" -c "ALTER ROLE ${PG_USER} RESET statement_timeout"
_info "Done!"
