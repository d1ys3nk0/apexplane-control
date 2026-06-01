#!/usr/bin/env bash

set -euo pipefail

run() {
    echo "> $1"
    shift

    if [ "${DEBUG:-0}" = "1" ]; then
        printf '$'
        printf ' %q' "$@"
        printf '\n'
    fi

    "$@"
}

run_output() {
    local output="$1"
    shift

    echo "> $1"
    shift

    if [ "${DEBUG:-0}" = "1" ]; then
        printf '$'
        printf ' %q' "$@"
        printf ' > %q\n' "${output}"
    fi

    "$@" >"${output}"
}

info() {
    echo "[INFO] $*"
}

error() {
    echo "[ERROR] $*"
    exit 1
}

usage() {
    cat >&2 <<'USAGE'
Usage: pg_restore [backup-file|s3:key|s3:prefix|s3://bucket/key|s3://bucket/prefix]

Restores a cst-format dump, PostgreSQL dir-format directory or tar archive,
plain .sql, gzip .sql.gz, gzip .tar.gz, or encrypted .enc backup into PG_BASE.
With no source argument and S3 enabled, restores the latest backup under
PG_RESTORE_S3_PREFIX. Without PG_RESTORE_S3_PREFIX, pass a local backup file or S3
source argument.

Required environment:
  PG_IMAGE, PG_HOST, PG_PORT, PG_USER, PG_PASS, PG_BASE

Optional environment:
  PG_SSL=require|disable (defaults to disable)
  PG_RESTORE_NO_RECREATE=true|false
  PG_RESTORE_NO_PREPARE=true|false
  PG_RESTORE_NO_VACUUM=true|false
  PG_RESTORE_FORMAT=sql|dir|cst (optional override; defaults to extension detection)
  PG_RESTORE_CONCURRENCY=<jobs> (defaults to 4)
  PG_RESTORE_CREATE_EXTENSIONS="extension_a extension_b"
  PG_RESTORE_EXCLUDE_EXTENSIONS="extension_a extension_b"
  PG_RESTORE_SECRET=<passphrase>
  PG_RESTORE_S3=0|false
  PG_RESTORE_S3_ENDPOINT=<endpoint>
  PG_RESTORE_S3_REGION=<region>
  PG_RESTORE_S3_BUCKET=<bucket>
  PG_RESTORE_S3_PREFIX=<key-prefix>
  PG_RESTORE_S3_ACCESS_KEY=<access-key>
  PG_RESTORE_S3_SECRET_KEY=<secret-key>
Examples:
  dotenv /path/to/app.env pg_restore /var/backups/postgres/latest.dump.enc
  dotenv /path/to/app.env pg_restore
  dotenv /path/to/app.env pg_restore s3:source_database/
  dotenv /path/to/app.env pg_restore s3://bucket/source_database/backup.tar.gz
USAGE
}

usage_error() {
    usage
    error "$*"
}

check_vars() {
    local arg

    for arg in "$@"; do
        if [ -z "${!arg:-}" ]; then
            error "${arg} is not set"
        fi
    done
}

is_s3_enabled() {
    case "${PG_RESTORE_S3}" in
    0 | false | False | FALSE) return 1 ;;
    *) return 0 ;;
    esac
}

is_true() {
    case "${1}" in
    1 | true | True | TRUE) return 0 ;;
    "" | 0 | false | False | FALSE) return 1 ;;
    *) usage_error "${2} must be true or false" ;;
    esac
}

require_positive_integer() {
    if [[ ! "${1}" =~ ^[1-9][0-9]*$ ]]; then
        usage_error "${2} must be a positive integer"
    fi
}

cleanup() {
    if [ "${PREPARE_DB_CREATED:-0}" = "1" ] && [ "${PREPARE_DB_PROMOTED:-0}" != "1" ] && [ -n "${PREPARE_DB_NAME:-}" ]; then
        info "Cleaning up prepare database ${PREPARE_DB_NAME}"
        drop_database "${PREPARE_DB_NAME}" || true
    fi
    if [ -n "${DECRYPTED_FILE:-}" ] && [ -f "${DECRYPTED_FILE}" ]; then
        info "Cleaning up temporary decrypted file ${DECRYPTED_FILE}"
        rm -f "${DECRYPTED_FILE}"
    fi
    if [ -n "${DECOMPRESSED_FILE:-}" ] && [ -f "${DECOMPRESSED_FILE}" ]; then
        info "Cleaning up temporary decompressed file ${DECOMPRESSED_FILE}"
        rm -f "${DECOMPRESSED_FILE}"
    fi
    if [ -n "${EXTRACTED_DIR:-}" ] && [ -d "${EXTRACTED_DIR}" ]; then
        info "Cleaning up temporary extracted directory ${EXTRACTED_DIR}"
        rm -rf "${EXTRACTED_DIR}"
    fi
    if [ -n "${DOWNLOADED_DIR:-}" ] && [ -d "${DOWNLOADED_DIR}" ]; then
        info "Cleaning up temporary download directory ${DOWNLOADED_DIR}"
        rm -rf "${DOWNLOADED_DIR}"
    fi
    if [ -n "${RESTORE_LIST_FILE:-}" ] && [ -f "${RESTORE_LIST_FILE}" ]; then
        info "Cleaning up temporary restore list ${RESTORE_LIST_FILE}"
        rm -f "${RESTORE_LIST_FILE}"
    fi
}

is_exact_backup_key() {
    case "${1}" in
    *.dump | *.dump.enc | *.sql | *.sql.enc | *.sql.gz | *.sql.gz.enc | *.tar | *.tar.enc | *.tar.gz | *.tar.gz.enc) return 0 ;;
    *) return 1 ;;
    esac
}

is_gzip_file() {
    [ "$(od -An -tx1 -N2 "$1" | tr -d ' \n')" = "1f8b" ]
}

restore_format_flag() {
    case "${PG_RESTORE_FORMAT}" in
    dir) printf 'd' ;;
    cst) printf 'c' ;;
    *) usage_error "PG_RESTORE_FORMAT must be sql, dir, or cst" ;;
    esac
}

aws_env() {
    env AWS_REGION="${PG_RESTORE_S3_REGION}" AWS_ACCESS_KEY_ID="${PG_RESTORE_S3_ACCESS_KEY}" AWS_SECRET_ACCESS_KEY="${PG_RESTORE_S3_SECRET_KEY}" "$@"
}

latest_s3_key() {
    local bucket="${1}"
    local prefix="${2}"
    local key

    # shellcheck disable=SC2016
    key=$(
        aws_env aws --endpoint-url="${PG_RESTORE_S3_ENDPOINT}" s3api list-objects-v2 \
            --bucket "${bucket}" \
            --prefix "${prefix}" \
            --query 'sort_by(not_null(Contents, `[]`)[?ends_with(Key, `.dump`) || ends_with(Key, `.dump.enc`) || ends_with(Key, `.sql`) || ends_with(Key, `.sql.enc`) || ends_with(Key, `.sql.gz`) || ends_with(Key, `.sql.gz.enc`) || ends_with(Key, `.tar`) || ends_with(Key, `.tar.enc`) || ends_with(Key, `.tar.gz`) || ends_with(Key, `.tar.gz.enc`)], &LastModified)[-1].Key' \
            --output text
    )

    if [ -z "${key}" ] || [ "${key}" = "None" ]; then
        error "No backup objects found in s3://${bucket}/${prefix}"
    fi

    echo "${key}"
}

init_config() {
    if [ "$#" -gt 1 ]; then
        usage_error "Expected 0 or 1 arguments, got $#"
    fi

    BACKUP_INPUT="${1:-}"
    PG_IMAGE="${PG_IMAGE:-}"
    PG_RESTORE_SECRET="${PG_RESTORE_SECRET:-}"
    PG_RESTORE_S3_ENDPOINT="${PG_RESTORE_S3_ENDPOINT:-}"
    PG_RESTORE_S3_PREFIX="${PG_RESTORE_S3_PREFIX:-}"
    PG_RESTORE_S3_REGION="${PG_RESTORE_S3_REGION:-}"
    PG_RESTORE_S3_BUCKET="${PG_RESTORE_S3_BUCKET:-}"
    PG_RESTORE_S3_ACCESS_KEY="${PG_RESTORE_S3_ACCESS_KEY:-}"
    PG_RESTORE_S3_SECRET_KEY="${PG_RESTORE_S3_SECRET_KEY:-}"
    PG_RESTORE_S3="${PG_RESTORE_S3:-}"
    PG_RESTORE_NO_RECREATE="${PG_RESTORE_NO_RECREATE:-}"
    PG_RESTORE_NO_PREPARE="${PG_RESTORE_NO_PREPARE:-}"
    PG_RESTORE_NO_VACUUM="${PG_RESTORE_NO_VACUUM:-}"
    PG_RESTORE_FORMAT="${PG_RESTORE_FORMAT:-}"
    PG_RESTORE_CONCURRENCY="${PG_RESTORE_CONCURRENCY:-4}"
    PG_RESTORE_EXCLUDE_EXTENSIONS="${PG_RESTORE_EXCLUDE_EXTENSIONS:-}"

    check_vars "PG_IMAGE" "PG_HOST" "PG_PORT" "PG_USER" "PG_PASS" "PG_BASE"
    require_positive_integer "${PG_RESTORE_CONCURRENCY}" PG_RESTORE_CONCURRENCY
    case "${PG_RESTORE_FORMAT}" in
    "" | sql | dir | cst) ;;
    *) usage_error "PG_RESTORE_FORMAT must be sql, dir, or cst" ;;
    esac

    BACKUP_FILE="${BACKUP_INPUT}"
    DECRYPTED_FILE=""
    DECOMPRESSED_FILE=""
    DOWNLOADED_FILE=""
    DOWNLOADED_DIR=""
    EXTRACTED_DIR=""
    RESTORE_LIST_FILE=""
    PREPARE_DB_CREATED=0
    PREPARE_DB_NAME=""
    PREPARE_DB_PROMOTED=0
}

init_cleanup() {
    trap cleanup EXIT
}

validate_s3_backup_input() {
    local var

    S3_BUCKET="${PG_RESTORE_S3_BUCKET}"
    if [ -z "${BACKUP_INPUT}" ]; then
        S3_INPUT="${PG_RESTORE_S3_PREFIX}"
    elif [[ "${BACKUP_INPUT}" == s3://* ]]; then
        S3_INPUT="${BACKUP_INPUT#s3://}"
        S3_BUCKET="${S3_INPUT%%/*}"
        if [[ "${S3_INPUT}" == */* ]]; then
            S3_INPUT="${S3_INPUT#*/}"
        else
            usage_error "Expected non-empty S3 key or prefix after s3://${S3_BUCKET}/"
        fi
    else
        S3_INPUT="${BACKUP_INPUT#s3:}"
        if [ -z "${S3_INPUT}" ]; then
            usage_error "Expected non-empty S3 key or prefix after s3:"
        fi
    fi

    if [ -z "${S3_INPUT}" ]; then
        usage_error "Expected non-empty S3 key or prefix"
    fi

    for var in PG_RESTORE_S3_ENDPOINT PG_RESTORE_S3_REGION PG_RESTORE_S3_ACCESS_KEY PG_RESTORE_S3_SECRET_KEY; do
        if [ -z "${!var}" ]; then
            error "${var} is not set"
        fi
    done

    if [ -z "${S3_BUCKET}" ]; then
        error "PG_RESTORE_S3_BUCKET is not set"
    fi
}

validate_backup_input() {
    if [ -z "${BACKUP_INPUT}" ]; then
        if is_s3_enabled && [ -n "${PG_RESTORE_S3_PREFIX}" ]; then
            validate_s3_backup_input
        else
            usage_error "Backup source is required unless PG_RESTORE_S3_PREFIX is set and S3 restore is enabled"
        fi
    elif [[ "${BACKUP_INPUT}" == s3:* ]]; then
        if ! is_s3_enabled; then
            error "S3 restore is disabled by PG_RESTORE_S3=${PG_RESTORE_S3}"
        fi
        validate_s3_backup_input
    elif [ ! -f "${BACKUP_INPUT}" ] && [ ! -d "${BACKUP_INPUT}" ]; then
        error "Backup source ${BACKUP_INPUT} not found"
    fi
}

resolve_s3_backup() {
    validate_s3_backup_input

    if is_exact_backup_key "${S3_INPUT}"; then
        S3_KEY="${S3_INPUT}"
    else
        S3_KEY=$(latest_s3_key "${S3_BUCKET}" "${S3_INPUT}")
    fi

    DOWNLOADED_DIR=$(mktemp -d "/tmp/${PG_BASE}.restore.XXXXXX")
    DOWNLOADED_FILE="${DOWNLOADED_DIR}/${S3_KEY##*/}"
    run "Downloading backup s3://${S3_BUCKET}/${S3_KEY}..." \
        aws_env aws --endpoint-url="${PG_RESTORE_S3_ENDPOINT}" s3api get-object --bucket "${S3_BUCKET}" --key "${S3_KEY}" "${DOWNLOADED_FILE}"
    BACKUP_FILE="${DOWNLOADED_FILE}"
}

resolve_backup_source() {
    if [ -z "${BACKUP_INPUT}" ]; then
        if is_s3_enabled && [ -n "${PG_RESTORE_S3_PREFIX}" ]; then
            resolve_s3_backup
        else
            usage_error "Backup source is required unless PG_RESTORE_S3_PREFIX is set and S3 restore is enabled"
        fi
    elif [[ "${BACKUP_INPUT}" == s3:* ]]; then
        if ! is_s3_enabled; then
            error "S3 restore is disabled by PG_RESTORE_S3=${PG_RESTORE_S3}"
        fi
        resolve_s3_backup
    fi
}

verify_backup_source() {
    if [ ! -f "${BACKUP_FILE}" ] && [ ! -d "${BACKUP_FILE}" ]; then
        error "Backup source ${BACKUP_FILE} not found"
    fi

    BACKUP_FILE=$(realpath -m "${BACKUP_FILE}")
}

decrypt_backup() {
    if [[ "${BACKUP_FILE}" != *.enc ]]; then
        return
    fi

    if [ -z "${PG_RESTORE_SECRET}" ]; then
        error "Backup file ${BACKUP_FILE} is encrypted but PG_RESTORE_SECRET is not set"
    fi

    DECRYPTED_FILE="${BACKUP_FILE%.enc}"
    rm -rf "${DECRYPTED_FILE}"
    run "Decrypting backup ${BACKUP_FILE}..." \
        openssl enc -aes-256-cbc -base64 -pbkdf2 -pass "pass:${PG_RESTORE_SECRET}" -d -in "${BACKUP_FILE}" -out "${DECRYPTED_FILE}"

    if [ ! -f "${DECRYPTED_FILE}" ]; then
        error "Failed to decrypt ${BACKUP_FILE} to ${DECRYPTED_FILE}"
    fi

    BACKUP_FILE="${DECRYPTED_FILE}"
}

decompress_backup() {
    if [[ "${BACKUP_FILE}" != *.sql.gz ]] && [[ "${BACKUP_FILE}" != *.tar.gz ]]; then
        return
    fi

    if ! is_gzip_file "${BACKUP_FILE}"; then
        return
    fi

    if [[ "${BACKUP_FILE}" == *.sql.gz ]]; then
        DECOMPRESSED_FILE=$(mktemp "/tmp/${PG_BASE}.restore.XXXXXX.sql")
    else
        DECOMPRESSED_FILE=$(mktemp "/tmp/${PG_BASE}.restore.XXXXXX.tar")
    fi
    run_output "${DECOMPRESSED_FILE}" "Decompressing backup ${BACKUP_FILE}..." \
        gzip -dc "${BACKUP_FILE}"

    if [ ! -f "${DECOMPRESSED_FILE}" ]; then
        error "Failed to decompress ${BACKUP_FILE} to ${DECOMPRESSED_FILE}"
    fi

    BACKUP_FILE="${DECOMPRESSED_FILE}"
}

extract_backup() {
    local restore_toc

    if [[ "${BACKUP_FILE}" != *.tar ]] && [[ "${BACKUP_FILE}" != *.tar.gz ]]; then
        return
    fi

    EXTRACTED_DIR=$(mktemp -d "/tmp/${PG_BASE}.restore.XXXXXX.dir")
    run "Extracting PostgreSQL directory-format archive ${BACKUP_FILE}..." \
        tar -xf "${BACKUP_FILE}" -C "${EXTRACTED_DIR}"

    if [ -f "${EXTRACTED_DIR}/toc.dat" ]; then
        BACKUP_FILE="${EXTRACTED_DIR}"
    else
        restore_toc=$(find "${EXTRACTED_DIR}" -mindepth 2 -maxdepth 2 -type f -name toc.dat -print -quit)
        if [ -z "${restore_toc}" ]; then
            error "Extracted archive ${BACKUP_FILE} does not contain PostgreSQL directory-format toc.dat"
        fi
        BACKUP_FILE=$(dirname "${restore_toc}")
    fi
}

prepare_backup_file() {
    resolve_backup_source
    verify_backup_source
    decrypt_backup
    decompress_backup
    extract_backup
}

init_timestamps() {
    SCRIPT_START=$(date -u '+%s.%3N')
    TIME_TAG=$(date -d "@${SCRIPT_START%.*}" -u '+%y%m%d%H%M%S')
    TIME_UTC=$(date -d "@${SCRIPT_START%.*}" -u '+%Y-%m-%d %H:%M:%S')
}

log_started() {
    info "Started at ${TIME_UTC} UTC"
}

init_restore_context() {
    RESTORE_DB_NAME="${PG_BASE}"
    ARCHIVE_DB_NAME="${PG_BASE}_archive_${TIME_TAG}"
    PG_RESTORE_CREATE_EXTENSIONS="${PG_RESTORE_CREATE_EXTENSIONS:-}"
}

docker_pg() {
    docker run --rm --name "pg-recover-${PG_BASE}" --network host -i -e "PGPASSWORD=${PG_PASS}" -e "PGSSLMODE=${PG_SSL:-disable}" "${PG_IMAGE}" "$@"
}

docker_pg_with_backup() {
    docker run --rm --name "pg-recover-${PG_BASE}" --network host -v "${BACKUP_FILE}:/backup.dump:ro" -i -e "PGPASSWORD=${PG_PASS}" -e "PGSSLMODE=${PG_SSL:-disable}" "${PG_IMAGE}" "$@"
}

docker_pg_with_backup_and_restore_list() {
    docker run --rm --name "pg-recover-${PG_BASE}" --network host -v "${BACKUP_FILE}:/backup.dump:ro" -v "${RESTORE_LIST_FILE}:/restore.list:ro" -i -e "PGPASSWORD=${PG_PASS}" -e "PGSSLMODE=${PG_SSL:-disable}" "${PG_IMAGE}" "$@"
}

create_database() {
    local database_name="$1"

    run "Creating database ${database_name}..." \
        docker_pg psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d postgres -c "CREATE DATABASE ${database_name} WITH TEMPLATE template0 OWNER ${PG_USER}"
}

database_exists() {
    local database_name="$1"
    local exists

    exists=$(docker_pg psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d postgres -Atq -v "database_name=${database_name}" -c "SELECT 1 FROM pg_database WHERE datname = :'database_name'")
    [ "${exists}" = "1" ]
}

drop_database() {
    local database_name="$1"

    run "Disabling connections to ${database_name}..." \
        docker_pg psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d postgres -c "ALTER DATABASE ${database_name} WITH ALLOW_CONNECTIONS false" || true
    run "Terminating active connections to ${database_name}..." \
        docker_pg psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE pid <> pg_backend_pid() AND datname = '${database_name}'" || true
    run "Dropping database ${database_name}..." \
        docker_pg psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d postgres -c "DROP DATABASE ${database_name}"
}

drop_user_schemas() {
    run "Dropping user schemas from ${PG_BASE}..." \
        docker_pg psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${PG_BASE}" -v ON_ERROR_STOP=1 <<'SQL'
DO $$
DECLARE
    schema_name text;
BEGIN
    FOR schema_name IN
        SELECT nspname
        FROM pg_namespace
        WHERE nspname <> 'information_schema'
          AND nspname !~ '^pg_'
    LOOP
        EXECUTE format('DROP SCHEMA IF EXISTS %I CASCADE', schema_name);
    END LOOP;

    CREATE SCHEMA IF NOT EXISTS public;
END
$$;
SQL
}

is_plain_sql_backup() {
    [ "${PG_RESTORE_FORMAT}" = "sql" ]
}

detect_backup_format() {
    if [ -n "${PG_RESTORE_FORMAT}" ]; then
        return
    fi

    if [ -d "${BACKUP_FILE}" ]; then
        if [ ! -f "${BACKUP_FILE}/toc.dat" ]; then
            error "Directory backup source ${BACKUP_FILE} does not contain PostgreSQL directory-format toc.dat"
        fi
        PG_RESTORE_FORMAT=dir
        return
    fi

    case "${BACKUP_FILE}" in
    *.sql) PG_RESTORE_FORMAT=sql ;;
    *.tar) PG_RESTORE_FORMAT=dir ;;
    *.dump) PG_RESTORE_FORMAT=cst ;;
    *) error "Could not determine backup format from ${BACKUP_FILE}; set PG_RESTORE_FORMAT=sql, dir, or cst" ;;
    esac
}

create_extensions() {
    local extension

    if [ -z "${PG_RESTORE_CREATE_EXTENSIONS}" ]; then
        return
    fi

    echo "Creating extensions: ${PG_RESTORE_CREATE_EXTENSIONS}"
    for extension in ${PG_RESTORE_CREATE_EXTENSIONS}; do
        run "Creating extension ${extension}..." \
            docker_pg psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${RESTORE_DB_NAME}" -c "CREATE EXTENSION IF NOT EXISTS ${extension}"
    done
}

prepare_restore_database() {
    if is_true "${PG_RESTORE_NO_RECREATE}" PG_RESTORE_NO_RECREATE; then
        info "Restoring directly into existing database ${RESTORE_DB_NAME}"
        drop_user_schemas
    elif ! is_true "${PG_RESTORE_NO_PREPARE}" PG_RESTORE_NO_PREPARE; then
        RESTORE_DB_NAME="${PG_BASE}_prepare_${TIME_TAG}"
        create_database "${RESTORE_DB_NAME}"
        PREPARE_DB_CREATED=1
        PREPARE_DB_NAME="${RESTORE_DB_NAME}"
        create_extensions
    else
        if database_exists "${RESTORE_DB_NAME}"; then
            drop_database "${RESTORE_DB_NAME}"
        fi
        create_database "${RESTORE_DB_NAME}"
        create_extensions
    fi
}

restore_plain_sql_backup() {
    if [[ "${BACKUP_FILE}" == *.sql.gz ]]; then
        run "Restoring gzip SQL backup into ${RESTORE_DB_NAME}..." \
            docker_pg_with_backup sh -c "gunzip -c /backup.dump | psql -h \"${PG_HOST}\" -p \"${PG_PORT}\" -U \"${PG_USER}\" -d \"${RESTORE_DB_NAME}\" -v ON_ERROR_STOP=1"
    else
        run "Restoring SQL backup into ${RESTORE_DB_NAME}..." \
            docker_pg_with_backup psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${RESTORE_DB_NAME}" -f /backup.dump -v ON_ERROR_STOP=1
    fi
}

restore_archive_backup_with_filtered_list() {
    local restore_format_flag_value

    RESTORE_LIST_FILE=$(mktemp "/tmp/${PG_BASE}.restore.XXXXXX.list")
    restore_format_flag_value=$(restore_format_flag)

    run_output "${RESTORE_LIST_FILE}" "Listing ${PG_RESTORE_FORMAT} backup contents..." \
        docker_pg_with_backup pg_restore -l -F "${restore_format_flag_value}" /backup.dump

    awk -v excluded="${PG_RESTORE_EXCLUDE_EXTENSIONS}" '
        BEGIN {
            split(excluded, names, /[[:space:]]+/)
            for (name_index in names) {
                if (names[name_index] != "") {
                    excluded_extensions[names[name_index]] = 1
                }
            }
        }
        {
            split($0, fields, /[[:space:]]+/)
            for (extension in excluded_extensions) {
                if (fields[4] == "EXTENSION" && fields[6] == extension) {
                    next
                }
                if (fields[4] == "COMMENT" && fields[6] == "EXTENSION" && fields[7] == extension) {
                    next
                }
                if (fields[4] == "ACL" && fields[6] == "EXTENSION" && fields[7] == extension) {
                    next
                }
            }
            print
        }
    ' "${RESTORE_LIST_FILE}" >"${RESTORE_LIST_FILE}.filtered"
    mv "${RESTORE_LIST_FILE}.filtered" "${RESTORE_LIST_FILE}"

    run "Restoring ${PG_RESTORE_FORMAT} backup into ${RESTORE_DB_NAME} without extensions: ${PG_RESTORE_EXCLUDE_EXTENSIONS}..." \
        docker_pg_with_backup_and_restore_list pg_restore -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${RESTORE_DB_NAME}" --no-owner --no-privileges --no-comments -j "${PG_RESTORE_CONCURRENCY}" -F "${restore_format_flag_value}" -L /restore.list -v /backup.dump
}

restore_backup() {
    local restore_format_flag_value

    if is_plain_sql_backup; then
        restore_plain_sql_backup
    elif [ -n "${PG_RESTORE_EXCLUDE_EXTENSIONS}" ]; then
        restore_archive_backup_with_filtered_list
    else
        restore_format_flag_value=$(restore_format_flag)
        run "Restoring ${PG_RESTORE_FORMAT} backup into ${RESTORE_DB_NAME}..." \
            docker_pg_with_backup pg_restore -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${RESTORE_DB_NAME}" --no-owner --no-privileges --no-comments -j "${PG_RESTORE_CONCURRENCY}" -F "${restore_format_flag_value}" -v /backup.dump
    fi
}

vacuum_restored_database() {
    if is_true "${PG_RESTORE_NO_VACUUM}" PG_RESTORE_NO_VACUUM; then
        return
    fi

    run "Setting statement timeout for ${RESTORE_DB_NAME}..." \
        docker_pg psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${RESTORE_DB_NAME}" -c "ALTER ROLE ${PG_USER} SET statement_timeout = 300000"
    run "Analyzing restored database ${RESTORE_DB_NAME}..." \
        docker_pg vacuumdb -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${RESTORE_DB_NAME}" --echo --analyze-in-stages -j "${PG_RESTORE_CONCURRENCY}"
    run "Resetting statement timeout for ${RESTORE_DB_NAME}..." \
        docker_pg psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${RESTORE_DB_NAME}" -c "ALTER ROLE ${PG_USER} RESET statement_timeout"
}

promote_restored_database() {
    if is_true "${PG_RESTORE_NO_PREPARE}" PG_RESTORE_NO_PREPARE || is_true "${PG_RESTORE_NO_RECREATE}" PG_RESTORE_NO_RECREATE; then
        return
    fi

    run "Disabling connections to ${PG_BASE}..." \
        docker_pg psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d postgres -c "ALTER DATABASE ${PG_BASE} WITH ALLOW_CONNECTIONS false" || true
    run "Terminating active connections to ${PG_BASE}..." \
        docker_pg psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE pid <> pg_backend_pid() AND datname = '${PG_BASE}'" || true
    run "Archiving current database ${PG_BASE}..." \
        docker_pg psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d postgres -c "ALTER DATABASE ${PG_BASE} RENAME TO ${ARCHIVE_DB_NAME}" || true
    run "Promoting restored database ${RESTORE_DB_NAME}..." \
        docker_pg psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d postgres -c "ALTER DATABASE ${RESTORE_DB_NAME} RENAME TO ${PG_BASE}"
    PREPARE_DB_PROMOTED=1
    run "Dropping archive database ${ARCHIVE_DB_NAME}..." \
        docker_pg psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d postgres -c "DROP DATABASE IF EXISTS ${ARCHIVE_DB_NAME}"
}

verify_restore() {
    run "Checking databases..." \
        docker_pg psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${PG_BASE}" -c '\l'

    run "Checking tables..." \
        docker_pg psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${PG_BASE}" -c '\dt *.*'
}

finish() {
    SCRIPT_END=$(date -u '+%s.%3N')
    SCRIPT_ELAPSED=$(echo "scale=3; $SCRIPT_END - $SCRIPT_START" | bc)
    info "Finished in ${SCRIPT_ELAPSED}s"
}

main() {
    init_config "$@"
    validate_backup_input
    init_timestamps
    log_started
    init_cleanup
    prepare_backup_file
    init_restore_context
    detect_backup_format
    prepare_restore_database
    restore_backup
    vacuum_restored_database
    promote_restored_database
    verify_restore
    finish
}

main "$@"
