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
Usage: snap_dump

Creates a local tar.gz snapshot of the configured Docker PostgreSQL data volume.
The script stops PostgreSQL while archiving and starts it again if it was running.

Required environment:
  POSTGRES_DATA_VOLUME
  POSTGRES_DATA_ROOT
  POSTGRES_DATA_DIR

Optional environment:
  PG_CONTAINER=postgres
  SNAPSHOT_DIR=/opt/postgres/snapshots
  SNAPSHOT_UTILITY_IMAGE=busybox:1.37.0

Example:
  dotenv /opt/postgres/env /opt/postgres/bin/snap_dump
USAGE
}

init_config() {
    if [ "$#" -ne 0 ]; then
        usage_error "Expected 0 arguments, got $#"
    fi

    PG_CONTAINER="${PG_CONTAINER:-postgres}"
    SNAPSHOT_DIR="${SNAPSHOT_DIR:-/opt/postgres/snapshots}"
    SNAPSHOT_UTILITY_IMAGE="${SNAPSHOT_UTILITY_IMAGE:-busybox:1.37.0}"
    require_vars "POSTGRES_DATA_VOLUME" "POSTGRES_DATA_ROOT" "POSTGRES_DATA_DIR"

    POSTGRES_WAS_RUNNING=false
    SNAPSHOT_FILE=""
}

init_timestamps() {
    TIME_TAG=$(date -u '+%y%m%d%H%M%S')
    TIME_UTC=$(date -u '+%Y-%m-%d %H:%M:%S')
    info "Started at ${TIME_UTC} UTC"
}

cleanup() {
    if [ "${POSTGRES_WAS_RUNNING:-false}" = "true" ]; then
        warn "Starting PostgreSQL container ${PG_CONTAINER} after interrupted snapshot"
        docker start "${PG_CONTAINER}" >/dev/null || true
    fi
}

init_cleanup() {
    trap cleanup EXIT
}

validate_postgres_container() {
    local data_mount
    local pgdata

    info "Validating PostgreSQL container ${PG_CONTAINER}"
    if ! docker inspect "${PG_CONTAINER}" >/dev/null 2>&1; then
        error "PostgreSQL container ${PG_CONTAINER} does not exist"
    fi

    pgdata=$(docker inspect "${PG_CONTAINER}" --format '{{range .Config.Env}}{{printf "%s\n" .}}{{end}}' | awk -F= '$1 == "PGDATA" { print substr($0, 8); exit }')
    if [ "${pgdata}" != "${POSTGRES_DATA_DIR}" ]; then
        error "PostgreSQL container ${PG_CONTAINER} uses PGDATA=${pgdata:-unset}, expected ${POSTGRES_DATA_DIR}"
    fi

    data_mount=$(docker inspect "${PG_CONTAINER}" --format '{{range .Mounts}}{{printf "%s %s %s\n" .Type .Name .Destination}}{{end}}' |
        awk -v volume="${POSTGRES_DATA_VOLUME}" -v destination="${POSTGRES_DATA_ROOT}" '$1 == "volume" && $2 == volume && $3 == destination { print $0; exit }')
    if [ -z "${data_mount}" ]; then
        error "PostgreSQL container ${PG_CONTAINER} does not mount ${POSTGRES_DATA_VOLUME} at ${POSTGRES_DATA_ROOT}"
    fi
}

stop_postgres_container() {
    local container_state

    container_state=$(docker inspect "${PG_CONTAINER}" --format '{{.State.Status}}')
    if [ "${container_state}" = "running" ]; then
        POSTGRES_WAS_RUNNING=true
        info "Stopping PostgreSQL container ${PG_CONTAINER}"
        docker stop "${PG_CONTAINER}" >/dev/null
        return
    fi

    warn "PostgreSQL container ${PG_CONTAINER} is ${container_state}; creating snapshot from offline data"
}

start_postgres_container() {
    if [ "${POSTGRES_WAS_RUNNING}" != "true" ]; then
        return
    fi

    info "Starting PostgreSQL container ${PG_CONTAINER}"
    docker start "${PG_CONTAINER}" >/dev/null
    POSTGRES_WAS_RUNNING=false
}

dump_snapshot() {
    SNAPSHOT_FILE="${SNAPSHOT_DIR}/postgres-snapshot-${TIME_TAG}.tar.gz"
    info "Creating PostgreSQL data snapshot ${SNAPSHOT_FILE}"
    mkdir -p "${SNAPSHOT_DIR}"
    docker run --rm \
        --volumes-from "${PG_CONTAINER}:ro" \
        -v "${SNAPSHOT_DIR}:/mnt/snapshots" \
        "${SNAPSHOT_UTILITY_IMAGE}" \
        tar czf "/mnt/snapshots/$(basename "${SNAPSHOT_FILE}")" -C "${POSTGRES_DATA_DIR}" .
}

finish() {
    info "Finished in $((SECONDS - SCRIPT_START_SECONDS))s"
}

main() {
    init_config "$@"
    init_timestamps
    init_cleanup
    validate_postgres_container
    stop_postgres_container
    dump_snapshot
    start_postgres_container
    finish
}

main "$@"
