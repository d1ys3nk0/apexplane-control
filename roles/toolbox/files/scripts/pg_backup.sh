#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
TOOLBOX_REDACT_VARS="PG_PASS PG_BACKUP_SECRET PG_BACKUP_S3_SECRET_KEY"
# shellcheck source=../lib/helpers.sh
source "${SCRIPT_DIR}/../lib/helpers.sh"

usage() {
    cat >&2 <<'USAGE'
Usage: pg_backup [backup-root]

Creates a PostgreSQL backup for PG_BASE.
Defaults backup-root to ~/backups/postgres.

Required environment:
  PG_IMAGE, PG_HOST, PG_PORT, PG_USER, PG_PASS, PG_BASE

Optional environment:
  PG_SSL=require|disable (defaults to disable)
  PG_BACKUP_FORMAT=sql|dir|cst (defaults to dir)
  PG_BACKUP_CONCURRENCY=<jobs> (defaults to 1; dir format only)
  PG_BACKUP_PREFIX=<relative-path>
  PG_BACKUP_SECRET=<passphrase>
  PG_BACKUP_S3=0|false
  PG_BACKUP_S3_ENDPOINT=<endpoint>
  PG_BACKUP_S3_REGION=<region>
  PG_BACKUP_S3_BUCKET=<bucket>
  PG_BACKUP_S3_PREFIX=<key-prefix>
  PG_BACKUP_S3_ACCESS_KEY=<access-key>
  PG_BACKUP_S3_SECRET_KEY=<secret-key>

Example:
  dotenv /path/to/app.env pg_backup
  dotenv /path/to/app.env pg_backup /var/backups/postgres
USAGE
}

is_s3_enabled() {
    case "${PG_BACKUP_S3}" in
    0 | false | False | FALSE) return 1 ;;
    *) return 0 ;;
    esac
}

init_config() {
    if [ "$#" -gt 1 ]; then
        _usage_error "Expected 0 or 1 arguments, got $#"
    fi

    PG_IMAGE="${PG_IMAGE:-}"
    PG_BACKUP_ROOT_INPUT="${1:-}"
    PG_BACKUP_ROOT="${PG_BACKUP_ROOT_INPUT:-${HOME}/backups/postgres}"
    PG_BACKUP_FORMAT="${PG_BACKUP_FORMAT:-dir}"
    PG_BACKUP_CONCURRENCY="${PG_BACKUP_CONCURRENCY:-1}"
    case "${PG_BACKUP_FORMAT}" in
    sql) BACKUP_EXT="sql.gz" ;;
    dir) BACKUP_EXT="tar" ;;
    cst) BACKUP_EXT="dump" ;;
    *) _usage_error "PG_BACKUP_FORMAT must be sql, dir, or cst" ;;
    esac
    PG_BACKUP_PREFIX="${PG_BACKUP_PREFIX:-}"
    PG_BACKUP_SECRET="${PG_BACKUP_SECRET:-}"
    PG_BACKUP_S3="${PG_BACKUP_S3:-}"
    PG_BACKUP_S3_ENDPOINT="${PG_BACKUP_S3_ENDPOINT:-}"
    PG_BACKUP_S3_PREFIX="${PG_BACKUP_S3_PREFIX:-}"
    PG_BACKUP_S3_REGION="${PG_BACKUP_S3_REGION:-}"
    PG_BACKUP_S3_BUCKET="${PG_BACKUP_S3_BUCKET:-}"
    PG_BACKUP_S3_ACCESS_KEY="${PG_BACKUP_S3_ACCESS_KEY:-}"
    PG_BACKUP_S3_SECRET_KEY="${PG_BACKUP_S3_SECRET_KEY:-}"

    _require_vars "PG_IMAGE" "PG_HOST" "PG_PORT" "PG_USER" "PG_PASS" "PG_BASE" "PG_BACKUP_ROOT"
    if [ "${PG_BACKUP_FORMAT}" = "dir" ]; then
        _require_positive_integer "${PG_BACKUP_CONCURRENCY}" PG_BACKUP_CONCURRENCY
    fi
    PG_BACKUP_S3_PREFIX="${PG_BACKUP_S3_PREFIX:-${PG_BASE}}"
}

init_timestamps() {
    TIME_TAG=$(date -d "@${TOOLBOX_SCRIPT_START%.*}" -u '+%y%m%d%H%M%S')
    TIME_UTC=$(date -d "@${TOOLBOX_SCRIPT_START%.*}" -u '+%Y-%m-%d %H:%M:%S')

    _info "Started at ${TIME_UTC} UTC"
}

init_backup_paths() {
    BACKUP_NAME="${PG_BASE}-${TIME_TAG}"
    BACKUP_BASE="${PG_BASE}"
    BACKUP_LATEST_DIR=$(realpath -m "${PG_BACKUP_ROOT}/${BACKUP_BASE}")

    if [ -n "${PG_BACKUP_ROOT_INPUT}" ]; then
        BACKUP_BASE=""
        BACKUP_LATEST_DIR=$(realpath -m "${PG_BACKUP_ROOT}")
    fi

    if [ -n "${PG_BACKUP_ROOT_INPUT}" ] && [ -n "${PG_BACKUP_PREFIX}" ]; then
        BACKUP_BASE="${PG_BACKUP_PREFIX}"
    fi

    if [ -n "${BACKUP_BASE}" ]; then
        BACKUP_DIR=$(realpath -m "${PG_BACKUP_ROOT}/${BACKUP_BASE}")
    else
        BACKUP_DIR=$(realpath -m "${PG_BACKUP_ROOT}")
    fi

    BACKUP_FILE="${BACKUP_DIR}/${BACKUP_NAME}.${BACKUP_EXT}"
}

create_backup() {
    local backup_dump_path

    _info "Checking database tables..."
    _cmd docker run --name "pg-backup-${PG_BASE}" --rm --network host -i -e "PGPASSWORD=${PG_PASS}" -e "PGSSLMODE=${PG_SSL:-disable}" "${PG_IMAGE}" \
        psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${PG_BASE}" -c '\dt *.*'

    _info "Creating ${BACKUP_DIR}"
    _cmd mkdir -p "${BACKUP_DIR}"

    if [ "${PG_BACKUP_FORMAT}" = "sql" ]; then
        _info "Creating SQL backup ${BACKUP_FILE}..."
        _cmd docker run --rm --name "pg-backup-${PG_BASE}" --network host --user "$(id -u):$(id -g)" -v "${BACKUP_DIR}:/backup" -i -e "PGPASSWORD=${PG_PASS}" -e "PGSSLMODE=${PG_SSL:-disable}" "${PG_IMAGE}" \
            sh -c "pg_dump -h \"\$1\" -p \"\$2\" -U \"\$3\" -d \"\$4\" --no-owner --no-privileges --no-comments -Fp | gzip -c > \"\$5\"" sh "${PG_HOST}" "${PG_PORT}" "${PG_USER}" "${PG_BASE}" "/backup/${BACKUP_NAME}.sql.gz"
    elif [ "${PG_BACKUP_FORMAT}" = "dir" ]; then
        backup_dump_path="${BACKUP_DIR}/${BACKUP_NAME}.dir"
        _cmd rm -rf "${backup_dump_path}"
        _info "Creating dir-format backup ${backup_dump_path}..."
        _cmd docker run --rm --name "pg-backup-${PG_BASE}" --network host --user "$(id -u):$(id -g)" -v "${BACKUP_DIR}:/backup" -i -e "PGPASSWORD=${PG_PASS}" -e "PGSSLMODE=${PG_SSL:-disable}" "${PG_IMAGE}" \
            pg_dump -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${PG_BASE}" --no-owner --no-privileges --no-comments -j "${PG_BACKUP_CONCURRENCY}" -f "/backup/${BACKUP_NAME}.dir" -Fd
        _info "Archiving dir-format backup ${BACKUP_FILE} without compression..."
        _cmd tar -cf "${BACKUP_FILE}" -C "${BACKUP_DIR}" "${BACKUP_NAME}.dir"
        _cmd rm -rf "${backup_dump_path}"
    else
        _info "Creating cst-format backup ${BACKUP_FILE}..."
        _cmd docker run --rm --name "pg-backup-${PG_BASE}" --network host --user "$(id -u):$(id -g)" -v "${BACKUP_DIR}:/backup" -i -e "PGPASSWORD=${PG_PASS}" -e "PGSSLMODE=${PG_SSL:-disable}" "${PG_IMAGE}" \
            pg_dump -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${PG_BASE}" --no-owner --no-privileges --no-comments -f "/backup/${BACKUP_NAME}.dump" -Fc
    fi
}

encrypt_backup() {
    if [ -z "${PG_BACKUP_SECRET}" ]; then
        return
    fi

    _info "Encrypting backup ${BACKUP_FILE}.enc..."
    _cmd openssl enc -aes-256-cbc -base64 -pbkdf2 -pass "pass:${PG_BACKUP_SECRET}" -e -in "${BACKUP_FILE}" -out "${BACKUP_FILE}.enc"
    _cmd rm -f "${BACKUP_FILE}"
    BACKUP_EXT="${BACKUP_EXT}.enc"
    BACKUP_FILE="${BACKUP_DIR}/${BACKUP_NAME}.${BACKUP_EXT}"
}

verify_backup_file() {
    if [ ! -f "${BACKUP_FILE}" ]; then
        _error "Backup file ${BACKUP_FILE} should be created, but not found"
    fi

    _info "Created backup: ${BACKUP_FILE}"
}

link_latest_backup() {
    _info "Linking backup to ${BACKUP_LATEST_DIR}/latest.${BACKUP_EXT}"
    _cmd ln -sf "${BACKUP_FILE}" "${BACKUP_LATEST_DIR}/latest.${BACKUP_EXT}"
}

upload_backup() {
    local var

    if [ -z "${PG_BACKUP_S3_BUCKET}" ]; then
        _info "Backup uploading is not configured, skipping..."
        return
    fi

    if ! is_s3_enabled; then
        _info "S3 backup uploading is disabled by PG_BACKUP_S3=${PG_BACKUP_S3}, skipping..."
        return
    fi

    for var in PG_BACKUP_S3_ENDPOINT PG_BACKUP_S3_REGION PG_BACKUP_S3_ACCESS_KEY PG_BACKUP_S3_SECRET_KEY; do
        if [ -z "${!var}" ]; then
            _error "${var} is not set"
        fi
    done

    BACKUP_KEY="${PG_BACKUP_S3_PREFIX%/}"
    if [ -n "${PG_BACKUP_PREFIX}" ]; then
        BACKUP_KEY="${BACKUP_KEY}/${PG_BACKUP_PREFIX}"
    fi
    BACKUP_KEY="${BACKUP_KEY%/}/${BACKUP_NAME}.${BACKUP_EXT}"
    _info "Uploading ${BACKUP_FILE} to s3://${PG_BACKUP_S3_BUCKET}/${BACKUP_KEY} via ${PG_BACKUP_S3_ENDPOINT} with PG_BACKUP_S3_REGION=${PG_BACKUP_S3_REGION}"
    BACKUP_MD5_BASE64=$(openssl md5 -binary "${BACKUP_FILE}" | base64)
    _info "Uploading backup to S3..."
    _cmd env AWS_REGION="${PG_BACKUP_S3_REGION}" AWS_ACCESS_KEY_ID="${PG_BACKUP_S3_ACCESS_KEY}" AWS_SECRET_ACCESS_KEY="${PG_BACKUP_S3_SECRET_KEY}" \
        aws --endpoint-url="${PG_BACKUP_S3_ENDPOINT}" s3api put-object --bucket "${PG_BACKUP_S3_BUCKET}" --key "${BACKUP_KEY}" --body "${BACKUP_FILE}" --content-md5 "${BACKUP_MD5_BASE64}"
}

prune_old_backups() {
    _info "Clean up ${BACKUP_DIR} from backups older than 24 hours"
    _cmd find "${BACKUP_DIR}" -type f -mmin +1440 -exec rm {} \;
}

finish() {
    SCRIPT_END=$(date -u '+%s.%3N')
    SCRIPT_ELAPSED=$(echo "scale=3; $SCRIPT_END - $TOOLBOX_SCRIPT_START" | bc)
    _info "Finished in ${SCRIPT_ELAPSED}s"
}

main() {
    init_config "$@"
    init_timestamps
    init_backup_paths
    create_backup
    encrypt_backup
    verify_backup_file
    link_latest_backup
    upload_backup
    prune_old_backups
    finish
}

main "$@"
