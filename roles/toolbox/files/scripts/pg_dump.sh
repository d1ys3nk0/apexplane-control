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

info() {
    echo "[INFO] $*"
}

error() {
    echo "[ERROR] $*"
    exit 1
}

usage() {
    cat >&2 <<'USAGE'
Usage: pg_dump [backup-root]

Creates a compressed PostgreSQL dump for PG_BASE.
Defaults backup-root to ~/backups/postgres.

Required environment:
  PG_IMAGE, PG_HOST, PG_PORT, PG_USER, PG_PASS, PG_BASE

Optional environment:
  PG_SSL=require|disable (defaults to disable)
  PG_DUMP_FORMAT=sql|dir|cst (defaults to dir)
  PG_DUMP_CONCURRENCY=<jobs> (defaults to 4; dir format only)
  PG_DUMP_PREFIX=<relative-path>
  PG_DUMP_SECRET=<passphrase>
  PG_DUMP_S3=0|false
  PG_DUMP_S3_ENDPOINT=<endpoint>
  PG_DUMP_S3_REGION=<region>
  PG_DUMP_S3_BUCKET=<bucket>
  PG_DUMP_S3_PREFIX=<key-prefix>
  PG_DUMP_S3_ACCESS_KEY=<access-key>
  PG_DUMP_S3_SECRET_KEY=<secret-key>

Example:
  dotenv /path/to/app.env pg_dump
  dotenv /path/to/app.env pg_dump /var/backups/postgres
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
    case "${PG_DUMP_S3}" in
    0 | false | False | FALSE) return 1 ;;
    *) return 0 ;;
    esac
}

require_positive_integer() {
    if [[ ! "${1}" =~ ^[1-9][0-9]*$ ]]; then
        usage_error "${2} must be a positive integer"
    fi
}

init_config() {
    if [ "$#" -gt 1 ]; then
        usage_error "Expected 0 or 1 arguments, got $#"
    fi

    PG_IMAGE="${PG_IMAGE:-}"
    PG_DUMP_ROOT_INPUT="${1:-}"
    PG_DUMP_ROOT="${PG_DUMP_ROOT_INPUT:-${HOME}/backups/postgres}"
    PG_DUMP_FORMAT="${PG_DUMP_FORMAT:-dir}"
    PG_DUMP_CONCURRENCY="${PG_DUMP_CONCURRENCY:-4}"
    case "${PG_DUMP_FORMAT}" in
    sql) BACKUP_EXT="sql.gz" ;;
    dir) BACKUP_EXT="tar.gz" ;;
    cst) BACKUP_EXT="dump" ;;
    *) usage_error "PG_DUMP_FORMAT must be sql, dir, or cst" ;;
    esac
    PG_DUMP_PREFIX="${PG_DUMP_PREFIX:-}"
    PG_DUMP_SECRET="${PG_DUMP_SECRET:-}"
    PG_DUMP_S3="${PG_DUMP_S3:-}"
    PG_DUMP_S3_ENDPOINT="${PG_DUMP_S3_ENDPOINT:-}"
    PG_DUMP_S3_PREFIX="${PG_DUMP_S3_PREFIX:-}"
    PG_DUMP_S3_REGION="${PG_DUMP_S3_REGION:-}"
    PG_DUMP_S3_BUCKET="${PG_DUMP_S3_BUCKET:-}"
    PG_DUMP_S3_ACCESS_KEY="${PG_DUMP_S3_ACCESS_KEY:-}"
    PG_DUMP_S3_SECRET_KEY="${PG_DUMP_S3_SECRET_KEY:-}"

    check_vars "PG_IMAGE" "PG_HOST" "PG_PORT" "PG_USER" "PG_PASS" "PG_BASE" "PG_DUMP_ROOT"
    if [ "${PG_DUMP_FORMAT}" = "dir" ]; then
        require_positive_integer "${PG_DUMP_CONCURRENCY}" PG_DUMP_CONCURRENCY
    fi
    PG_DUMP_S3_PREFIX="${PG_DUMP_S3_PREFIX:-${PG_BASE}}"
}

init_timestamps() {
    SCRIPT_START=$(date -u '+%s.%3N')
    TIME_TAG=$(date -d "@${SCRIPT_START%.*}" -u '+%y%m%d%H%M%S')
    TIME_UTC=$(date -d "@${SCRIPT_START%.*}" -u '+%Y-%m-%d %H:%M:%S')

    info "Started at ${TIME_UTC} UTC"
}

init_backup_paths() {
    BACKUP_NAME="${PG_BASE}-${TIME_TAG}"
    BACKUP_BASE="${PG_BASE}"
    BACKUP_LATEST_DIR=$(realpath -m "${PG_DUMP_ROOT}/${BACKUP_BASE}")

    if [ -n "${PG_DUMP_ROOT_INPUT}" ]; then
        BACKUP_BASE=""
        BACKUP_LATEST_DIR=$(realpath -m "${PG_DUMP_ROOT}")
    fi

    if [ -n "${PG_DUMP_ROOT_INPUT}" ] && [ -n "${PG_DUMP_PREFIX}" ]; then
        BACKUP_BASE="${PG_DUMP_PREFIX}"
    fi

    if [ -n "${BACKUP_BASE}" ]; then
        BACKUP_DIR=$(realpath -m "${PG_DUMP_ROOT}/${BACKUP_BASE}")
    else
        BACKUP_DIR=$(realpath -m "${PG_DUMP_ROOT}")
    fi

    BACKUP_FILE="${BACKUP_DIR}/${BACKUP_NAME}.${BACKUP_EXT}"
}

create_backup() {
    local backup_dump_path

    run "Checking database tables..." \
        docker run --name "pg-backup-${PG_BASE}" --rm --network host -i -e "PGPASSWORD=${PG_PASS}" -e "PGSSLMODE=${PG_SSL:-disable}" "${PG_IMAGE}" \
        psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${PG_BASE}" -c '\dt *.*'

    echo "Creating ${BACKUP_DIR}"
    mkdir -p "${BACKUP_DIR}"

    if [ "${PG_DUMP_FORMAT}" = "sql" ]; then
        # shellcheck disable=SC2016
        run "Creating SQL backup ${BACKUP_FILE}..." \
            docker run --rm --name "pg-backup-${PG_BASE}" --network host --user "$(id -u):$(id -g)" -v "${BACKUP_DIR}:/backup" -i -e "PGPASSWORD=${PG_PASS}" -e "PGSSLMODE=${PG_SSL:-disable}" "${PG_IMAGE}" \
            sh -c 'pg_dump -h "$1" -p "$2" -U "$3" -d "$4" --no-owner --no-privileges --no-comments -Fp | gzip -c > "$5"' sh "${PG_HOST}" "${PG_PORT}" "${PG_USER}" "${PG_BASE}" "/backup/${BACKUP_NAME}.sql.gz"
    elif [ "${PG_DUMP_FORMAT}" = "dir" ]; then
        backup_dump_path="${BACKUP_DIR}/${BACKUP_NAME}.dir"
        rm -rf "${backup_dump_path}"
        run "Creating dir-format backup ${backup_dump_path}..." \
            docker run --rm --name "pg-backup-${PG_BASE}" --network host --user "$(id -u):$(id -g)" -v "${BACKUP_DIR}:/backup" -i -e "PGPASSWORD=${PG_PASS}" -e "PGSSLMODE=${PG_SSL:-disable}" "${PG_IMAGE}" \
            pg_dump -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${PG_BASE}" --no-owner --no-privileges --no-comments -j "${PG_DUMP_CONCURRENCY}" -f "/backup/${BACKUP_NAME}.dir" -Fd
        run "Archiving dir-format backup ${BACKUP_FILE}..." \
            tar -czf "${BACKUP_FILE}" -C "${BACKUP_DIR}" "${BACKUP_NAME}.dir"
        rm -rf "${backup_dump_path}"
    else
        run "Creating cst-format backup ${BACKUP_FILE}..." \
            docker run --rm --name "pg-backup-${PG_BASE}" --network host --user "$(id -u):$(id -g)" -v "${BACKUP_DIR}:/backup" -i -e "PGPASSWORD=${PG_PASS}" -e "PGSSLMODE=${PG_SSL:-disable}" "${PG_IMAGE}" \
            pg_dump -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${PG_BASE}" --no-owner --no-privileges --no-comments -f "/backup/${BACKUP_NAME}.dump" -Fc
    fi
}

encrypt_backup() {
    if [ -z "${PG_DUMP_SECRET}" ]; then
        return
    fi

    run "Encrypting backup ${BACKUP_FILE}.enc..." \
        openssl enc -aes-256-cbc -base64 -pbkdf2 -pass "pass:${PG_DUMP_SECRET}" -e -in "${BACKUP_FILE}" -out "${BACKUP_FILE}.enc"
    rm -f "${BACKUP_FILE}"
    BACKUP_EXT="${BACKUP_EXT}.enc"
    BACKUP_FILE="${BACKUP_DIR}/${BACKUP_NAME}.${BACKUP_EXT}"
}

verify_backup_file() {
    if [ ! -f "${BACKUP_FILE}" ]; then
        error "Backup file ${BACKUP_FILE} should be created, but not found"
    fi

    echo "Created backup: ${BACKUP_FILE}"
}

link_latest_backup() {
    echo "Linking backup to ${BACKUP_LATEST_DIR}/latest.${BACKUP_EXT}"
    ln -sf "${BACKUP_FILE}" "${BACKUP_LATEST_DIR}/latest.${BACKUP_EXT}"
}

upload_backup() {
    local var

    if [ -z "${PG_DUMP_S3_BUCKET}" ]; then
        info "Backup uploading is not configured, skipping..."
        return
    fi

    if ! is_s3_enabled; then
        info "S3 backup uploading is disabled by PG_DUMP_S3=${PG_DUMP_S3}, skipping..."
        return
    fi

    for var in PG_DUMP_S3_ENDPOINT PG_DUMP_S3_REGION PG_DUMP_S3_ACCESS_KEY PG_DUMP_S3_SECRET_KEY; do
        if [ -z "${!var}" ]; then
            echo "Error: ${var} is not set"
            exit 1
        fi
    done

    BACKUP_KEY="${PG_DUMP_S3_PREFIX%/}"
    if [ -n "${PG_DUMP_PREFIX}" ]; then
        BACKUP_KEY="${BACKUP_KEY}/${PG_DUMP_PREFIX}"
    fi
    BACKUP_KEY="${BACKUP_KEY%/}/${BACKUP_NAME}.${BACKUP_EXT}"
    info "Uploading ${BACKUP_FILE} to s3://${PG_DUMP_S3_BUCKET}/${BACKUP_KEY} via ${PG_DUMP_S3_ENDPOINT} with PG_DUMP_S3_REGION=${PG_DUMP_S3_REGION}"
    BACKUP_MD5_BASE64=$(openssl md5 -binary "${BACKUP_FILE}" | base64)
    run "Uploading backup to S3..." \
        env AWS_REGION="${PG_DUMP_S3_REGION}" AWS_ACCESS_KEY_ID="${PG_DUMP_S3_ACCESS_KEY}" AWS_SECRET_ACCESS_KEY="${PG_DUMP_S3_SECRET_KEY}" \
        aws --endpoint-url="${PG_DUMP_S3_ENDPOINT}" s3api put-object --bucket "${PG_DUMP_S3_BUCKET}" --key "${BACKUP_KEY}" --body "${BACKUP_FILE}" --content-md5 "${BACKUP_MD5_BASE64}"
}

prune_old_backups() {
    info "Clean up ${BACKUP_DIR} from backups older than 24 hours"
    find "${BACKUP_DIR}" -type f -mmin +1440 -exec rm {} \;
}

finish() {
    SCRIPT_END=$(date -u '+%s.%3N')
    SCRIPT_ELAPSED=$(echo "scale=3; $SCRIPT_END - $SCRIPT_START" | bc)
    info "Finished in ${SCRIPT_ELAPSED}s"
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
