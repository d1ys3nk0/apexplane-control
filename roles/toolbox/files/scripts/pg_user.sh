#!/usr/bin/env bash

set -euo pipefail

error() {
    echo "[ERROR] $*"
    exit 1
}

usage() {
    cat <<'EOF'
Usage:
  pg_user <target_user> <database_name>:ro
  pg_user <target_user>:<target_pass> <database_name>:rw
  pg_user <target_user>:<target_pass> <database_name>:full
EOF
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
PG_TARGET_SPEC="${1:-}"
PG_GRANT_SPEC="${2:-}"
PG_TARGET_PASS_SET=0
PG_TARGET_USER=""
PG_TARGET_PASS=""
PG_BASE=""
PG_GRANT=""

if [ "$#" -ne 2 ]; then
    usage
    exit 1
fi

if [[ "${PG_TARGET_SPEC}" == *:* ]]; then
    PG_TARGET_PASS_SET=1
    PG_TARGET_USER="${PG_TARGET_SPEC%%:*}"
    PG_TARGET_PASS="${PG_TARGET_SPEC#*:}"
else
    PG_TARGET_USER="${PG_TARGET_SPEC}"
fi

if [ -z "${PG_TARGET_USER}" ]; then
    usage
    error "target user is empty"
fi

if [ "${PG_TARGET_PASS_SET}" = "1" ] && [ -z "${PG_TARGET_PASS}" ]; then
    usage
    error "target password is empty"
fi

if [[ "${PG_GRANT_SPEC}" != *:* ]]; then
    usage
    error "database grant must use <database_name>:<ro|rw|full>"
fi

PG_BASE="${PG_GRANT_SPEC%%:*}"
PG_GRANT="${PG_GRANT_SPEC#*:}"
PG_GRANT="${PG_GRANT,,}"

case "${PG_GRANT}" in
ro | rw | full) ;;
*)
    usage
    error "unknown grant mode: ${PG_GRANT}"
    ;;
esac

check "PG_IMAGE" "PG_HOST" "PG_PORT" "PG_USER" "PG_PASS" "PG_BASE" "PG_TARGET_USER"

sudo docker run \
    --rm \
    --network host \
    -i \
    -e "PGPASSWORD=${PG_PASS}" \
    -e "PGSSLMODE=${PG_SSL:-disable}" \
    "${PG_IMAGE}" \
    psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${PG_BASE}" \
    -v ON_ERROR_STOP=1 \
    -v "grant_mode=${PG_GRANT}" \
    -v "target_user=${PG_TARGET_USER}" \
    -v "target_pass=${PG_TARGET_PASS}" \
    -v "target_pass_set=${PG_TARGET_PASS_SET}" <<'SQL'
SELECT r.rolname AS database_owner
FROM pg_catalog.pg_database d
JOIN pg_catalog.pg_roles r ON r.oid = d.datdba
WHERE d.datname = current_database()
\gset

SELECT format(
    'DO $do$ BEGIN RAISE EXCEPTION %L; END $do$',
    format('Target role "%s" does not exist and no password was provided', :'target_user')
)
WHERE :'target_pass_set' != '1'
  AND NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles
    WHERE rolname = :'target_user'
  )
\gexec

SELECT format('CREATE USER %I WITH PASSWORD %L', :'target_user', :'target_pass')
WHERE :'target_pass_set' = '1'
  AND NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles
    WHERE rolname = :'target_user'
  )
\gexec

SELECT format('ALTER USER %I WITH PASSWORD %L', :'target_user', :'target_pass')
WHERE :'target_pass_set' = '1'
  AND EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles
    WHERE rolname = :'target_user'
  )
\gexec

SELECT format('GRANT CONNECT ON DATABASE %I TO %I', current_database(), :'target_user')
WHERE :'grant_mode' IN ('ro', 'rw')
\gexec

SELECT format('GRANT ALL PRIVILEGES ON DATABASE %I TO %I', current_database(), :'target_user')
WHERE :'grant_mode' = 'full'
\gexec

WITH toolbox_schemas AS (
    SELECT nspname
    FROM pg_catalog.pg_namespace
    WHERE nspname != 'information_schema'
      AND nspname NOT LIKE 'pg_%'
)
SELECT format('GRANT USAGE ON SCHEMA %I TO %I', nspname, :'target_user')
FROM toolbox_schemas
WHERE :'grant_mode' IN ('ro', 'rw')
\gexec

WITH toolbox_schemas AS (
    SELECT nspname
    FROM pg_catalog.pg_namespace
    WHERE nspname != 'information_schema'
      AND nspname NOT LIKE 'pg_%'
)
SELECT format('GRANT USAGE, CREATE ON SCHEMA %I TO %I', nspname, :'target_user')
FROM toolbox_schemas
WHERE :'grant_mode' = 'full'
\gexec

WITH toolbox_schemas AS (
    SELECT nspname
    FROM pg_catalog.pg_namespace
    WHERE nspname != 'information_schema'
      AND nspname NOT LIKE 'pg_%'
)
SELECT format('GRANT SELECT ON ALL TABLES IN SCHEMA %I TO %I', nspname, :'target_user')
FROM toolbox_schemas
WHERE :'grant_mode' = 'ro'
\gexec

WITH toolbox_schemas AS (
    SELECT nspname
    FROM pg_catalog.pg_namespace
    WHERE nspname != 'information_schema'
      AND nspname NOT LIKE 'pg_%'
)
SELECT format('GRANT SELECT ON ALL SEQUENCES IN SCHEMA %I TO %I', nspname, :'target_user')
FROM toolbox_schemas
WHERE :'grant_mode' = 'ro'
\gexec

WITH toolbox_schemas AS (
    SELECT nspname
    FROM pg_catalog.pg_namespace
    WHERE nspname != 'information_schema'
      AND nspname NOT LIKE 'pg_%'
)
SELECT format('GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA %I TO %I', nspname, :'target_user')
FROM toolbox_schemas
WHERE :'grant_mode' = 'rw'
\gexec

WITH toolbox_schemas AS (
    SELECT nspname
    FROM pg_catalog.pg_namespace
    WHERE nspname != 'information_schema'
      AND nspname NOT LIKE 'pg_%'
)
SELECT format('GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA %I TO %I', nspname, :'target_user')
FROM toolbox_schemas
WHERE :'grant_mode' = 'rw'
\gexec

WITH toolbox_schemas AS (
    SELECT nspname
    FROM pg_catalog.pg_namespace
    WHERE nspname != 'information_schema'
      AND nspname NOT LIKE 'pg_%'
)
SELECT format('GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA %I TO %I', nspname, :'target_user')
FROM toolbox_schemas
WHERE :'grant_mode' = 'full'
\gexec

WITH toolbox_schemas AS (
    SELECT nspname
    FROM pg_catalog.pg_namespace
    WHERE nspname != 'information_schema'
      AND nspname NOT LIKE 'pg_%'
)
SELECT format('GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA %I TO %I', nspname, :'target_user')
FROM toolbox_schemas
WHERE :'grant_mode' = 'full'
\gexec

WITH toolbox_schemas AS (
    SELECT nspname
    FROM pg_catalog.pg_namespace
    WHERE nspname != 'information_schema'
      AND nspname NOT LIKE 'pg_%'
)
SELECT format('GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA %I TO %I', nspname, :'target_user')
FROM toolbox_schemas
WHERE :'grant_mode' = 'full'
\gexec

SELECT format('ALTER DEFAULT PRIVILEGES FOR ROLE %I GRANT USAGE ON SCHEMAS TO %I', :'database_owner', :'target_user')
WHERE :'grant_mode' IN ('ro', 'rw')
\gexec

SELECT format('ALTER DEFAULT PRIVILEGES FOR ROLE %I GRANT SELECT ON TABLES TO %I', :'database_owner', :'target_user')
WHERE :'grant_mode' = 'ro'
\gexec

SELECT format('ALTER DEFAULT PRIVILEGES FOR ROLE %I GRANT SELECT ON SEQUENCES TO %I', :'database_owner', :'target_user')
WHERE :'grant_mode' = 'ro'
\gexec

SELECT format('ALTER DEFAULT PRIVILEGES FOR ROLE %I GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO %I', :'database_owner', :'target_user')
WHERE :'grant_mode' = 'rw'
\gexec

SELECT format('ALTER DEFAULT PRIVILEGES FOR ROLE %I GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO %I', :'database_owner', :'target_user')
WHERE :'grant_mode' = 'rw'
\gexec

SELECT format('ALTER DEFAULT PRIVILEGES FOR ROLE %I GRANT USAGE, CREATE ON SCHEMAS TO %I', :'database_owner', :'target_user')
WHERE :'grant_mode' = 'full'
\gexec

SELECT format('ALTER DEFAULT PRIVILEGES FOR ROLE %I GRANT ALL PRIVILEGES ON TABLES TO %I', :'database_owner', :'target_user')
WHERE :'grant_mode' = 'full'
\gexec

SELECT format('ALTER DEFAULT PRIVILEGES FOR ROLE %I GRANT ALL PRIVILEGES ON SEQUENCES TO %I', :'database_owner', :'target_user')
WHERE :'grant_mode' = 'full'
\gexec

SELECT format('ALTER DEFAULT PRIVILEGES FOR ROLE %I GRANT ALL PRIVILEGES ON FUNCTIONS TO %I', :'database_owner', :'target_user')
WHERE :'grant_mode' = 'full'
\gexec
SQL

echo "User '${PG_TARGET_USER}' has been granted ${PG_GRANT} access to database '${PG_BASE}'"
