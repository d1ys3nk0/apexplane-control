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
Usage: snap_restore /opt/postgres/snapshots/<snapshot>.tar.gz

Restores a local tar.gz snapshot into the configured Docker PostgreSQL data
volume. The script stops PostgreSQL, clears the data volume, extracts the
snapshot, and starts PostgreSQL again.

Required environment:
  POSTGRES_DATA_VOLUME
  POSTGRES_DATA_ROOT
  POSTGRES_DATA_DIR

Optional environment:
  PG_CONTAINER=postgres
  SNAPSHOT_UTILITY_IMAGE=busybox:1.37.0

Example:
  dotenv /opt/postgres/env /opt/postgres/bin/snap_restore /opt/postgres/snapshots/postgres-snapshot-260603120000.tar.gz
USAGE
}

init_config() {
    if [ "$#" -ne 1 ]; then
        usage_error "Expected 1 argument, got $#"
    fi

    PG_CONTAINER="${PG_CONTAINER:-postgres}"
    SNAPSHOT_UTILITY_IMAGE="${SNAPSHOT_UTILITY_IMAGE:-busybox:1.37.0}"
    SNAPSHOT_FILE="$1"
    require_vars "POSTGRES_DATA_VOLUME" "POSTGRES_DATA_ROOT" "POSTGRES_DATA_DIR"

    if [ ! -f "${SNAPSHOT_FILE}" ]; then
        error "Snapshot file ${SNAPSHOT_FILE} does not exist"
    fi
}

init_timestamps() {
    TIME_UTC=$(date -u '+%Y-%m-%d %H:%M:%S')
    info "Started at ${TIME_UTC} UTC"
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

wait_before_restore() {
    local seconds_left

    info "Snapshot restore will replace Docker volume ${POSTGRES_DATA_VOLUME} from ${SNAPSHOT_FILE}."
    for seconds_left in 10 9 8 7 6 5 4 3 2 1; do
        warn "Starting destructive snapshot restore in ${seconds_left}s..."
        sleep 1
    done
}

stop_postgres_container() {
    local container_state

    container_state=$(docker inspect "${PG_CONTAINER}" --format '{{.State.Status}}')
    if [ "${container_state}" = "running" ]; then
        info "Stopping PostgreSQL container ${PG_CONTAINER}"
        docker stop "${PG_CONTAINER}" >/dev/null
        return
    fi

    warn "PostgreSQL container ${PG_CONTAINER} is ${container_state}; continuing with offline restore"
}

clear_data() {
    info "Clearing PostgreSQL data volume ${POSTGRES_DATA_VOLUME}"
    docker run --rm \
        --volumes-from "${PG_CONTAINER}" \
        "${SNAPSHOT_UTILITY_IMAGE}" \
        find "${POSTGRES_DATA_DIR}" -mindepth 1 -delete
}

restore_snapshot() {
    local snapshot_dir
    local snapshot_name

    snapshot_dir=$(dirname "${SNAPSHOT_FILE}")
    snapshot_name=$(basename "${SNAPSHOT_FILE}")
    info "Restoring PostgreSQL data snapshot ${SNAPSHOT_FILE}"
    docker run --rm \
        --volumes-from "${PG_CONTAINER}" \
        -v "${snapshot_dir}:/mnt/snapshots:ro" \
        "${SNAPSHOT_UTILITY_IMAGE}" \
        tar xzf "/mnt/snapshots/${snapshot_name}" -C "${POSTGRES_DATA_DIR}"
}

start_postgres_container() {
    info "Starting PostgreSQL container ${PG_CONTAINER}"
    docker start "${PG_CONTAINER}" >/dev/null
}

finish() {
    info "Finished in $((SECONDS - SCRIPT_START_SECONDS))s"
}

main() {
    init_config "$@"
    init_timestamps
    validate_postgres_container
    wait_before_restore
    stop_postgres_container
    clear_data
    restore_snapshot
    start_postgres_container
    finish
}

main "$@"
