#!/usr/bin/env bash

set -euo pipefail

SCRIPT_START_SECONDS=${SECONDS}

is_quiet() {
    case "${QUIET:-}" in
    1 | true | True | TRUE) return 0 ;;
    *) return 1 ;;
    esac
}

info() {
    is_quiet || printf '> %s\n' "$*"
}

warn() {
    is_quiet || printf '> %s\n' "$*" >&2
}

error() {
    printf '! %s\n' "$*" >&2
    exit 1
}

usage_error() {
    printf '! %s\n\n' "$*" >&2
    usage >&2
    exit 2
}

require_vars() {
    local var

    for var in "$@"; do
        if [ -z "${!var:-}" ]; then
            error "${var} is not set"
        fi
    done
}

inspect_container_env() {
    local format

    format='{''{range .Config.Env}''}''{''{println .}''}''{''{end}''}'
    docker inspect "${WALG_CONTAINER}" --format "${format}" | awk -F= -v key="$1" '$1 == key {print substr($0, length(key) + 2); exit}'
}

inspect_container_mounts() {
    local format

    format='{''{range .Mounts}''}''{''{println .Name "\t" .Destination}''}''{''{end}''}'
    docker inspect "${WALG_CONTAINER}" --format "${format}"
}

inspect_data_volume_mount_path() {
    inspect_container_mounts | awk -F '\t' -v data_dir="${WALG_DATA_DIR}" '
        data_dir == $2 || index(data_dir, $2 "/") == 1 {
            if (length($2) > length(best)) {
                best = $2
            }
        }
        END {
            print best
        }
    '
}

inspect_data_volume() {
    inspect_container_mounts | awk -F '\t' -v mount_path="${WALG_DATA_ROOT}" '$2 == mount_path {print $1; exit}'
}

require_positive_integer() {
    if [[ ! "${1}" =~ ^[1-9][0-9]*$ ]]; then
        usage_error "${2} must be a positive integer"
    fi
}

is_true() {
    case "${1}" in
    1 | true | True | TRUE) return 0 ;;
    "" | 0 | false | False | FALSE) return 1 ;;
    *) usage_error "${2} must be true or false" ;;
    esac
}

usage() {
    cat >&2 <<'USAGE'
Usage: walg_recover [s3://bucket/prefix] [backup-name]
       walg_recover [backup-name]

Replaces the local Docker PostgreSQL data volume with a physical WAL-G backup
and starts PostgreSQL archive recovery. This is a whole-cluster restore, not a
single database restore.

Required environment:
  WALG_RECOVER_S3_ENDPOINT
  WALG_RECOVER_S3_REGION
  WALG_RECOVER_S3_BUCKET
  WALG_RECOVER_S3_PREFIX
  WALG_RECOVER_S3_ACCESS_KEY
  WALG_RECOVER_S3_SECRET_KEY

Optional environment:
  PG_PORT=5432
  WALG_CONTAINER=postgres
  WALG_DATA_ROOT=<container data volume mount path>
  WALG_DATA_DIR=<container PGDATA>
  WALG_CONFIG_DIR=/opt/postgres/config
  WALG_SNAPSHOT_DIR=/opt/postgres/snapshots
  WALG_RECOVER_BACKUP_NAME=LATEST
  WALG_RECOVER_PGUSER=admin
  WALG_RECOVER_NO_SNAPSHOT=true|false
  WALG_RECOVER_START=true|false
  WALG_RECOVER_WAIT=true|false
  WALG_RECOVER_WAIT_SECONDS=3600
  WALG_RECOVER_ORIGIN_BASE=<old-database-name>
  WALG_RECOVER_TARGET_BASE=<new-database-name>
  WALG_RECOVER_ORIGIN_OWNER=<old-role-name>
  WALG_RECOVER_TARGET_USER=<new-role-name>
  WALG_RECOVER_TARGET_PASS=<new-role-password>
  WALG_RECOVER_ORIGIN_USERS="<source-role-a> <source-role-b>"

Examples:
  dotenv /opt/postgres/admin.env /opt/postgres/bin/walg_recover
  dotenv /opt/postgres/admin.env /opt/postgres/bin/walg_recover s3://<bucket>/<prefix> LATEST
USAGE
}

init_config() {
    if [ "$#" -gt 2 ]; then
        usage_error "Expected 0, 1, or 2 arguments, got $#"
    fi

    WALG_CONTAINER="${WALG_CONTAINER:-postgres}"
    PG_PORT="${PG_PORT:-5432}"
    WALG_DATA_DIR="${WALG_DATA_DIR:-$(inspect_container_env PGDATA)}"
    if [ -z "${WALG_DATA_DIR}" ]; then
        error "Cannot determine PostgreSQL data directory from WALG_DATA_DIR or container ${WALG_CONTAINER} PGDATA"
    fi
    WALG_DATA_ROOT="${WALG_DATA_ROOT:-$(inspect_data_volume_mount_path)}"
    if [ -z "${WALG_DATA_ROOT}" ]; then
        error "Cannot determine data root from WALG_DATA_ROOT or container ${WALG_CONTAINER} mounts"
    fi
    WALG_DATA_VOLUME="$(inspect_data_volume)"
    if [ -z "${WALG_DATA_VOLUME}" ]; then
        error "Cannot determine data volume from container ${WALG_CONTAINER}"
    fi
    WALG_CONFIG_DIR="${WALG_CONFIG_DIR:-/opt/postgres/config}"
    WALG_SNAPSHOT_DIR="${WALG_SNAPSHOT_DIR:-/opt/postgres/snapshots}"
    WALG_RECOVER_BACKUP_NAME="${WALG_RECOVER_BACKUP_NAME:-LATEST}"
    WALG_RECOVER_PGUSER="${WALG_RECOVER_PGUSER:-admin}"
    WALG_RECOVER_NO_SNAPSHOT="${WALG_RECOVER_NO_SNAPSHOT:-false}"
    WALG_RECOVER_START="${WALG_RECOVER_START:-true}"
    WALG_RECOVER_WAIT="${WALG_RECOVER_WAIT:-true}"
    WALG_RECOVER_WAIT_SECONDS="${WALG_RECOVER_WAIT_SECONDS:-3600}"
    WALG_RECOVER_S3_BUCKET="${WALG_RECOVER_S3_BUCKET:-}"
    WALG_RECOVER_ORIGIN_BASE="${WALG_RECOVER_ORIGIN_BASE:-}"
    WALG_RECOVER_TARGET_BASE="${WALG_RECOVER_TARGET_BASE:-}"
    WALG_RECOVER_ORIGIN_OWNER="${WALG_RECOVER_ORIGIN_OWNER:-}"
    WALG_RECOVER_TARGET_USER="${WALG_RECOVER_TARGET_USER:-}"
    WALG_RECOVER_TARGET_PASS="${WALG_RECOVER_TARGET_PASS:-}"
    WALG_RECOVER_ORIGIN_USERS="${WALG_RECOVER_ORIGIN_USERS:-}"

    if [ "$#" -ge 1 ]; then
        if [[ "$1" == s3://* ]]; then
            WALG_RECOVER_S3_PREFIX="$1"
        else
            WALG_RECOVER_BACKUP_NAME="$1"
        fi
    fi
    if [ "$#" -eq 2 ]; then
        WALG_RECOVER_BACKUP_NAME="$2"
    fi

    require_vars \
        "WALG_RECOVER_S3_ENDPOINT" \
        "WALG_RECOVER_S3_REGION" \
        "WALG_RECOVER_S3_BUCKET" \
        "WALG_RECOVER_S3_PREFIX" \
        "WALG_RECOVER_S3_ACCESS_KEY" \
        "WALG_RECOVER_S3_SECRET_KEY"
    require_positive_integer "${WALG_RECOVER_WAIT_SECONDS}" WALG_RECOVER_WAIT_SECONDS
    require_positive_integer "${PG_PORT}" PG_PORT
    is_true "${WALG_RECOVER_NO_SNAPSHOT}" WALG_RECOVER_NO_SNAPSHOT || true
    is_true "${WALG_RECOVER_START}" WALG_RECOVER_START || true
    is_true "${WALG_RECOVER_WAIT}" WALG_RECOVER_WAIT || true

    if [[ "${WALG_RECOVER_S3_PREFIX}" != s3://* ]]; then
        WALG_RECOVER_S3_PREFIX="s3://${WALG_RECOVER_S3_BUCKET}/${WALG_RECOVER_S3_PREFIX#/}"
    fi
    if [ -n "${WALG_RECOVER_ORIGIN_BASE}" ] || [ -n "${WALG_RECOVER_TARGET_BASE}" ]; then
        require_vars "WALG_RECOVER_ORIGIN_BASE" "WALG_RECOVER_TARGET_BASE"
    fi
    if [ -n "${WALG_RECOVER_ORIGIN_OWNER}" ] || [ -n "${WALG_RECOVER_TARGET_USER}" ]; then
        require_vars "WALG_RECOVER_ORIGIN_OWNER" "WALG_RECOVER_TARGET_USER"
    fi
    if [ -n "${WALG_RECOVER_ORIGIN_USERS}" ]; then
        require_vars "WALG_RECOVER_TARGET_USER" "WALG_RECOVER_TARGET_BASE"
    fi
    if [ -n "${WALG_RECOVER_ORIGIN_BASE}${WALG_RECOVER_ORIGIN_OWNER}${WALG_RECOVER_ORIGIN_USERS}" ]; then
        if ! is_true "${WALG_RECOVER_START}" WALG_RECOVER_START || ! is_true "${WALG_RECOVER_WAIT}" WALG_RECOVER_WAIT; then
            error "WAL-G recovery rename/reassign requires WALG_RECOVER_START=true and WALG_RECOVER_WAIT=true"
        fi
    fi

    WALG_IMAGE="${WALG_IMAGE:-$(docker inspect "${WALG_CONTAINER}" --format '{{.Config.Image}}')}"
    RECOVER_SCRIPT="${WALG_CONFIG_DIR}/walg_recover.sh"
    POSTGRES_STARTED=0
    RECOVERY_COMPLETED=0
}

cleanup() {
    if [ "${RECOVERY_COMPLETED:-0}" = "1" ] || [ "${POSTGRES_STARTED:-0}" != "1" ]; then
        if [ -n "${RECOVER_SCRIPT:-}" ] && [ -f "${RECOVER_SCRIPT}" ]; then
            info "Removing temporary WAL-G recovery config ${RECOVER_SCRIPT}"
            rm -f "${RECOVER_SCRIPT}"
        fi
        return
    fi

    local recovery_state
    recovery_state=$(docker exec "${WALG_CONTAINER}" psql -p "${PG_PORT}" -U "${WALG_RECOVER_PGUSER}" -d postgres -Atq -c "SELECT pg_is_in_recovery()" 2>/dev/null || true)
    if [ "${recovery_state}" = "f" ]; then
        if [ -n "${RECOVER_SCRIPT:-}" ] && [ -f "${RECOVER_SCRIPT}" ]; then
            info "Removing temporary WAL-G recovery config ${RECOVER_SCRIPT}"
            rm -f "${RECOVER_SCRIPT}"
        fi
        return
    fi

    warn "Leaving ${RECOVER_SCRIPT} in place because PostgreSQL was started and may still need it for recovery"
}

init_cleanup() {
    trap cleanup EXIT
}

init_timestamps() {
    TIME_TAG=$(date -u '+%y%m%d%H%M%S')
    TIME_UTC=$(date -u '+%Y-%m-%d %H:%M:%S')
    info "Started at ${TIME_UTC} UTC"
}

wait_before_recovery() {
    local seconds_left

    info "WAL-G recovery will replace Docker volume ${WALG_DATA_VOLUME} from ${WALG_RECOVER_S3_PREFIX}."
    for seconds_left in 10 9 8 7 6 5 4 3 2 1; do
        warn "Starting destructive recovery in ${seconds_left}s..."
        sleep 1
    done
}

stop_postgres() {
    info "Stopping PostgreSQL container ${WALG_CONTAINER}"
    docker stop "${WALG_CONTAINER}"
}

snapshot_data() {
    if is_true "${WALG_RECOVER_NO_SNAPSHOT}" WALG_RECOVER_NO_SNAPSHOT; then
        warn "Skipping pre-restore data snapshot because WALG_RECOVER_NO_SNAPSHOT=${WALG_RECOVER_NO_SNAPSHOT}"
        return
    fi

    info "Creating pre-restore snapshot in ${WALG_SNAPSHOT_DIR}"
    mkdir -p "${WALG_SNAPSHOT_DIR}"
    docker run --rm \
        -v "${WALG_DATA_VOLUME}:${WALG_DATA_ROOT}:ro" \
        -v "${WALG_SNAPSHOT_DIR}:/mnt/snapshots" \
        busybox:latest \
        tar czf "/mnt/snapshots/walg-recover-before-${TIME_TAG}.tar.gz" -C "${WALG_DATA_DIR}" .
}

clear_data() {
    info "Clearing PostgreSQL data volume ${WALG_DATA_VOLUME}"
    docker run --rm \
        -v "${WALG_DATA_VOLUME}:${WALG_DATA_ROOT}" \
        busybox:latest \
        find "${WALG_DATA_DIR}" -mindepth 1 -delete
}

fetch_backup() {
    info "Fetching WAL-G backup ${WALG_RECOVER_BACKUP_NAME} from ${WALG_RECOVER_S3_PREFIX}"
    docker run --rm \
        --user postgres \
        -v "${WALG_DATA_VOLUME}:${WALG_DATA_ROOT}" \
        -e "AWS_ENDPOINT=${WALG_RECOVER_S3_ENDPOINT}" \
        -e "AWS_REGION=${WALG_RECOVER_S3_REGION}" \
        -e "AWS_ACCESS_KEY_ID=${WALG_RECOVER_S3_ACCESS_KEY}" \
        -e "AWS_SECRET_ACCESS_KEY=${WALG_RECOVER_S3_SECRET_KEY}" \
        -e "WALG_S3_PREFIX=${WALG_RECOVER_S3_PREFIX}" \
        "${WALG_IMAGE}" \
        /usr/local/bin/wal-g backup-fetch "${WALG_DATA_DIR}" "${WALG_RECOVER_BACKUP_NAME}"
}

install_recover_config() {
    info "Installing temporary WAL-G recovery config ${RECOVER_SCRIPT}"
    mkdir -p "${WALG_CONFIG_DIR}"
    umask 077
    {
        printf '%s\n' '#!/bin/sh'
        printf '%s\n' 'export PGHOST="/var/run/postgresql"'
        printf 'export PGUSER=%q\n' "${WALG_RECOVER_PGUSER}"
        printf 'export AWS_ENDPOINT=%q\n' "${WALG_RECOVER_S3_ENDPOINT}"
        printf 'export AWS_REGION=%q\n' "${WALG_RECOVER_S3_REGION}"
        printf 'export AWS_ACCESS_KEY_ID=%q\n' "${WALG_RECOVER_S3_ACCESS_KEY}"
        printf 'export AWS_SECRET_ACCESS_KEY=%q\n' "${WALG_RECOVER_S3_SECRET_KEY}"
        printf 'export WALG_S3_PREFIX=%q\n' "${WALG_RECOVER_S3_PREFIX}"
        printf '%s\n' 'exec /usr/local/bin/wal-g "$@"'
    } >"${RECOVER_SCRIPT}"
    chmod 0700 "${RECOVER_SCRIPT}"
}

enable_recovery() {
    info "Enabling PostgreSQL archive recovery"
    # shellcheck disable=SC2016
    docker run --rm \
        -v "${WALG_DATA_VOLUME}:${WALG_DATA_ROOT}" \
        -e "RESTORE_COMMAND=restore_command = '/opt/config/walg_recover.sh wal-fetch \"%f\" \"%p\" 2>&1 | tee -a ${WALG_DATA_DIR}/walg_restore.log'" \
        busybox:latest \
        sh -c 'printf "%s\n" "$RESTORE_COMMAND" >> "$1/postgresql.auto.conf" && touch "$1/recovery.signal"' sh "${WALG_DATA_DIR}"
}

start_postgres() {
    if ! is_true "${WALG_RECOVER_START}" WALG_RECOVER_START; then
        warn "PostgreSQL container ${WALG_CONTAINER} is left stopped because WALG_RECOVER_START=${WALG_RECOVER_START}"
        return
    fi

    info "Starting PostgreSQL container ${WALG_CONTAINER}"
    docker start "${WALG_CONTAINER}"
    POSTGRES_STARTED=1
}

wait_for_recovery() {
    local deadline
    local recovery_state

    if ! is_true "${WALG_RECOVER_START}" WALG_RECOVER_START || ! is_true "${WALG_RECOVER_WAIT}" WALG_RECOVER_WAIT; then
        return
    fi

    info "Waiting up to ${WALG_RECOVER_WAIT_SECONDS}s for PostgreSQL to finish recovery"
    deadline=$((SECONDS + WALG_RECOVER_WAIT_SECONDS))
    while [ "${SECONDS}" -lt "${deadline}" ]; do
        if docker exec "${WALG_CONTAINER}" pg_isready -d postgres -p "${PG_PORT}" -U "${WALG_RECOVER_PGUSER}" >/dev/null 2>&1; then
            recovery_state=$(docker exec "${WALG_CONTAINER}" psql -p "${PG_PORT}" -U "${WALG_RECOVER_PGUSER}" -d postgres -Atq -c "SELECT pg_is_in_recovery()" || true)
            if [ "${recovery_state}" = "f" ]; then
                info "PostgreSQL recovery completed"
                RECOVERY_COMPLETED=1
                return
            fi
        fi
        sleep 5
    done

    error "PostgreSQL did not finish recovery within ${WALG_RECOVER_WAIT_SECONDS}s"
}

cleanup_recover_config() {
    if ! is_true "${WALG_RECOVER_START}" WALG_RECOVER_START; then
        return
    fi

    local recovery_state
    recovery_state=$(docker exec "${WALG_CONTAINER}" psql -p "${PG_PORT}" -U "${WALG_RECOVER_PGUSER}" -d postgres -Atq -c "SELECT pg_is_in_recovery()" 2>/dev/null || true)
    if [ "${recovery_state}" = "t" ]; then
        warn "PostgreSQL is still in recovery; leaving restore_command in place"
        return
    fi

    info "Resetting temporary restore_command override"
    docker exec "${WALG_CONTAINER}" psql -p "${PG_PORT}" -U "${WALG_RECOVER_PGUSER}" -d postgres -c "ALTER SYSTEM RESET restore_command"
    docker exec "${WALG_CONTAINER}" psql -p "${PG_PORT}" -U "${WALG_RECOVER_PGUSER}" -d postgres -c "SELECT pg_reload_conf()"
}

psql_postgres() {
    docker exec -i "${WALG_CONTAINER}" psql -p "${PG_PORT}" -U "${WALG_RECOVER_PGUSER}" -d postgres -v ON_ERROR_STOP=1 "$@"
}

psql_database() {
    local database="$1"
    shift

    docker exec -i "${WALG_CONTAINER}" psql -p "${PG_PORT}" -U "${WALG_RECOVER_PGUSER}" -d "${database}" -v ON_ERROR_STOP=1 "$@"
}

reconcile_database_name() {
    if [ -z "${WALG_RECOVER_ORIGIN_BASE}" ]; then
        return
    fi

    info "Reconciling recovered database ${WALG_RECOVER_ORIGIN_BASE} to ${WALG_RECOVER_TARGET_BASE}"
    psql_postgres \
        -v "source_db=${WALG_RECOVER_ORIGIN_BASE}" \
        -v "target_db=${WALG_RECOVER_TARGET_BASE}" <<'SQL'
SELECT format('SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = %L AND pid <> pg_backend_pid()', :'source_db')
WHERE :'source_db' <> :'target_db'
  AND EXISTS (SELECT 1 FROM pg_database WHERE datname = :'source_db')
  AND NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'target_db')
\gexec

SELECT format('ALTER DATABASE %I RENAME TO %I', :'source_db', :'target_db')
WHERE :'source_db' <> :'target_db'
  AND EXISTS (SELECT 1 FROM pg_database WHERE datname = :'source_db')
  AND NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'target_db')
\gexec

SELECT format(
    'DO $do$ BEGIN RAISE EXCEPTION %L; END $do$',
    format('Both source database "%s" and target database "%s" exist', :'source_db', :'target_db')
)
WHERE :'source_db' <> :'target_db'
  AND EXISTS (SELECT 1 FROM pg_database WHERE datname = :'source_db')
  AND EXISTS (SELECT 1 FROM pg_database WHERE datname = :'target_db')
\gexec

SELECT format(
    'DO $do$ BEGIN RAISE EXCEPTION %L; END $do$',
    format('Neither source database "%s" nor target database "%s" exists', :'source_db', :'target_db')
)
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname IN (:'source_db', :'target_db'))
\gexec
SQL
}

reconcile_role_name() {
    local password_b64

    if [ -z "${WALG_RECOVER_TARGET_USER}" ]; then
        return
    fi

    password_b64="$(printf '%s' "${WALG_RECOVER_TARGET_PASS}" | base64 | tr -d '\n')"
    info "Reconciling recovered role ${WALG_RECOVER_TARGET_USER}"
    psql_postgres \
        -v "source_user=${WALG_RECOVER_ORIGIN_OWNER}" \
        -v "target_user=${WALG_RECOVER_TARGET_USER}" \
        -v "target_pass_b64=${password_b64}" <<'SQL'
SELECT format('ALTER ROLE %I RENAME TO %I', :'source_user', :'target_user')
WHERE :'source_user' <> ''
  AND :'source_user' <> :'target_user'
  AND EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'source_user')
  AND NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'target_user')
\gexec

SELECT format(
    'DO $do$ BEGIN RAISE EXCEPTION %L; END $do$',
    format('Both source role "%s" and target role "%s" exist', :'source_user', :'target_user')
)
WHERE :'source_user' <> ''
  AND :'source_user' <> :'target_user'
  AND EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'source_user')
  AND EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'target_user')
\gexec

SELECT format('CREATE ROLE %I LOGIN CREATEDB', :'target_user')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'target_user')
  AND :'target_pass_b64' <> ''
\gexec

SELECT format(
    'DO $do$ BEGIN RAISE EXCEPTION %L; END $do$',
    format('Target role "%s" does not exist and WALG_RECOVER_TARGET_PASS is empty', :'target_user')
)
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'target_user')
  AND :'target_pass_b64' = ''
\gexec

SELECT format(
    'ALTER ROLE %I LOGIN CREATEDB PASSWORD %L',
    :'target_user',
    convert_from(decode(:'target_pass_b64', 'base64'), 'UTF8')
)
WHERE :'target_pass_b64' <> ''
\gexec
SQL
}

reassign_database_objects() {
    local target_db="${WALG_RECOVER_TARGET_BASE:-${WALG_RECOVER_ORIGIN_BASE}}"

    if [ -z "${target_db}" ] || [ -z "${WALG_RECOVER_TARGET_USER}" ]; then
        return
    fi

    info "Reconciling ownership and grants in database ${target_db}"
    psql_postgres \
        -v "target_db=${target_db}" \
        -v "target_user=${WALG_RECOVER_TARGET_USER}" <<'SQL'
SELECT format('ALTER DATABASE %I OWNER TO %I', :'target_db', :'target_user')
WHERE EXISTS (SELECT 1 FROM pg_database WHERE datname = :'target_db')
\gexec
SQL

    psql_database "${target_db}" \
        -v "target_user=${WALG_RECOVER_TARGET_USER}" \
        -v "reassign_users=${WALG_RECOVER_ORIGIN_USERS}" <<'SQL'
SELECT format('REASSIGN OWNED BY %I TO %I', source_user, :'target_user')
FROM unnest(string_to_array(:'reassign_users', ' ')) AS source_user
WHERE source_user <> ''
  AND source_user <> :'target_user'
  AND EXISTS (SELECT 1 FROM pg_roles WHERE rolname = source_user)
\gexec

SELECT format('ALTER SCHEMA public OWNER TO %I', :'target_user')
WHERE EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'public')
\gexec

SELECT format('GRANT ALL PRIVILEGES ON DATABASE %I TO %I', current_database(), :'target_user')
\gexec

WITH user_schemas AS (
    SELECT nspname
    FROM pg_namespace
    WHERE nspname != 'information_schema'
      AND nspname NOT LIKE 'pg_%'
)
SELECT format('GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA %I TO %I', nspname, :'target_user')
FROM user_schemas
\gexec

WITH user_schemas AS (
    SELECT nspname
    FROM pg_namespace
    WHERE nspname != 'information_schema'
      AND nspname NOT LIKE 'pg_%'
)
SELECT format('GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA %I TO %I', nspname, :'target_user')
FROM user_schemas
\gexec

WITH user_schemas AS (
    SELECT nspname
    FROM pg_namespace
    WHERE nspname != 'information_schema'
      AND nspname NOT LIKE 'pg_%'
)
SELECT format('GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA %I TO %I', nspname, :'target_user')
FROM user_schemas
\gexec
SQL
}

reconcile_recovered_cluster() {
    reconcile_database_name
    reconcile_role_name
    reassign_database_objects
}

finish() {
    info "Finished in $((SECONDS - SCRIPT_START_SECONDS))s"
}

main() {
    init_config "$@"
    init_timestamps
    init_cleanup
    wait_before_recovery
    stop_postgres
    snapshot_data
    clear_data
    fetch_backup
    install_recover_config
    enable_recovery
    start_postgres
    wait_for_recovery
    cleanup_recover_config
    reconcile_recovered_cluster
    finish
}

main "$@"
