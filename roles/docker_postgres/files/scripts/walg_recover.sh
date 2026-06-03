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

Stop application writers before running this script. The script stops and starts
the configured PostgreSQL container during recovery.

Required environment:
  WALG_IMAGE
  WALG_DATA_VOLUME
  WALG_DATA_ROOT
  WALG_DATA_DIR
  WALG_RECOVER_S3_ENDPOINT
  WALG_RECOVER_S3_REGION
  WALG_RECOVER_S3_BUCKET
  WALG_RECOVER_S3_PREFIX
  WALG_RECOVER_S3_ACCESS_KEY
  WALG_RECOVER_S3_SECRET_KEY

Optional environment:
  PG_CONTAINER=postgres
  PG_PORT=5432
  WALG_UTILITY_IMAGE=busybox:1.37.0
  WALG_RECOVER_BACKUP_NAME=LATEST
  WALG_RECOVER_PGUSER=admin
  WALG_RECOVER_START=true|false
  WALG_RECOVER_WAIT=true|false
  WALG_RECOVER_WAIT_SECONDS=3600
  WALG_RECOVER_PROGRESS_SECONDS=30
  WALG_RECOVER_HEALTH_WAIT_SECONDS=120
  WALG_RECOVER_LOG_TAIL_LINES=80
  WALG_RECOVER_ORIGIN_BASE=<old-database-name>
  WALG_RECOVER_TARGET_BASE=<new-database-name>
  WALG_RECOVER_ORIGIN_OWNER=<old-role-name>
  WALG_RECOVER_TARGET_USER=<new-role-name>
  WALG_RECOVER_TARGET_PASS=<new-role-password>
  WALG_RECOVER_ORIGIN_USERS="<source-role-a> <source-role-b>"

Examples:
  dotenv /opt/postgres/env /opt/postgres/bin/walg_recover
  dotenv /opt/postgres/env /opt/postgres/bin/walg_recover s3://<bucket>/<prefix> LATEST
USAGE
}

init_config() {
    if [ "$#" -gt 2 ]; then
        usage_error "Expected 0, 1, or 2 arguments, got $#"
    fi

    PG_CONTAINER="${PG_CONTAINER:-postgres}"
    PG_PORT="${PG_PORT:-5432}"
    require_vars "WALG_IMAGE" "WALG_DATA_VOLUME" "WALG_DATA_ROOT" "WALG_DATA_DIR"
    WALG_UTILITY_IMAGE="${WALG_UTILITY_IMAGE:-busybox:1.37.0}"
    WALG_RECOVER_BACKUP_NAME="${WALG_RECOVER_BACKUP_NAME:-LATEST}"
    WALG_RECOVER_PGUSER="${WALG_RECOVER_PGUSER:-admin}"
    WALG_RECOVER_START="${WALG_RECOVER_START:-true}"
    WALG_RECOVER_WAIT="${WALG_RECOVER_WAIT:-true}"
    WALG_RECOVER_WAIT_SECONDS="${WALG_RECOVER_WAIT_SECONDS:-3600}"
    WALG_RECOVER_PROGRESS_SECONDS="${WALG_RECOVER_PROGRESS_SECONDS:-30}"
    WALG_RECOVER_HEALTH_WAIT_SECONDS="${WALG_RECOVER_HEALTH_WAIT_SECONDS:-120}"
    WALG_RECOVER_LOG_TAIL_LINES="${WALG_RECOVER_LOG_TAIL_LINES:-80}"
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
    require_positive_integer "${WALG_RECOVER_PROGRESS_SECONDS}" WALG_RECOVER_PROGRESS_SECONDS
    require_positive_integer "${WALG_RECOVER_HEALTH_WAIT_SECONDS}" WALG_RECOVER_HEALTH_WAIT_SECONDS
    require_positive_integer "${WALG_RECOVER_LOG_TAIL_LINES}" WALG_RECOVER_LOG_TAIL_LINES
    require_positive_integer "${PG_PORT}" PG_PORT
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

    RESTORE_SCRIPT="${WALG_DATA_ROOT}/walg_restore_command.sh"
    RESTORE_CONFIG_INSTALLED=false
    RECOVERY_COMPLETED=false
    POSTGRES_HEALTH_CONFIRMED=false
    POSTGRES_UID=""
    POSTGRES_GID=""
}

cleanup() {
    if [ -z "${RESTORE_SCRIPT:-}" ]; then
        return
    fi

    if [ "${RESTORE_CONFIG_INSTALLED:-false}" != "true" ]; then
        return
    fi

    if [ "${POSTGRES_HEALTH_CONFIRMED:-false}" = "true" ]; then
        return
    fi

    warn "Leaving ${RESTORE_SCRIPT} in place because PostgreSQL recovery was not confirmed healthy"
    warn "Inspect with: docker ps; docker logs ${PG_CONTAINER} -n ${WALG_RECOVER_LOG_TAIL_LINES}; docker exec ${PG_CONTAINER} pg_isready -d postgres -p ${PG_PORT} -U ${WALG_RECOVER_PGUSER}"
}

init_cleanup() {
    trap cleanup EXIT
}

init_timestamps() {
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

load_postgres_identity() {
    POSTGRES_UID=$(docker run --rm --entrypoint id "${WALG_IMAGE}" -u postgres)
    POSTGRES_GID=$(docker run --rm --entrypoint id "${WALG_IMAGE}" -g postgres)
}

validate_postgres_container() {
    local container_image
    local data_mount
    local shadow_mount
    local pgdata

    info "Validating PostgreSQL container ${PG_CONTAINER}"
    if ! docker inspect "${PG_CONTAINER}" >/dev/null 2>&1; then
        error "PostgreSQL container ${PG_CONTAINER} does not exist"
    fi

    container_image=$(docker inspect "${PG_CONTAINER}" --format '{{.Config.Image}}')
    if [ "${container_image}" != "${WALG_IMAGE}" ]; then
        error "PostgreSQL container ${PG_CONTAINER} uses image ${container_image}, expected ${WALG_IMAGE}"
    fi

    pgdata=$(docker inspect "${PG_CONTAINER}" --format '{{range .Config.Env}}{{printf "%s\n" .}}{{end}}' | awk -F= '$1 == "PGDATA" { print substr($0, 8); exit }')
    if [ "${pgdata}" != "${WALG_DATA_DIR}" ]; then
        error "PostgreSQL container ${PG_CONTAINER} uses PGDATA=${pgdata:-unset}, expected ${WALG_DATA_DIR}"
    fi

    data_mount=$(docker inspect "${PG_CONTAINER}" --format '{{range .Mounts}}{{printf "%s %s %s\n" .Type .Name .Destination}}{{end}}' |
        awk -v volume="${WALG_DATA_VOLUME}" -v destination="${WALG_DATA_ROOT}" '$1 == "volume" && $2 == volume && $3 == destination { print $0; exit }')
    if [ -z "${data_mount}" ]; then
        error "PostgreSQL container ${PG_CONTAINER} does not mount ${WALG_DATA_VOLUME} at ${WALG_DATA_ROOT}"
    fi

    shadow_mount=$(docker inspect "${PG_CONTAINER}" --format '{{range .Mounts}}{{printf "%s %s %s\n" .Type .Name .Destination}}{{end}}' |
        awk -v volume="${WALG_DATA_VOLUME}" -v root="${WALG_DATA_ROOT}" -v pgdata="${WALG_DATA_DIR}" '
            $3 == pgdata && !(pgdata == root && $1 == "volume" && $2 == volume) { print $0; exit }
        ')
    if [ -n "${shadow_mount}" ]; then
        print_recovery_volume_diagnostics
        error "PostgreSQL PGDATA ${WALG_DATA_DIR} is shadowed by unexpected Docker mount: ${shadow_mount}"
    fi
}

print_recovery_volume_diagnostics() {
    warn "PostgreSQL container mounts:"
    docker inspect "${PG_CONTAINER}" --format '{{range .Mounts}}{{printf "%s name=%s source=%s destination=%s\n" .Type .Name .Source .Destination}}{{end}}' >&2 || true
    warn "PostgreSQL data directory diagnostics:"
    docker run --rm \
        --volumes-from "${PG_CONTAINER}:ro" \
        "${WALG_UTILITY_IMAGE}" \
        sh -c '
            for path in "$1" "$1/global"; do
                printf "%s\n" "# ${path}"
                ls -la "${path}" 2>&1 || true
            done
        ' sh "${WALG_DATA_DIR}" >&2 || true
}

validate_recovered_data_files() {
    if docker run --rm \
        --volumes-from "${PG_CONTAINER}:ro" \
        "${WALG_UTILITY_IMAGE}" \
        sh -c 'test -f "$1/PG_VERSION" && test -f "$1/global/pg_control"' sh "${WALG_DATA_DIR}"; then
        return
    fi

    print_recovery_volume_diagnostics
    error "WAL-G backup fetch did not produce a valid PostgreSQL data directory at ${WALG_DATA_DIR}"
}

validate_recovery_config_files() {
    if docker run --rm \
        --volumes-from "${PG_CONTAINER}:ro" \
        "${WALG_UTILITY_IMAGE}" \
        sh -c 'test -f "$1/postgresql.auto.conf" && test -f "$1/recovery.signal" && test -f "$1/walg_restore.log"' sh "${WALG_DATA_DIR}"; then
        return
    fi

    print_recovery_volume_diagnostics
    error "WAL-G recovery config was not installed in PostgreSQL data directory ${WALG_DATA_DIR}"
}

stop_postgres_container() {
    local container_state

    container_state=$(docker inspect "${PG_CONTAINER}" --format '{{.State.Status}}')
    if [ "${container_state}" = "running" ]; then
        info "Stopping PostgreSQL container ${PG_CONTAINER}"
        docker stop "${PG_CONTAINER}" >/dev/null
        return
    fi

    warn "PostgreSQL container ${PG_CONTAINER} is ${container_state}; continuing with offline recovery"
}

clear_data() {
    info "Clearing PostgreSQL data volume ${WALG_DATA_VOLUME}"
    docker run --rm \
        --volumes-from "${PG_CONTAINER}" \
        "${WALG_UTILITY_IMAGE}" \
        find "${WALG_DATA_DIR}" -mindepth 1 -delete
}

fetch_backup() {
    local fetch_started

    fetch_started=${SECONDS}
    info "Fetching WAL-G backup ${WALG_RECOVER_BACKUP_NAME} from ${WALG_RECOVER_S3_PREFIX}"
    docker run --rm \
        --user "${POSTGRES_UID}:${POSTGRES_GID}" \
        --volumes-from "${PG_CONTAINER}" \
        -e "AWS_ENDPOINT=${WALG_RECOVER_S3_ENDPOINT}" \
        -e "AWS_REGION=${WALG_RECOVER_S3_REGION}" \
        -e "AWS_ACCESS_KEY_ID=${WALG_RECOVER_S3_ACCESS_KEY}" \
        -e "AWS_SECRET_ACCESS_KEY=${WALG_RECOVER_S3_SECRET_KEY}" \
        -e "WALG_S3_PREFIX=${WALG_RECOVER_S3_PREFIX}" \
        "${WALG_IMAGE}" \
        /usr/local/bin/wal-g backup-fetch "${WALG_DATA_DIR}" "${WALG_RECOVER_BACKUP_NAME}"
    info "Fetched WAL-G backup in $((SECONDS - fetch_started))s"
}

install_restore_command() {
    info "Installing temporary WAL-G restore command ${RESTORE_SCRIPT}"
    docker run --rm \
        --user "${POSTGRES_UID}:${POSTGRES_GID}" \
        --volumes-from "${PG_CONTAINER}" \
        -e "RESTORE_SCRIPT=${RESTORE_SCRIPT}" \
        -e "WALG_RECOVER_PGUSER=${WALG_RECOVER_PGUSER}" \
        -e "WALG_RECOVER_S3_ENDPOINT=${WALG_RECOVER_S3_ENDPOINT}" \
        -e "WALG_RECOVER_S3_REGION=${WALG_RECOVER_S3_REGION}" \
        -e "WALG_RECOVER_S3_ACCESS_KEY=${WALG_RECOVER_S3_ACCESS_KEY}" \
        -e "WALG_RECOVER_S3_SECRET_KEY=${WALG_RECOVER_S3_SECRET_KEY}" \
        -e "WALG_RECOVER_S3_PREFIX=${WALG_RECOVER_S3_PREFIX}" \
        "${WALG_UTILITY_IMAGE}" \
        sh -c '
            quote_env() {
                sq=$(printf "\047")
                printf "%s" "${sq}"
                printf "%s" "$1" | sed "s/${sq}/${sq}\\\\${sq}${sq}/g"
                printf "%s" "${sq}"
            }

            umask 077
            {
                printf "%s\n" "#!/bin/sh"
                printf "%s\n" "export PGHOST=\"/var/run/postgresql\""
                printf "export PGUSER=%s\n" "$(quote_env "${WALG_RECOVER_PGUSER}")"
                printf "export AWS_ENDPOINT=%s\n" "$(quote_env "${WALG_RECOVER_S3_ENDPOINT}")"
                printf "export AWS_REGION=%s\n" "$(quote_env "${WALG_RECOVER_S3_REGION}")"
                printf "export AWS_ACCESS_KEY_ID=%s\n" "$(quote_env "${WALG_RECOVER_S3_ACCESS_KEY}")"
                printf "export AWS_SECRET_ACCESS_KEY=%s\n" "$(quote_env "${WALG_RECOVER_S3_SECRET_KEY}")"
                printf "export WALG_S3_PREFIX=%s\n" "$(quote_env "${WALG_RECOVER_S3_PREFIX}")"
                printf "%s\n" "exec /usr/local/bin/wal-g \"\$@\""
            } >"${RESTORE_SCRIPT}"
            chmod 0700 "${RESTORE_SCRIPT}"
        '
}

remove_restore_command() {
    docker run --rm \
        --volumes-from "${PG_CONTAINER}" \
        "${WALG_UTILITY_IMAGE}" \
        rm -f "${RESTORE_SCRIPT}" >/dev/null 2>&1 || true
}

enable_recovery() {
    info "Enabling PostgreSQL archive recovery"
    # shellcheck disable=SC2016
    docker run --rm \
        --user "${POSTGRES_UID}:${POSTGRES_GID}" \
        --volumes-from "${PG_CONTAINER}" \
        -e "RESTORE_COMMAND=restore_command = '${RESTORE_SCRIPT} wal-fetch \"%f\" \"%p\" >> ${WALG_DATA_DIR}/walg_restore.log 2>&1'" \
        "${WALG_UTILITY_IMAGE}" \
        sh -c 'printf "%s\n" "$RESTORE_COMMAND" >> "$1/postgresql.auto.conf" && touch "$1/recovery.signal" && : > "$1/walg_restore.log"' sh "${WALG_DATA_DIR}"
    RESTORE_CONFIG_INSTALLED=true
}

start_postgres_container() {
    if ! is_true "${WALG_RECOVER_START}" WALG_RECOVER_START; then
        warn "PostgreSQL container is not started because WALG_RECOVER_START=${WALG_RECOVER_START}"
        return
    fi

    info "Starting PostgreSQL container ${PG_CONTAINER}"
    docker start "${PG_CONTAINER}" >/dev/null
}

recovery_volume_metrics() {
    docker run --rm \
        --volumes-from "${PG_CONTAINER}:ro" \
        "${WALG_UTILITY_IMAGE}" \
        sh -c '
            data_kib=unknown
            restore_log_bytes=missing
            if du_output=$(du -sk "$1" 2>/dev/null); then
                data_kib="${du_output%%[!0-9]*}"
            fi
            if [ -f "$2" ]; then
                restore_log_bytes=$(wc -c <"$2" | tr -d " ")
            fi
            printf "data_kib=%s restore_log_bytes=%s" "${data_kib}" "${restore_log_bytes}"
        ' sh "${WALG_DATA_DIR}" "${WALG_DATA_DIR}/walg_restore.log" 2>/dev/null || printf 'data_kib=unknown restore_log_bytes=unknown'
}

container_metrics() {
    docker inspect "${PG_CONTAINER}" \
        --format 'container={{.State.Status}} health={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}} restart_count={{.RestartCount}} exit_code={{.State.ExitCode}}' \
        2>/dev/null || printf 'container=missing health=unknown restart_count=unknown exit_code=unknown'
}

postgres_ready() {
    docker exec "${PG_CONTAINER}" pg_isready -d postgres -p "${PG_PORT}" -U "${WALG_RECOVER_PGUSER}" >/dev/null 2>&1
}

postgres_recovery_state() {
    docker exec "${PG_CONTAINER}" psql -p "${PG_PORT}" -U "${WALG_RECOVER_PGUSER}" -d postgres -Atq -c "SELECT pg_is_in_recovery()" 2>/dev/null || true
}

postgres_replay_metrics() {
    docker exec "${PG_CONTAINER}" psql -p "${PG_PORT}" -U "${WALG_RECOVER_PGUSER}" -d postgres -Atq -c "SELECT 'replay_lsn=' || COALESCE(pg_last_wal_replay_lsn()::text, 'unknown')" 2>/dev/null || printf 'replay_lsn=unknown'
}

restore_command_state() {
    docker exec "${PG_CONTAINER}" psql -p "${PG_PORT}" -U "${WALG_RECOVER_PGUSER}" -d postgres -Atq -c "SHOW restore_command" 2>/dev/null || true
}

print_restore_log_tail() {
    docker run --rm \
        --volumes-from "${PG_CONTAINER}:ro" \
        "${WALG_UTILITY_IMAGE}" \
        sh -c '
            if [ -f "$1" ]; then
                tail -n "$2" "$1"
            else
                printf "%s\n" "restore log is missing: $1"
            fi
        ' sh "${WALG_DATA_DIR}/walg_restore.log" "${WALG_RECOVER_LOG_TAIL_LINES}" 2>/dev/null || true
}

print_diagnostics() {
    local restore_command

    warn "PostgreSQL restore diagnostics:"
    warn "$(container_metrics); $(recovery_volume_metrics)"
    if postgres_ready; then
        restore_command=$(restore_command_state)
        warn "postgres=ready pg_is_in_recovery=$(postgres_recovery_state) $(postgres_replay_metrics) restore_command=${restore_command:+configured}"
    else
        warn "postgres=not-ready"
    fi
    warn "Last ${WALG_RECOVER_LOG_TAIL_LINES} PostgreSQL log lines:"
    docker logs "${PG_CONTAINER}" -n "${WALG_RECOVER_LOG_TAIL_LINES}" 2>&1 || true
    warn "Last ${WALG_RECOVER_LOG_TAIL_LINES} WAL-G restore log lines:"
    print_restore_log_tail
}

wait_for_recovery() {
    local container_state
    local database_metrics
    local deadline
    local elapsed
    local next_progress
    local ready_state
    local recovery_state
    local recovery_started
    local remaining

    if ! is_true "${WALG_RECOVER_START}" WALG_RECOVER_START || ! is_true "${WALG_RECOVER_WAIT}" WALG_RECOVER_WAIT; then
        return
    fi

    info "Waiting up to ${WALG_RECOVER_WAIT_SECONDS}s for PostgreSQL to finish recovery"
    recovery_started=${SECONDS}
    deadline=$((SECONDS + WALG_RECOVER_WAIT_SECONDS))
    next_progress=${SECONDS}
    while [ "${SECONDS}" -lt "${deadline}" ]; do
        container_state=$(docker inspect "${PG_CONTAINER}" --format '{{.State.Status}}' 2>/dev/null || true)
        if [ "${container_state}" != "running" ]; then
            print_diagnostics
            error "PostgreSQL container ${PG_CONTAINER} is ${container_state:-missing}"
        fi

        ready_state=not-ready
        database_metrics="replay_lsn=unknown"
        recovery_state=unknown
        if postgres_ready; then
            ready_state=ready
            recovery_state=$(postgres_recovery_state)
            database_metrics=$(postgres_replay_metrics)
            if [ "${recovery_state}" = "f" ]; then
                RECOVERY_COMPLETED=true
                info "PostgreSQL recovery completed in $((SECONDS - recovery_started))s"
                return
            fi
        fi

        if [ "${SECONDS}" -ge "${next_progress}" ]; then
            elapsed=$((SECONDS - recovery_started))
            remaining=$((deadline - SECONDS))
            if [ "${remaining}" -lt 0 ]; then
                remaining=0
            fi
            info "Recovery in progress after ${elapsed}s; ${remaining}s until timeout; $(container_metrics); postgres=${ready_state}; pg_is_in_recovery=${recovery_state}; $(recovery_volume_metrics); ${database_metrics:-replay_lsn=unknown}"
            next_progress=$((SECONDS + WALG_RECOVER_PROGRESS_SECONDS))
        fi

        sleep 5
    done

    print_diagnostics
    error "PostgreSQL did not finish recovery within ${WALG_RECOVER_WAIT_SECONDS}s"
}

wait_for_postgres_health() {
    local deadline
    local health_state
    local recovery_state
    local health_started

    if ! is_true "${WALG_RECOVER_START}" WALG_RECOVER_START || ! is_true "${WALG_RECOVER_WAIT}" WALG_RECOVER_WAIT; then
        return
    fi

    info "Waiting up to ${WALG_RECOVER_HEALTH_WAIT_SECONDS}s for PostgreSQL to become healthy"
    health_started=${SECONDS}
    deadline=$((SECONDS + WALG_RECOVER_HEALTH_WAIT_SECONDS))
    while [ "${SECONDS}" -lt "${deadline}" ]; do
        health_state=$(docker inspect "${PG_CONTAINER}" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' 2>/dev/null || true)
        if [ "$(docker inspect "${PG_CONTAINER}" --format '{{.State.Status}}' 2>/dev/null || true)" = "running" ] &&
            [ "${health_state}" = "healthy" ] &&
            postgres_ready; then
            recovery_state=$(postgres_recovery_state)
            if [ "${recovery_state}" = "f" ]; then
                POSTGRES_HEALTH_CONFIRMED=true
                info "PostgreSQL is healthy after restore in $((SECONDS - health_started))s; $(container_metrics); pg_is_in_recovery=${recovery_state}"
                return
            fi
        fi
        sleep 5
    done

    print_diagnostics
    error "PostgreSQL did not become healthy within ${WALG_RECOVER_HEALTH_WAIT_SECONDS}s"
}

cleanup_recover_config() {
    if ! is_true "${WALG_RECOVER_START}" WALG_RECOVER_START; then
        return
    fi

    local recovery_state
    recovery_state=$(postgres_recovery_state)
    if [ "${RECOVERY_COMPLETED}" != "true" ] || [ "${POSTGRES_HEALTH_CONFIRMED}" != "true" ] || [ "${recovery_state}" != "f" ]; then
        warn "PostgreSQL restore is not confirmed healthy; leaving restore_command in place"
        return
    fi

    info "Resetting temporary restore_command override"
    docker exec "${PG_CONTAINER}" psql -p "${PG_PORT}" -U "${WALG_RECOVER_PGUSER}" -d postgres -c "ALTER SYSTEM RESET restore_command"
    docker exec "${PG_CONTAINER}" psql -p "${PG_PORT}" -U "${WALG_RECOVER_PGUSER}" -d postgres -c "SELECT pg_reload_conf()"

    if [ -n "${RESTORE_SCRIPT:-}" ]; then
        info "Removing temporary WAL-G recovery config ${RESTORE_SCRIPT}"
        remove_restore_command
        RESTORE_CONFIG_INSTALLED=false
        RESTORE_SCRIPT=""
    fi
}

psql_postgres() {
    docker exec -i "${PG_CONTAINER}" psql -p "${PG_PORT}" -U "${WALG_RECOVER_PGUSER}" -d postgres -v ON_ERROR_STOP=1 "$@"
}

psql_database() {
    local database="$1"
    shift

    docker exec -i "${PG_CONTAINER}" psql -p "${PG_PORT}" -U "${WALG_RECOVER_PGUSER}" -d "${database}" -v ON_ERROR_STOP=1 "$@"
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
    load_postgres_identity
    validate_postgres_container
    wait_before_recovery
    stop_postgres_container
    clear_data
    fetch_backup
    validate_recovered_data_files
    install_restore_command
    enable_recovery
    validate_recovery_config_files
    start_postgres_container
    wait_for_recovery
    wait_for_postgres_health
    cleanup_recover_config
    reconcile_recovered_cluster
    finish
}

main "$@"
