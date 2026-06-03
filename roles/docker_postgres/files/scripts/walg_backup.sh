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

usage() {
    cat >&2 <<'USAGE'
Usage: walg_backup

Creates a physical PostgreSQL cluster backup with WAL-G from a standalone
Docker container that mounts the configured PostgreSQL data volume.

Required environment:
  WALG_IMAGE
  WALG_DATA_VOLUME
  WALG_DATA_ROOT
  WALG_DATA_DIR
  WALG_BACKUP_S3_ENDPOINT
  WALG_BACKUP_S3_REGION
  WALG_BACKUP_S3_BUCKET
  WALG_BACKUP_S3_PREFIX
  WALG_BACKUP_S3_ACCESS_KEY
  WALG_BACKUP_S3_SECRET_KEY

Optional environment:
  PG_HOST=127.0.0.1
  PG_PORT=5432
  PG_USER=admin
  PG_PASS=<postgres-password>
  WALG_PGHOST=<PG_HOST>
  WALG_PGPORT=<PG_PORT>
  WALG_PGUSER=<PG_USER>
  WALG_PGPASSWORD=<PG_PASS>
  WALG_DELTA_ORIGIN=LATEST
  WALG_DELTA_MAX_STEPS=24
  WALG_COMPRESSION_METHOD=brotli
  WALG_COMPRESSION_LEVEL=5
  WALG_DISK_RATE_LIMIT=10485760
  WALG_UPLOAD_DISK_CONCURRENCY=1
  WALG_TAR_SIZE_THRESHOLD=<unset>

Example:
  dotenv /opt/postgres/env /opt/postgres/bin/walg_backup
USAGE
}

init_config() {
    if [ "$#" -ne 0 ]; then
        usage_error "Expected 0 arguments, got $#"
    fi

    PG_HOST="${PG_HOST:-127.0.0.1}"
    PG_PORT="${PG_PORT:-5432}"
    PG_USER="${PG_USER:-admin}"
    PG_PASS="${PG_PASS:-}"
    WALG_PGHOST="${WALG_PGHOST:-${PG_HOST}}"
    WALG_PGPORT="${WALG_PGPORT:-${PG_PORT}}"
    WALG_PGUSER="${WALG_PGUSER:-${PG_USER}}"
    WALG_PGPASSWORD="${WALG_PGPASSWORD:-${PG_PASS}}"
    WALG_DELTA_ORIGIN="${WALG_DELTA_ORIGIN:-LATEST}"
    WALG_DELTA_MAX_STEPS="${WALG_DELTA_MAX_STEPS:-24}"
    WALG_COMPRESSION_METHOD="${WALG_COMPRESSION_METHOD:-brotli}"
    WALG_COMPRESSION_LEVEL="${WALG_COMPRESSION_LEVEL:-5}"
    WALG_DISK_RATE_LIMIT="${WALG_DISK_RATE_LIMIT:-10485760}"
    WALG_UPLOAD_DISK_CONCURRENCY="${WALG_UPLOAD_DISK_CONCURRENCY:-1}"
    WALG_TAR_SIZE_THRESHOLD="${WALG_TAR_SIZE_THRESHOLD:-}"

    require_vars \
        "WALG_IMAGE" \
        "WALG_DATA_VOLUME" \
        "WALG_DATA_ROOT" \
        "WALG_DATA_DIR" \
        "WALG_BACKUP_S3_ENDPOINT" \
        "WALG_BACKUP_S3_REGION" \
        "WALG_BACKUP_S3_BUCKET" \
        "WALG_BACKUP_S3_PREFIX" \
        "WALG_BACKUP_S3_ACCESS_KEY" \
        "WALG_BACKUP_S3_SECRET_KEY"

    if [[ "${WALG_BACKUP_S3_PREFIX}" != s3://* ]]; then
        WALG_BACKUP_S3_PREFIX="s3://${WALG_BACKUP_S3_BUCKET}/${WALG_BACKUP_S3_PREFIX#/}"
    fi
}

init_timestamps() {
    TIME_UTC=$(date -u '+%Y-%m-%d %H:%M:%S')
    info "Started at ${TIME_UTC} UTC"
}

create_backup() {
    local backup_started
    local tar_size_threshold_env=()

    backup_started=${SECONDS}
    info "Creating WAL-G backup from Docker volume ${WALG_DATA_VOLUME}:${WALG_DATA_DIR} to ${WALG_BACKUP_S3_PREFIX}"
    info "Backup settings: delta_origin=${WALG_DELTA_ORIGIN}; delta_max_steps=${WALG_DELTA_MAX_STEPS}; compression=${WALG_COMPRESSION_METHOD}:${WALG_COMPRESSION_LEVEL}; disk_rate_limit=${WALG_DISK_RATE_LIMIT}; upload_disk_concurrency=${WALG_UPLOAD_DISK_CONCURRENCY}; tar_size_threshold=${WALG_TAR_SIZE_THRESHOLD:-unset}"
    if [ -n "${WALG_TAR_SIZE_THRESHOLD}" ]; then
        tar_size_threshold_env=(-e "WALG_TAR_SIZE_THRESHOLD=${WALG_TAR_SIZE_THRESHOLD}")
    fi
    docker run --rm \
        --network host \
        --user postgres \
        -v "${WALG_DATA_VOLUME}:${WALG_DATA_ROOT}:ro" \
        -e "PGHOST=${WALG_PGHOST}" \
        -e "PGPORT=${WALG_PGPORT}" \
        -e "PGUSER=${WALG_PGUSER}" \
        -e "PGPASSWORD=${WALG_PGPASSWORD}" \
        -e "AWS_ENDPOINT=${WALG_BACKUP_S3_ENDPOINT}" \
        -e "AWS_REGION=${WALG_BACKUP_S3_REGION}" \
        -e "AWS_ACCESS_KEY_ID=${WALG_BACKUP_S3_ACCESS_KEY}" \
        -e "AWS_SECRET_ACCESS_KEY=${WALG_BACKUP_S3_SECRET_KEY}" \
        -e "WALG_S3_PREFIX=${WALG_BACKUP_S3_PREFIX}" \
        -e "WALG_DELTA_ORIGIN=${WALG_DELTA_ORIGIN}" \
        -e "WALG_DELTA_MAX_STEPS=${WALG_DELTA_MAX_STEPS}" \
        -e "WALG_COMPRESSION_METHOD=${WALG_COMPRESSION_METHOD}" \
        -e "WALG_COMPRESSION_LEVEL=${WALG_COMPRESSION_LEVEL}" \
        -e "WALG_DISK_RATE_LIMIT=${WALG_DISK_RATE_LIMIT}" \
        -e "WALG_UPLOAD_DISK_CONCURRENCY=${WALG_UPLOAD_DISK_CONCURRENCY}" \
        "${tar_size_threshold_env[@]}" \
        "${WALG_IMAGE}" \
        /usr/local/bin/wal-g backup-push "${WALG_DATA_DIR}"
    info "Created WAL-G backup in $((SECONDS - backup_started))s"
}

finish() {
    info "Finished in $((SECONDS - SCRIPT_START_SECONDS))s"
}

main() {
    init_config "$@"
    init_timestamps
    create_backup
    finish
}

main "$@"
