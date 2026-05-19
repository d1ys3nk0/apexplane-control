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

check "PG_IMAGE" "PG_HOST" "PG_PORT" "PG_USER" "PG_PASS" "PG_BASE"

psql() {
    sudo docker run --rm --network host -e "PGPASSWORD=${PG_PASS}" -e "PGSSLMODE=${PG_SSL:-disable}" "${PG_IMAGE}" psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" "$@"
}

echo "Creating amcheck extension"
psql -d "${PG_BASE}" -c "CREATE EXTENSION IF NOT EXISTS amcheck"

echo "Performing amcheck database ${PG_BASE}"
psql -d "${PG_BASE}" -c "ALTER ROLE ${PG_USER} SET statement_timeout = 300000"

echo "Performing lightweight B-tree index checks for ${PG_BASE}"
psql -d "${PG_BASE}" -c "
SELECT
    schemaname,
    relname as tablename,
    indexrelname as indexname,
    bt_index_check(indexrelid) as check_result
FROM pg_stat_user_indexes
WHERE schemaname != 'information_schema' AND schemaname NOT LIKE 'pg_%'
ORDER BY schemaname, relname, indexrelname;
"

echo "Performing thorough B-tree index checks with heap verification..."
psql -d "${PG_BASE}" -c "
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

echo "Checking for potential duplicate indexes..."
psql -d "${PG_BASE}" -c "
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

echo "Index usage statistics (low usage indexes may need review)..."
psql -d "${PG_BASE}" -c "
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

psql -d "${PG_BASE}" -c "ALTER ROLE ${PG_USER} RESET statement_timeout"
echo "Done!"
