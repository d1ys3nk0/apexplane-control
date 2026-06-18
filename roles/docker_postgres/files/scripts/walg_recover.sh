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
Usage: walg_recover [--time <timestamp>] s3:key-or-prefix|s3://bucket/key-or-prefix|/mounted/walg/repo

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

Optional environment:
  PG_CONTAINER=postgres
  PG_PORT=5432
  WALG_UTILITY_IMAGE=busybox:1.37.0
  WALG_RECOVER_BACKUP_NAME=LATEST
  WALG_RECOVER_TIME=<timestamp>
  WALG_RECOVER_PGUSER=admin
  WALG_RECOVER_START=true|false
  WALG_RECOVER_STANDBY=true|false
  WALG_RECOVER_PRIMARY_HOST=<primary-host>
  WALG_RECOVER_PRIMARY_PORT=5432
  WALG_RECOVER_PRIMARY_USER=<replication-user>
  WALG_RECOVER_PRIMARY_PASSWORD=<replication-password>
  WALG_RECOVER_PRIMARY_SSL=prefer
  WALG_RECOVER_WAIT=true|false
  WALG_RECOVER_STOP_WAIT_SECONDS=120
  WALG_RECOVER_WAIT_SECONDS=3600
  WALG_RECOVER_PROGRESS_SECONDS=30
  WALG_RECOVER_HEALTH_WAIT_SECONDS=120
  WALG_RECOVER_LOG_TAIL_LINES=80
  WALG_RECOVER_S3_ENDPOINT=<endpoint>
  WALG_RECOVER_S3_REGION=<region>
  WALG_RECOVER_S3_BUCKET=<bucket>
  WALG_RECOVER_S3_ACCESS_KEY=<access-key>
  WALG_RECOVER_S3_SECRET_KEY=<secret-key>

Examples:
  dotenv /opt/postgres/env /opt/postgres/bin/walg_recover s3:<key-or-prefix>
  dotenv /opt/postgres/env /opt/postgres/bin/walg_recover s3://<bucket>/<key-or-prefix>
  dotenv /opt/postgres/env /opt/postgres/bin/walg_recover --time '2026-06-05 12:00:00 UTC' s3:<key-or-prefix>
USAGE
}

parse_args() {
    WALG_RECOVER_SOURCE=""
    WALG_RECOVER_TIME="${WALG_RECOVER_TIME:-}"

    while [ "$#" -gt 0 ]; do
        case "$1" in
        -h | --help)
            usage
            exit 0
            ;;
        --time)
            if [ "$#" -lt 2 ] || [ -z "$2" ]; then
                usage_error "--time requires a non-empty timestamp"
            fi
            WALG_RECOVER_TIME="$2"
            shift 2
            ;;
        --time=*)
            WALG_RECOVER_TIME="${1#--time=}"
            if [ -z "${WALG_RECOVER_TIME}" ]; then
                usage_error "--time requires a non-empty timestamp"
            fi
            shift
            ;;
        --*)
            usage_error "Unknown option: $1"
            ;;
        *)
            if [ -n "${WALG_RECOVER_SOURCE}" ]; then
                usage_error "Expected at most one recovery source argument"
            fi
            WALG_RECOVER_SOURCE="$1"
            shift
            ;;
        esac
    done

    if [ -z "${WALG_RECOVER_SOURCE}" ]; then
        usage_error "Recovery source argument is required"
    fi
}

resolve_recover_path() {
    local s3_input

    case "${WALG_RECOVER_PATH}" in
    s3://*)
        s3_input="${WALG_RECOVER_PATH#s3://}"
        if [ -z "${s3_input%%/*}" ] || [[ "${s3_input}" != */* ]] || [ -z "${s3_input#*/}" ]; then
            usage_error "Expected non-empty S3 key or prefix after s3://<bucket>/"
        fi
        require_vars \
            "WALG_RECOVER_S3_ENDPOINT" \
            "WALG_RECOVER_S3_REGION" \
            "WALG_RECOVER_S3_ACCESS_KEY" \
            "WALG_RECOVER_S3_SECRET_KEY"
        WALG_RECOVER_STORAGE="s3"
        WALG_RECOVER_STORAGE_PATH="${WALG_RECOVER_PATH}"
        ;;
    s3:*)
        s3_input="${WALG_RECOVER_PATH#s3:}"
        if [ -z "${s3_input}" ]; then
            usage_error "Expected non-empty S3 key or prefix after s3:"
        fi
        require_vars \
            "WALG_RECOVER_S3_ENDPOINT" \
            "WALG_RECOVER_S3_REGION" \
            "WALG_RECOVER_S3_BUCKET" \
            "WALG_RECOVER_S3_ACCESS_KEY" \
            "WALG_RECOVER_S3_SECRET_KEY"
        WALG_RECOVER_STORAGE="s3"
        WALG_RECOVER_STORAGE_PATH="s3://${WALG_RECOVER_S3_BUCKET}/${s3_input#/}"
        ;;
    /*)
        WALG_RECOVER_STORAGE="file"
        WALG_RECOVER_STORAGE_PATH="${WALG_RECOVER_PATH}"
        ;;
    *)
        usage_error "WALG_RECOVER_PATH must be s3:<key-or-prefix>, s3://<bucket>/<key-or-prefix>, or an absolute local path"
        ;;
    esac
}

init_config() {
    parse_args "$@"

    PG_CONTAINER="${PG_CONTAINER:-postgres}"
    PG_PORT="${PG_PORT:-5432}"
    require_vars "WALG_IMAGE" "WALG_DATA_VOLUME" "WALG_DATA_ROOT" "WALG_DATA_DIR"
    WALG_UTILITY_IMAGE="${WALG_UTILITY_IMAGE:-busybox:1.37.0}"
    WALG_RECOVER_PATH="${WALG_RECOVER_SOURCE}"
    WALG_RECOVER_BACKUP_NAME="${WALG_RECOVER_BACKUP_NAME:-LATEST}"
    WALG_RECOVER_PGUSER="${WALG_RECOVER_PGUSER:-admin}"
    WALG_RECOVER_START="${WALG_RECOVER_START:-true}"
    WALG_RECOVER_STANDBY="${WALG_RECOVER_STANDBY:-false}"
    WALG_RECOVER_PRIMARY_HOST="${WALG_RECOVER_PRIMARY_HOST:-}"
    WALG_RECOVER_PRIMARY_PORT="${WALG_RECOVER_PRIMARY_PORT:-5432}"
    WALG_RECOVER_PRIMARY_USER="${WALG_RECOVER_PRIMARY_USER:-}"
    WALG_RECOVER_PRIMARY_PASSWORD="${WALG_RECOVER_PRIMARY_PASSWORD:-}"
    WALG_RECOVER_PRIMARY_SSL="${WALG_RECOVER_PRIMARY_SSL:-prefer}"
    WALG_RECOVER_WAIT="${WALG_RECOVER_WAIT:-true}"
    WALG_RECOVER_STOP_WAIT_SECONDS="${WALG_RECOVER_STOP_WAIT_SECONDS:-120}"
    WALG_RECOVER_WAIT_SECONDS="${WALG_RECOVER_WAIT_SECONDS:-3600}"
    WALG_RECOVER_PROGRESS_SECONDS="${WALG_RECOVER_PROGRESS_SECONDS:-30}"
    WALG_RECOVER_HEALTH_WAIT_SECONDS="${WALG_RECOVER_HEALTH_WAIT_SECONDS:-120}"
    WALG_RECOVER_LOG_TAIL_LINES="${WALG_RECOVER_LOG_TAIL_LINES:-80}"
    WALG_RECOVER_S3_ENDPOINT="${WALG_RECOVER_S3_ENDPOINT:-}"
    WALG_RECOVER_S3_REGION="${WALG_RECOVER_S3_REGION:-}"
    WALG_RECOVER_S3_BUCKET="${WALG_RECOVER_S3_BUCKET:-}"
    WALG_RECOVER_S3_ACCESS_KEY="${WALG_RECOVER_S3_ACCESS_KEY:-}"
    WALG_RECOVER_S3_SECRET_KEY="${WALG_RECOVER_S3_SECRET_KEY:-}"

    require_positive_integer "${WALG_RECOVER_STOP_WAIT_SECONDS}" WALG_RECOVER_STOP_WAIT_SECONDS
    require_positive_integer "${WALG_RECOVER_WAIT_SECONDS}" WALG_RECOVER_WAIT_SECONDS
    require_positive_integer "${WALG_RECOVER_PROGRESS_SECONDS}" WALG_RECOVER_PROGRESS_SECONDS
    require_positive_integer "${WALG_RECOVER_HEALTH_WAIT_SECONDS}" WALG_RECOVER_HEALTH_WAIT_SECONDS
    require_positive_integer "${WALG_RECOVER_LOG_TAIL_LINES}" WALG_RECOVER_LOG_TAIL_LINES
    require_positive_integer "${PG_PORT}" PG_PORT
    require_positive_integer "${WALG_RECOVER_PRIMARY_PORT}" WALG_RECOVER_PRIMARY_PORT
    is_true "${WALG_RECOVER_START}" WALG_RECOVER_START || true
    is_true "${WALG_RECOVER_STANDBY}" WALG_RECOVER_STANDBY || true
    is_true "${WALG_RECOVER_WAIT}" WALG_RECOVER_WAIT || true
    case "${WALG_RECOVER_TIME}" in
    *$'\n'* | *$'\r'*)
        usage_error "WALG_RECOVER_TIME must be a single-line PostgreSQL timestamp"
        ;;
    esac
    case "${WALG_RECOVER_PRIMARY_HOST}${WALG_RECOVER_PRIMARY_USER}${WALG_RECOVER_PRIMARY_PASSWORD}${WALG_RECOVER_PRIMARY_SSL}" in
    *$'\n'* | *$'\r'*)
        usage_error "WALG_RECOVER_PRIMARY_* values must be single-line strings"
        ;;
    esac
    if is_true "${WALG_RECOVER_STANDBY}" WALG_RECOVER_STANDBY; then
        require_vars "WALG_RECOVER_PRIMARY_HOST" "WALG_RECOVER_PRIMARY_USER" "WALG_RECOVER_PRIMARY_PASSWORD" "WALG_RECOVER_PRIMARY_SSL"
        if [ -n "${WALG_RECOVER_TIME}" ]; then
            usage_error "WALG_RECOVER_TIME cannot be used with WALG_RECOVER_STANDBY=true"
        fi
    fi
    resolve_recover_path

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

    info "WAL-G recovery will replace Docker volume ${WALG_DATA_VOLUME} from ${WALG_RECOVER_STORAGE_PATH}."
    if is_true "${WALG_RECOVER_STANDBY}" WALG_RECOVER_STANDBY; then
        info "PostgreSQL will remain in standby mode and stream from primary ${WALG_RECOVER_PRIMARY_HOST}:${WALG_RECOVER_PRIMARY_PORT}."
    fi
    if [ -n "${WALG_RECOVER_TIME}" ]; then
        info "PostgreSQL will stop recovery at ${WALG_RECOVER_TIME} and promote."
    fi
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
}

validate_recover_path_access() {
    if [ "${WALG_RECOVER_STORAGE}" != "file" ]; then
        return
    fi

    info "Validating local WAL-G repository path ${WALG_RECOVER_STORAGE_PATH} in PostgreSQL container ${PG_CONTAINER}"
    if docker run --rm \
        --volumes-from "${PG_CONTAINER}:ro" \
        "${WALG_UTILITY_IMAGE}" \
        sh -c 'test -d "$1"' sh "${WALG_RECOVER_STORAGE_PATH}"; then
        return
    fi

    warn "PostgreSQL container mounts:"
    docker inspect "${PG_CONTAINER}" --format '{{range .Mounts}}{{printf "%s name=%s source=%s destination=%s\n" .Type .Name .Source .Destination}}{{end}}' >&2 || true
    error "Local WAL-G repository path ${WALG_RECOVER_STORAGE_PATH} is not mounted into PostgreSQL container ${PG_CONTAINER}"
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
    local signal_file

    signal_file=recovery.signal
    if is_true "${WALG_RECOVER_STANDBY}" WALG_RECOVER_STANDBY; then
        signal_file=standby.signal
    fi

    if docker run --rm \
        --volumes-from "${PG_CONTAINER}:ro" \
        "${WALG_UTILITY_IMAGE}" \
        sh -c 'test -f "$1/postgresql.auto.conf" && test -f "$1/$2" && test -f "$1/walg_restore.log"' sh "${WALG_DATA_DIR}" "${signal_file}"; then
        return
    fi

    print_recovery_volume_diagnostics
    error "WAL-G recovery config was not installed in PostgreSQL data directory ${WALG_DATA_DIR}"
}

wait_for_postgres_container_stopped() {
    local container_state
    local deadline

    deadline=$((SECONDS + WALG_RECOVER_STOP_WAIT_SECONDS))
    while [ "${SECONDS}" -lt "${deadline}" ]; do
        container_state=$(docker inspect "${PG_CONTAINER}" --format '{{.State.Status}}' 2>/dev/null || true)
        case "${container_state}" in
        created | dead | exited)
            return
            ;;
        "")
            error "PostgreSQL container ${PG_CONTAINER} does not exist"
            ;;
        esac
        sleep 1
    done

    container_state=$(docker inspect "${PG_CONTAINER}" --format '{{.State.Status}}' 2>/dev/null || true)
    error "PostgreSQL container ${PG_CONTAINER} is still ${container_state:-missing} after ${WALG_RECOVER_STOP_WAIT_SECONDS}s"
}

stop_postgres_container() {
    local container_state

    container_state=$(docker inspect "${PG_CONTAINER}" --format '{{.State.Status}}')
    if [ "${container_state}" = "paused" ]; then
        info "Unpausing PostgreSQL container ${PG_CONTAINER}"
        docker unpause "${PG_CONTAINER}" >/dev/null
        container_state=running
    fi
    if [ "${container_state}" = "running" ] || [ "${container_state}" = "restarting" ]; then
        info "Stopping PostgreSQL container ${PG_CONTAINER}"
        docker stop "${PG_CONTAINER}" >/dev/null
        wait_for_postgres_container_stopped
        return
    fi

    warn "PostgreSQL container ${PG_CONTAINER} is ${container_state}; continuing with offline recovery"
    wait_for_postgres_container_stopped
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
    local storage_env=()

    fetch_started=${SECONDS}
    info "Fetching WAL-G backup ${WALG_RECOVER_BACKUP_NAME} from ${WALG_RECOVER_STORAGE_PATH}"
    if [ "${WALG_RECOVER_STORAGE}" = "s3" ]; then
        storage_env=(
            -e "AWS_ENDPOINT=${WALG_RECOVER_S3_ENDPOINT}"
            -e "AWS_REGION=${WALG_RECOVER_S3_REGION}"
            -e "AWS_ACCESS_KEY_ID=${WALG_RECOVER_S3_ACCESS_KEY}"
            -e "AWS_SECRET_ACCESS_KEY=${WALG_RECOVER_S3_SECRET_KEY}"
            -e "WALG_S3_PREFIX=${WALG_RECOVER_STORAGE_PATH}"
        )
    else
        storage_env=(-e "WALG_FILE_PREFIX=${WALG_RECOVER_STORAGE_PATH}")
    fi
    docker run --rm \
        --user "${POSTGRES_UID}:${POSTGRES_GID}" \
        --volumes-from "${PG_CONTAINER}" \
        "${storage_env[@]}" \
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
        -e "WALG_RECOVER_STORAGE=${WALG_RECOVER_STORAGE}" \
        -e "WALG_RECOVER_STORAGE_PATH=${WALG_RECOVER_STORAGE_PATH}" \
        -e "WALG_RECOVER_PGUSER=${WALG_RECOVER_PGUSER}" \
        -e "WALG_RECOVER_S3_ENDPOINT=${WALG_RECOVER_S3_ENDPOINT}" \
        -e "WALG_RECOVER_S3_REGION=${WALG_RECOVER_S3_REGION}" \
        -e "WALG_RECOVER_S3_ACCESS_KEY=${WALG_RECOVER_S3_ACCESS_KEY}" \
        -e "WALG_RECOVER_S3_SECRET_KEY=${WALG_RECOVER_S3_SECRET_KEY}" \
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
                if [ "${WALG_RECOVER_STORAGE}" = "s3" ]; then
                    printf "export AWS_ENDPOINT=%s\n" "$(quote_env "${WALG_RECOVER_S3_ENDPOINT}")"
                    printf "export AWS_REGION=%s\n" "$(quote_env "${WALG_RECOVER_S3_REGION}")"
                    printf "export AWS_ACCESS_KEY_ID=%s\n" "$(quote_env "${WALG_RECOVER_S3_ACCESS_KEY}")"
                    printf "export AWS_SECRET_ACCESS_KEY=%s\n" "$(quote_env "${WALG_RECOVER_S3_SECRET_KEY}")"
                    printf "export WALG_S3_PREFIX=%s\n" "$(quote_env "${WALG_RECOVER_STORAGE_PATH}")"
                else
                    printf "export WALG_FILE_PREFIX=%s\n" "$(quote_env "${WALG_RECOVER_STORAGE_PATH}")"
                fi
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
        -e "WALG_RECOVER_TIME=${WALG_RECOVER_TIME}" \
        -e "WALG_RECOVER_STANDBY=${WALG_RECOVER_STANDBY}" \
        -e "WALG_RECOVER_PRIMARY_HOST=${WALG_RECOVER_PRIMARY_HOST}" \
        -e "WALG_RECOVER_PRIMARY_PORT=${WALG_RECOVER_PRIMARY_PORT}" \
        -e "WALG_RECOVER_PRIMARY_USER=${WALG_RECOVER_PRIMARY_USER}" \
        -e "WALG_RECOVER_PRIMARY_PASSWORD=${WALG_RECOVER_PRIMARY_PASSWORD}" \
        -e "WALG_RECOVER_PRIMARY_SSL=${WALG_RECOVER_PRIMARY_SSL}" \
        "${WALG_UTILITY_IMAGE}" \
        sh -c '
            sq=$(printf "\047")
            quote_conf() {
                printf "%s" "$1" | sed "s/${sq}/${sq}${sq}/g"
            }

            {
                printf "%s\n" "${RESTORE_COMMAND}"
                if [ "${WALG_RECOVER_STANDBY}" = "1" ] || [ "${WALG_RECOVER_STANDBY}" = "true" ] || [ "${WALG_RECOVER_STANDBY}" = "True" ] || [ "${WALG_RECOVER_STANDBY}" = "TRUE" ]; then
                    printf "primary_conninfo = %shost=%s port=%s user=%s password=%s sslmode=%s%s\n" \
                        "${sq}" \
                        "$(quote_conf "${WALG_RECOVER_PRIMARY_HOST}")" \
                        "$(quote_conf "${WALG_RECOVER_PRIMARY_PORT}")" \
                        "$(quote_conf "${WALG_RECOVER_PRIMARY_USER}")" \
                        "$(quote_conf "${WALG_RECOVER_PRIMARY_PASSWORD}")" \
                        "$(quote_conf "${WALG_RECOVER_PRIMARY_SSL}")" \
                        "${sq}"
                fi
                if [ -n "${WALG_RECOVER_TIME}" ]; then
                    printf "recovery_target_time = %s%s%s\n" "${sq}" "$(quote_conf "${WALG_RECOVER_TIME}")" "${sq}"
                    printf "recovery_target_action = %spromote%s\n" "${sq}" "${sq}"
                fi
            } >> "$1/postgresql.auto.conf"
            rm -f "$1/recovery.signal" "$1/standby.signal"
            if [ "${WALG_RECOVER_STANDBY}" = "1" ] || [ "${WALG_RECOVER_STANDBY}" = "true" ] || [ "${WALG_RECOVER_STANDBY}" = "True" ] || [ "${WALG_RECOVER_STANDBY}" = "TRUE" ]; then
                touch "$1/standby.signal"
            else
                touch "$1/recovery.signal"
            fi
            : > "$1/walg_restore.log"
        ' sh "${WALG_DATA_DIR}"
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

wait_for_standby() {
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

    info "Waiting up to ${WALG_RECOVER_WAIT_SECONDS}s for PostgreSQL to start as standby"
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
            if [ "${recovery_state}" = "t" ]; then
                RECOVERY_COMPLETED=true
                info "PostgreSQL standby started in $((SECONDS - recovery_started))s"
                return
            fi
        fi

        if [ "${SECONDS}" -ge "${next_progress}" ]; then
            elapsed=$((SECONDS - recovery_started))
            remaining=$((deadline - SECONDS))
            if [ "${remaining}" -lt 0 ]; then
                remaining=0
            fi
            info "Standby startup in progress after ${elapsed}s; ${remaining}s until timeout; $(container_metrics); postgres=${ready_state}; pg_is_in_recovery=${recovery_state}; $(recovery_volume_metrics); ${database_metrics:-replay_lsn=unknown}"
            next_progress=$((SECONDS + WALG_RECOVER_PROGRESS_SECONDS))
        fi

        sleep 5
    done

    print_diagnostics
    error "PostgreSQL did not start as standby within ${WALG_RECOVER_WAIT_SECONDS}s"
}

wait_for_postgres_health() {
    local deadline
    local expected_recovery_state
    local health_state
    local recovery_state
    local health_started

    if ! is_true "${WALG_RECOVER_START}" WALG_RECOVER_START || ! is_true "${WALG_RECOVER_WAIT}" WALG_RECOVER_WAIT; then
        return
    fi

    info "Waiting up to ${WALG_RECOVER_HEALTH_WAIT_SECONDS}s for PostgreSQL to become healthy"
    health_started=${SECONDS}
    deadline=$((SECONDS + WALG_RECOVER_HEALTH_WAIT_SECONDS))
    expected_recovery_state=f
    if is_true "${WALG_RECOVER_STANDBY}" WALG_RECOVER_STANDBY; then
        expected_recovery_state=t
    fi
    while [ "${SECONDS}" -lt "${deadline}" ]; do
        health_state=$(docker inspect "${PG_CONTAINER}" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' 2>/dev/null || true)
        if [ "$(docker inspect "${PG_CONTAINER}" --format '{{.State.Status}}' 2>/dev/null || true)" = "running" ] &&
            [ "${health_state}" = "healthy" ] &&
            postgres_ready; then
            recovery_state=$(postgres_recovery_state)
            if [ "${recovery_state}" = "${expected_recovery_state}" ]; then
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

    if is_true "${WALG_RECOVER_STANDBY}" WALG_RECOVER_STANDBY; then
        info "Leaving WAL-G restore command in place for standby archive recovery"
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
    if [ -n "${WALG_RECOVER_TIME}" ]; then
        info "Resetting temporary recovery target settings"
        docker exec "${PG_CONTAINER}" psql -p "${PG_PORT}" -U "${WALG_RECOVER_PGUSER}" -d postgres -c "ALTER SYSTEM RESET recovery_target_time"
        docker exec "${PG_CONTAINER}" psql -p "${PG_PORT}" -U "${WALG_RECOVER_PGUSER}" -d postgres -c "ALTER SYSTEM RESET recovery_target_action"
    fi
    docker exec "${PG_CONTAINER}" psql -p "${PG_PORT}" -U "${WALG_RECOVER_PGUSER}" -d postgres -c "SELECT pg_reload_conf()"

    if [ -n "${RESTORE_SCRIPT:-}" ]; then
        info "Removing temporary WAL-G recovery config ${RESTORE_SCRIPT}"
        remove_restore_command
        RESTORE_CONFIG_INSTALLED=false
        RESTORE_SCRIPT=""
    fi
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
    validate_recover_path_access
    wait_before_recovery
    stop_postgres_container
    clear_data
    fetch_backup
    validate_recovered_data_files
    install_restore_command
    enable_recovery
    validate_recovery_config_files
    start_postgres_container
    if is_true "${WALG_RECOVER_STANDBY}" WALG_RECOVER_STANDBY; then
        wait_for_standby
    else
        wait_for_recovery
    fi
    wait_for_postgres_health
    cleanup_recover_config
    finish
}

main "$@"
