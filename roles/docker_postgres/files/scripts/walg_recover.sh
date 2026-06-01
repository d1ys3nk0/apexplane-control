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
  WALG_RECOVER_S3_PREFIX
  WALG_RECOVER_S3_ACCESS_KEY
  WALG_RECOVER_S3_SECRET_KEY

Optional environment:
  WALG_CONTAINER=postgres
  WALG_DATA_VOLUME=postgres_data
  WALG_DATA_DIR=/var/lib/postgresql/data
  WALG_CONFIG_DIR=/opt/postgres/config
  WALG_SNAPSHOT_DIR=/opt/postgres/snapshots
  WALG_RECOVER_BACKUP_NAME=LATEST
  WALG_RECOVER_PGUSER=admin
  WALG_RECOVER_NO_SNAPSHOT=true|false
  WALG_RECOVER_START=true|false
  WALG_RECOVER_WAIT=true|false
  WALG_RECOVER_WAIT_SECONDS=3600

Examples:
  dotenv /opt/postgres/postgres.env /opt/postgres/bin/walg_recover
  dotenv /opt/postgres/postgres.env /opt/postgres/bin/walg_recover s3://<bucket>/<prefix> LATEST
USAGE
}

init_config() {
    if [ "$#" -gt 2 ]; then
        usage_error "Expected 0, 1, or 2 arguments, got $#"
    fi

    WALG_CONTAINER="${WALG_CONTAINER:-postgres}"
    WALG_DATA_VOLUME="${WALG_DATA_VOLUME:-postgres_data}"
    WALG_DATA_DIR="${WALG_DATA_DIR:-/var/lib/postgresql/data}"
    WALG_CONFIG_DIR="${WALG_CONFIG_DIR:-/opt/postgres/config}"
    WALG_SNAPSHOT_DIR="${WALG_SNAPSHOT_DIR:-/opt/postgres/snapshots}"
    WALG_RECOVER_BACKUP_NAME="${WALG_RECOVER_BACKUP_NAME:-LATEST}"
    WALG_RECOVER_PGUSER="${WALG_RECOVER_PGUSER:-admin}"
    WALG_RECOVER_NO_SNAPSHOT="${WALG_RECOVER_NO_SNAPSHOT:-false}"
    WALG_RECOVER_START="${WALG_RECOVER_START:-true}"
    WALG_RECOVER_WAIT="${WALG_RECOVER_WAIT:-true}"
    WALG_RECOVER_WAIT_SECONDS="${WALG_RECOVER_WAIT_SECONDS:-3600}"

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
        "WALG_RECOVER_S3_PREFIX" \
        "WALG_RECOVER_S3_ACCESS_KEY" \
        "WALG_RECOVER_S3_SECRET_KEY"
    require_positive_integer "${WALG_RECOVER_WAIT_SECONDS}" WALG_RECOVER_WAIT_SECONDS
    is_true "${WALG_RECOVER_NO_SNAPSHOT}" WALG_RECOVER_NO_SNAPSHOT || true
    is_true "${WALG_RECOVER_START}" WALG_RECOVER_START || true
    is_true "${WALG_RECOVER_WAIT}" WALG_RECOVER_WAIT || true

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
        -v "${WALG_DATA_VOLUME}:${WALG_DATA_DIR}:ro" \
        -v "${WALG_SNAPSHOT_DIR}:/mnt/snapshots" \
        busybox:latest \
        tar czf "/mnt/snapshots/walg-recover-before-${TIME_TAG}.tar.gz" -C "${WALG_DATA_DIR}" .
}

clear_data() {
    info "Clearing PostgreSQL data volume ${WALG_DATA_VOLUME}"
    docker run --rm \
        -v "${WALG_DATA_VOLUME}:${WALG_DATA_DIR}" \
        busybox:latest \
        find "${WALG_DATA_DIR}" -mindepth 1 -delete
}

fetch_backup() {
    info "Fetching WAL-G backup ${WALG_RECOVER_BACKUP_NAME} from ${WALG_RECOVER_S3_PREFIX}"
    docker run --rm \
        --user postgres \
        -v "${WALG_DATA_VOLUME}:${WALG_DATA_DIR}" \
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
        -v "${WALG_DATA_VOLUME}:${WALG_DATA_DIR}" \
        -e "RESTORE_COMMAND=restore_command = '/opt/config/walg_recover.sh wal-fetch \"%f\" \"%p\" 2>&1 | tee -a /var/lib/postgresql/data/walg_restore.log'" \
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
        if docker exec "${WALG_CONTAINER}" pg_isready -d postgres -U "${WALG_RECOVER_PGUSER}" >/dev/null 2>&1; then
            recovery_state=$(docker exec "${WALG_CONTAINER}" psql -U "${WALG_RECOVER_PGUSER}" -d postgres -Atq -c "SELECT pg_is_in_recovery()" || true)
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
    if ! is_true "${WALG_RECOVER_START}" WALG_RECOVER_START || ! is_true "${WALG_RECOVER_WAIT}" WALG_RECOVER_WAIT; then
        return
    fi

    info "Resetting temporary restore_command override"
    docker exec "${WALG_CONTAINER}" psql -U "${WALG_RECOVER_PGUSER}" -d postgres -c "ALTER SYSTEM RESET restore_command"
    docker exec "${WALG_CONTAINER}" psql -U "${WALG_RECOVER_PGUSER}" -d postgres -c "SELECT pg_reload_conf()"
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
    finish
}

main "$@"
