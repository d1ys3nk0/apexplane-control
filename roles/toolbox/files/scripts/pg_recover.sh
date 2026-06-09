#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
TOOLBOX_REDACT_VARS="PG_PASS PG_RECOVER_SECRET PG_RECOVER_S3_SECRET_KEY"
# shellcheck source=../lib/helpers.sh
source "${SCRIPT_DIR}/../lib/helpers.sh"

usage() {
    cat >&2 <<'USAGE'
Usage: pg_recover [backup-file|s3:key|s3:prefix|s3://bucket/key|s3://bucket/prefix]

Restores a cst-format dump, PostgreSQL dir-format directory or uncompressed tar
archive, plain .sql, gzip .sql.gz, gzip .tar.gz, or encrypted .enc backup into
PG_BASE.
With no source argument and S3 enabled, restores the latest backup under
PG_RECOVER_S3_PREFIX. Without PG_RECOVER_S3_PREFIX, pass a local backup file or S3
source argument.

Required environment:
  PG_IMAGE, PG_HOST, PG_PORT, PG_USER, PG_PASS, PG_BASE

Optional environment:
  PG_SSL=require|disable (defaults to disable)
  PG_RECOVER_NO_RECREATE=true|false
  PG_RECOVER_NO_PREPARE=true|false
  PG_RECOVER_NO_VACUUM=true|false
  PG_RECOVER_FORMAT=sql|dir|cst (optional override; defaults to extension detection)
  PG_RECOVER_CONCURRENCY=<jobs> (defaults to nproc)
  PG_RECOVER_CREATE_EXTENSIONS="extension_a extension_b"
  PG_RECOVER_EXCLUDE_EXTENSIONS="extension_a extension_b"
  PG_RECOVER_SECRET=<passphrase>
  PG_RECOVER_S3=0|false
  PG_RECOVER_S3_ENDPOINT=<endpoint>
  PG_RECOVER_S3_REGION=<region>
  PG_RECOVER_S3_BUCKET=<bucket>
  PG_RECOVER_S3_PREFIX=<key-prefix>
  PG_RECOVER_S3_ACCESS_KEY=<access-key>
  PG_RECOVER_S3_SECRET_KEY=<secret-key>
Examples:
  dotenv /path/to/app.env pg_recover /var/backups/postgres/latest.tar
  dotenv /path/to/app.env pg_recover
  dotenv /path/to/app.env pg_recover s3:source_database/
  dotenv /path/to/app.env pg_recover s3://bucket/source_database/backup.tar
USAGE
}

is_s3_enabled() {
    case "${PG_RECOVER_S3}" in
    0 | false | False | FALSE) return 1 ;;
    *) return 0 ;;
    esac
}

cleanup() {
    local status="${1:-$?}"
    local cleanup_status=0

    set +e

    if [ "${PREPARE_DB_CREATED:-0}" = "1" ] && [ "${PREPARE_DB_PROMOTED:-0}" != "1" ] && [ -n "${PREPARE_DB_NAME:-}" ]; then
        _warn "Restore failed before promotion; removing prepare database ${PREPARE_DB_NAME}"
        drop_database "${PREPARE_DB_NAME}" || cleanup_status=$?
    fi
    if [ -n "${DECRYPTED_FILE:-}" ] && [ -f "${DECRYPTED_FILE}" ]; then
        _info "Cleaning up temporary decrypted file ${DECRYPTED_FILE}"
        _cmd rm -f "${DECRYPTED_FILE}" || cleanup_status=$?
    fi
    if [ -n "${DECOMPRESSED_FILE:-}" ] && [ -f "${DECOMPRESSED_FILE}" ]; then
        _info "Cleaning up temporary decompressed file ${DECOMPRESSED_FILE}"
        _cmd rm -f "${DECOMPRESSED_FILE}" || cleanup_status=$?
    fi
    if [ -n "${EXTRACTED_DIR:-}" ] && [ -d "${EXTRACTED_DIR}" ]; then
        _info "Cleaning up temporary extracted directory ${EXTRACTED_DIR}"
        _cmd rm -rf "${EXTRACTED_DIR}" || cleanup_status=$?
    fi
    if [ -n "${DOWNLOADED_DIR:-}" ] && [ -d "${DOWNLOADED_DIR}" ]; then
        _info "Cleaning up temporary download directory ${DOWNLOADED_DIR}"
        _cmd rm -rf "${DOWNLOADED_DIR}" || cleanup_status=$?
    fi
    if [ -n "${RESTORE_LIST_FILE:-}" ] && [ -f "${RESTORE_LIST_FILE}" ]; then
        _info "Cleaning up temporary restore list ${RESTORE_LIST_FILE}"
        _cmd rm -f "${RESTORE_LIST_FILE}" || cleanup_status=$?
    fi

    if [ "${status}" -eq 0 ] && [ "${cleanup_status}" -ne 0 ]; then
        status="${cleanup_status}"
    fi

    finish "${status}"
    exit "${status}"
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
    case "${PG_RECOVER_FORMAT}" in
    dir) printf 'd' ;;
    cst) printf 'c' ;;
    *) _usage_error "PG_RECOVER_FORMAT must be sql, dir, or cst" ;;
    esac
}

aws_env() {
    env AWS_REGION="${PG_RECOVER_S3_REGION}" AWS_ACCESS_KEY_ID="${PG_RECOVER_S3_ACCESS_KEY}" AWS_SECRET_ACCESS_KEY="${PG_RECOVER_S3_SECRET_KEY}" "$@"
}

latest_s3_key() {
    local bucket="${1}"
    local prefix="${2}"
    local key

    # shellcheck disable=SC2016
    key=$(
        aws_env aws --endpoint-url="${PG_RECOVER_S3_ENDPOINT}" s3api list-objects-v2 \
            --bucket "${bucket}" \
            --prefix "${prefix}" \
            --query 'sort_by(not_null(Contents, `[]`)[?ends_with(Key, `.dump`) || ends_with(Key, `.dump.enc`) || ends_with(Key, `.sql`) || ends_with(Key, `.sql.enc`) || ends_with(Key, `.sql.gz`) || ends_with(Key, `.sql.gz.enc`) || ends_with(Key, `.tar`) || ends_with(Key, `.tar.enc`) || ends_with(Key, `.tar.gz`) || ends_with(Key, `.tar.gz.enc`)], &LastModified)[-1].Key' \
            --output text
    )

    if [ -z "${key}" ] || [ "${key}" = "None" ]; then
        _error "No backup objects found in s3://${bucket}/${prefix}"
    fi

    echo "${key}"
}

init_config() {
    if [ "$#" -gt 1 ]; then
        _usage_error "Expected 0 or 1 arguments, got $#"
    fi

    BACKUP_INPUT="${1:-}"
    PG_IMAGE="${PG_IMAGE:-}"
    PG_RECOVER_SECRET="${PG_RECOVER_SECRET:-}"
    PG_RECOVER_S3_ENDPOINT="${PG_RECOVER_S3_ENDPOINT:-}"
    PG_RECOVER_S3_PREFIX="${PG_RECOVER_S3_PREFIX:-}"
    PG_RECOVER_S3_REGION="${PG_RECOVER_S3_REGION:-}"
    PG_RECOVER_S3_BUCKET="${PG_RECOVER_S3_BUCKET:-}"
    PG_RECOVER_S3_ACCESS_KEY="${PG_RECOVER_S3_ACCESS_KEY:-}"
    PG_RECOVER_S3_SECRET_KEY="${PG_RECOVER_S3_SECRET_KEY:-}"
    PG_RECOVER_S3="${PG_RECOVER_S3:-}"
    PG_RECOVER_NO_RECREATE="${PG_RECOVER_NO_RECREATE:-}"
    PG_RECOVER_NO_PREPARE="${PG_RECOVER_NO_PREPARE:-}"
    PG_RECOVER_NO_VACUUM="${PG_RECOVER_NO_VACUUM:-}"
    PG_RECOVER_FORMAT="${PG_RECOVER_FORMAT:-}"
    PG_RECOVER_CONCURRENCY="${PG_RECOVER_CONCURRENCY:-$(nproc)}"
    PG_RECOVER_EXCLUDE_EXTENSIONS="${PG_RECOVER_EXCLUDE_EXTENSIONS:-}"

    _require_vars "PG_IMAGE" "PG_HOST" "PG_PORT" "PG_USER" "PG_PASS" "PG_BASE"
    _require_positive_integer "${PG_RECOVER_CONCURRENCY}" PG_RECOVER_CONCURRENCY
    case "${PG_RECOVER_FORMAT}" in
    "" | sql | dir | cst) ;;
    *) _usage_error "PG_RECOVER_FORMAT must be sql, dir, or cst" ;;
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
    trap 'cleanup $?' EXIT
}

validate_s3_backup_input() {
    local var

    S3_BUCKET="${PG_RECOVER_S3_BUCKET}"
    if [ -z "${BACKUP_INPUT}" ]; then
        S3_INPUT="${PG_RECOVER_S3_PREFIX}"
    elif [[ "${BACKUP_INPUT}" == s3://* ]]; then
        S3_INPUT="${BACKUP_INPUT#s3://}"
        S3_BUCKET="${S3_INPUT%%/*}"
        if [[ "${S3_INPUT}" == */* ]]; then
            S3_INPUT="${S3_INPUT#*/}"
        else
            _usage_error "Expected non-empty S3 key or prefix after s3://${S3_BUCKET}/"
        fi
    else
        S3_INPUT="${BACKUP_INPUT#s3:}"
        if [ -z "${S3_INPUT}" ]; then
            _usage_error "Expected non-empty S3 key or prefix after s3:"
        fi
    fi

    if [ -z "${S3_INPUT}" ]; then
        _usage_error "Expected non-empty S3 key or prefix"
    fi

    for var in PG_RECOVER_S3_ENDPOINT PG_RECOVER_S3_REGION PG_RECOVER_S3_ACCESS_KEY PG_RECOVER_S3_SECRET_KEY; do
        if [ -z "${!var}" ]; then
            _error "${var} is not set"
        fi
    done

    if [ -z "${S3_BUCKET}" ]; then
        _error "PG_RECOVER_S3_BUCKET is not set"
    fi
}

validate_backup_input() {
    if [ -z "${BACKUP_INPUT}" ]; then
        if is_s3_enabled && [ -n "${PG_RECOVER_S3_PREFIX}" ]; then
            validate_s3_backup_input
        else
            _usage_error "Backup source is required unless PG_RECOVER_S3_PREFIX is set and S3 restore is enabled"
        fi
    elif [[ "${BACKUP_INPUT}" == s3:* ]]; then
        if ! is_s3_enabled; then
            _error "S3 restore is disabled by PG_RECOVER_S3=${PG_RECOVER_S3}"
        fi
        validate_s3_backup_input
    elif [ ! -f "${BACKUP_INPUT}" ] && [ ! -d "${BACKUP_INPUT}" ]; then
        _error "Backup source ${BACKUP_INPUT} not found"
    fi
}

resolve_s3_backup() {
    if is_exact_backup_key "${S3_INPUT}"; then
        S3_KEY="${S3_INPUT}"
    else
        S3_KEY=$(latest_s3_key "${S3_BUCKET}" "${S3_INPUT}")
    fi

    DOWNLOADED_DIR=$(mktemp -d "/tmp/pg-recover.${PG_BASE}.XXXXXX")
    DOWNLOADED_FILE="${DOWNLOADED_DIR}/${S3_KEY##*/}"
    _info "Downloading backup s3://${S3_BUCKET}/${S3_KEY}..."
    _cmd aws_env aws --endpoint-url="${PG_RECOVER_S3_ENDPOINT}" s3api get-object --bucket "${S3_BUCKET}" --key "${S3_KEY}" "${DOWNLOADED_FILE}"
    BACKUP_FILE="${DOWNLOADED_FILE}"
}

resolve_backup_source() {
    if [ -z "${BACKUP_INPUT}" ]; then
        if is_s3_enabled && [ -n "${PG_RECOVER_S3_PREFIX}" ]; then
            resolve_s3_backup
        else
            _usage_error "Backup source is required unless PG_RECOVER_S3_PREFIX is set and S3 restore is enabled"
        fi
    elif [[ "${BACKUP_INPUT}" == s3:* ]]; then
        if ! is_s3_enabled; then
            _error "S3 restore is disabled by PG_RECOVER_S3=${PG_RECOVER_S3}"
        fi
        resolve_s3_backup
    fi
}

verify_backup_source() {
    if [ ! -f "${BACKUP_FILE}" ] && [ ! -d "${BACKUP_FILE}" ]; then
        _error "Backup source ${BACKUP_FILE} not found"
    fi

    BACKUP_FILE=$(realpath -m "${BACKUP_FILE}")
}

decrypt_backup() {
    if [[ "${BACKUP_FILE}" != *.enc ]]; then
        return
    fi

    if [ -z "${PG_RECOVER_SECRET}" ]; then
        _error "Backup file ${BACKUP_FILE} is encrypted but PG_RECOVER_SECRET is not set"
    fi

    DECRYPTED_FILE="${BACKUP_FILE%.enc}"
    _cmd rm -rf "${DECRYPTED_FILE}"
    _info "Decrypting backup ${BACKUP_FILE}..."
    _cmd openssl enc -aes-256-cbc -base64 -pbkdf2 -pass "pass:${PG_RECOVER_SECRET}" -d -in "${BACKUP_FILE}" -out "${DECRYPTED_FILE}"

    if [ ! -f "${DECRYPTED_FILE}" ]; then
        _error "Failed to decrypt ${BACKUP_FILE} to ${DECRYPTED_FILE}"
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
        DECOMPRESSED_FILE=$(mktemp "/tmp/pg-recover.${PG_BASE}.XXXXXX.sql")
    else
        DECOMPRESSED_FILE=$(mktemp "/tmp/pg-recover.${PG_BASE}.XXXXXX.tar")
    fi
    _info "Decompressing backup ${BACKUP_FILE}..."
    _cmd_output "${DECOMPRESSED_FILE}" gzip -dc "${BACKUP_FILE}"

    if [ ! -f "${DECOMPRESSED_FILE}" ]; then
        _error "Failed to decompress ${BACKUP_FILE} to ${DECOMPRESSED_FILE}"
    fi

    BACKUP_FILE="${DECOMPRESSED_FILE}"
}

extract_backup() {
    local restore_toc

    if [[ "${BACKUP_FILE}" != *.tar ]] && [[ "${BACKUP_FILE}" != *.tar.gz ]]; then
        return
    fi

    EXTRACTED_DIR=$(mktemp -d "/tmp/pg-recover.${PG_BASE}.XXXXXX.dir")
    _info "Extracting PostgreSQL directory-format archive ${BACKUP_FILE}..."
    _cmd tar -xf "${BACKUP_FILE}" -C "${EXTRACTED_DIR}"

    if [ -f "${EXTRACTED_DIR}/toc.dat" ]; then
        BACKUP_FILE="${EXTRACTED_DIR}"
    else
        restore_toc=$(find "${EXTRACTED_DIR}" -mindepth 2 -maxdepth 2 -type f -name toc.dat -print -quit)
        if [ -z "${restore_toc}" ]; then
            _error "Extracted archive ${BACKUP_FILE} does not contain PostgreSQL directory-format toc.dat"
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
    TIME_TAG=$(date -d "@${TOOLBOX_SCRIPT_START%.*}" -u '+%y%m%d%H%M%S')
    TIME_UTC=$(date -d "@${TOOLBOX_SCRIPT_START%.*}" -u '+%Y-%m-%d %H:%M:%S')
}

log_started() {
    _info "Started at ${TIME_UTC} UTC"
}

init_restore_context() {
    RESTORE_DB_NAME="${PG_BASE}"
    ARCHIVE_DB_NAME="${PG_BASE}_archive_${TIME_TAG}"
    PG_RECOVER_CREATE_EXTENSIONS="${PG_RECOVER_CREATE_EXTENSIONS:-}"
}

docker_pg() {
    _docker_postgres --name "pg-recover-${PG_BASE}" -- "$@"
}

docker_pg_with_backup() {
    _docker_postgres --name "pg-recover-${PG_BASE}" -v "${BACKUP_FILE}:/backup.dump:ro" -- "$@"
}

docker_pg_with_backup_and_restore_list() {
    _docker_postgres --name "pg-recover-${PG_BASE}" -v "${BACKUP_FILE}:/backup.dump:ro" -v "${RESTORE_LIST_FILE}:/restore.list:ro" -- "$@"
}

create_database() {
    local database_name="$1"

    _info "Creating database ${database_name}..."
    _cmd docker_pg psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d postgres -c "CREATE DATABASE ${database_name} WITH TEMPLATE template0 OWNER ${PG_USER}"
}

database_exists() {
    local database_name="$1"
    local exists

    exists=$(docker_pg psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d postgres -Atq -v "database_name=${database_name}" -c "SELECT 1 FROM pg_database WHERE datname = :'database_name'")
    [ "${exists}" = "1" ]
}

drop_database() {
    local database_name="$1"

    _info "Disabling connections to ${database_name}..."
    _cmd docker_pg psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d postgres -c "ALTER DATABASE ${database_name} WITH ALLOW_CONNECTIONS false" || true
    _info "Terminating active connections to ${database_name}..."
    _cmd docker_pg psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE pid <> pg_backend_pid() AND datname = '${database_name}'" || true
    _info "Dropping database ${database_name}..."
    _cmd docker_pg psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d postgres -c "DROP DATABASE ${database_name}"
}

drop_user_schemas() {
    _info "Dropping user schemas from ${PG_BASE}..."
    _cmd docker_pg psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${PG_BASE}" -v ON_ERROR_STOP=1 <<'SQL'
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
    [ "${PG_RECOVER_FORMAT}" = "sql" ]
}

detect_backup_format() {
    if [ -n "${PG_RECOVER_FORMAT}" ]; then
        return
    fi

    if [ -d "${BACKUP_FILE}" ]; then
        if [ ! -f "${BACKUP_FILE}/toc.dat" ]; then
            _error "Directory backup source ${BACKUP_FILE} does not contain PostgreSQL directory-format toc.dat"
        fi
        PG_RECOVER_FORMAT=dir
        return
    fi

    case "${BACKUP_FILE}" in
    *.sql) PG_RECOVER_FORMAT=sql ;;
    *.tar) PG_RECOVER_FORMAT=dir ;;
    *.dump) PG_RECOVER_FORMAT=cst ;;
    *) _error "Could not determine backup format from ${BACKUP_FILE}; set PG_RECOVER_FORMAT=sql, dir, or cst" ;;
    esac
}

create_extensions() {
    local extension

    if [ -z "${PG_RECOVER_CREATE_EXTENSIONS}" ]; then
        return
    fi

    _info "Creating extensions: ${PG_RECOVER_CREATE_EXTENSIONS}"
    for extension in ${PG_RECOVER_CREATE_EXTENSIONS}; do
        _info "Creating extension ${extension}..."
        _cmd docker_pg psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${RESTORE_DB_NAME}" -c "CREATE EXTENSION IF NOT EXISTS ${extension}"
    done
}

prepare_restore_database() {
    if _is_true "${PG_RECOVER_NO_RECREATE}" PG_RECOVER_NO_RECREATE; then
        _info "Restoring directly into existing database ${RESTORE_DB_NAME}"
        drop_user_schemas
    elif ! _is_true "${PG_RECOVER_NO_PREPARE}" PG_RECOVER_NO_PREPARE; then
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
        _info "Restoring gzip SQL backup into ${RESTORE_DB_NAME}..."
        _cmd docker_pg_with_backup sh -c "gunzip -c /backup.dump | psql -h \"${PG_HOST}\" -p \"${PG_PORT}\" -U \"${PG_USER}\" -d \"${RESTORE_DB_NAME}\" -v ON_ERROR_STOP=1"
    else
        _info "Restoring SQL backup into ${RESTORE_DB_NAME}..."
        _cmd docker_pg_with_backup psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${RESTORE_DB_NAME}" -f /backup.dump -v ON_ERROR_STOP=1
    fi
}

restore_archive_backup_with_filtered_list() {
    local restore_format_flag_value

    RESTORE_LIST_FILE=$(mktemp "/tmp/pg-recover.${PG_BASE}.XXXXXX.list")
    restore_format_flag_value=$(restore_format_flag)

    _info "Listing ${PG_RECOVER_FORMAT} backup contents..."
    _cmd_output "${RESTORE_LIST_FILE}" docker_pg_with_backup pg_restore -l -F "${restore_format_flag_value}" /backup.dump

    awk -v excluded="${PG_RECOVER_EXCLUDE_EXTENSIONS}" '
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
    _cmd mv "${RESTORE_LIST_FILE}.filtered" "${RESTORE_LIST_FILE}"

    _info "Restoring ${PG_RECOVER_FORMAT} backup into ${RESTORE_DB_NAME} without extensions: ${PG_RECOVER_EXCLUDE_EXTENSIONS}..."
    _cmd docker_pg_with_backup_and_restore_list pg_restore -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${RESTORE_DB_NAME}" --no-owner --no-privileges --no-comments -j "${PG_RECOVER_CONCURRENCY}" -F "${restore_format_flag_value}" -L /restore.list -v /backup.dump
}

restore_backup() {
    local restore_format_flag_value

    if is_plain_sql_backup; then
        restore_plain_sql_backup
    elif [ -n "${PG_RECOVER_EXCLUDE_EXTENSIONS}" ]; then
        restore_archive_backup_with_filtered_list
    else
        restore_format_flag_value=$(restore_format_flag)
        _info "Restoring ${PG_RECOVER_FORMAT} backup into ${RESTORE_DB_NAME}..."
        _cmd docker_pg_with_backup pg_restore -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${RESTORE_DB_NAME}" --no-owner --no-privileges --no-comments -j "${PG_RECOVER_CONCURRENCY}" -F "${restore_format_flag_value}" -v /backup.dump
    fi
}

vacuum_restored_database() {
    if _is_true "${PG_RECOVER_NO_VACUUM}" PG_RECOVER_NO_VACUUM; then
        return
    fi

    _info "Setting statement timeout for ${RESTORE_DB_NAME}..."
    _cmd docker_pg psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${RESTORE_DB_NAME}" -c "ALTER ROLE ${PG_USER} SET statement_timeout = 300000"
    _info "Analyzing restored database ${RESTORE_DB_NAME}..."
    _cmd docker_pg vacuumdb -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${RESTORE_DB_NAME}" --echo --analyze-in-stages -j "${PG_RECOVER_CONCURRENCY}"
    _info "Resetting statement timeout for ${RESTORE_DB_NAME}..."
    _cmd docker_pg psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${RESTORE_DB_NAME}" -c "ALTER ROLE ${PG_USER} RESET statement_timeout"
}

promote_restored_database() {
    if _is_true "${PG_RECOVER_NO_PREPARE}" PG_RECOVER_NO_PREPARE || _is_true "${PG_RECOVER_NO_RECREATE}" PG_RECOVER_NO_RECREATE; then
        return
    fi

    _info "Disabling connections to ${PG_BASE}..."
    _cmd docker_pg psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d postgres -c "ALTER DATABASE ${PG_BASE} WITH ALLOW_CONNECTIONS false" || true
    _info "Terminating active connections to ${PG_BASE}..."
    _cmd docker_pg psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE pid <> pg_backend_pid() AND datname = '${PG_BASE}'" || true
    _info "Archiving current database ${PG_BASE}..."
    _cmd docker_pg psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d postgres -c "ALTER DATABASE ${PG_BASE} RENAME TO ${ARCHIVE_DB_NAME}" || true
    _info "Promoting restored database ${RESTORE_DB_NAME}..."
    _cmd docker_pg psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d postgres -c "ALTER DATABASE ${RESTORE_DB_NAME} RENAME TO ${PG_BASE}"
    PREPARE_DB_PROMOTED=1
    _info "Dropping archive database ${ARCHIVE_DB_NAME}..."
    _cmd docker_pg psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d postgres -c "DROP DATABASE IF EXISTS ${ARCHIVE_DB_NAME}"
}

verify_restore() {
    _info "Checking databases..."
    _cmd docker_pg psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${PG_BASE}" -c '\l'

    _info "Checking tables..."
    _cmd docker_pg psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${PG_BASE}" -c '\dt *.*'
}

finish() {
    local status="${1}"

    SCRIPT_END=$(date -u '+%s.%3N')
    SCRIPT_ELAPSED=$(echo "scale=3; $SCRIPT_END - $TOOLBOX_SCRIPT_START" | bc)
    if [ "${status}" -eq 0 ]; then
        _info "Restore completed successfully in ${SCRIPT_ELAPSED}s; ${PG_BASE} is active"
    elif [ "${PREPARE_DB_CREATED:-0}" = "1" ] && [ "${PREPARE_DB_PROMOTED:-0}" != "1" ]; then
        _warn "Restore failed after ${SCRIPT_ELAPSED}s with exit status ${status}; ${PG_BASE} was not promoted"
    elif [ "${PREPARE_DB_PROMOTED:-0}" = "1" ]; then
        _warn "Restore failed after ${SCRIPT_ELAPSED}s with exit status ${status}; ${PG_BASE} may already be promoted"
    else
        _warn "Restore failed after ${SCRIPT_ELAPSED}s with exit status ${status}; check previous errors"
    fi
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
}

main "$@"
