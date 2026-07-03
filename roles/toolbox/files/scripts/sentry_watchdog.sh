#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=../lib/helpers.sh
source "${SCRIPT_DIR}/../lib/helpers.sh"

SCRIPT_NAME="sentry_watchdog"
LOCK_PATH="${SENTRY_WATCHDOG_LOCK_PATH:-/run/sentry-watchdog.lock}"
STATE_DIR="${SENTRY_WATCHDOG_STATE_DIR:-/var/lib/sentry-watchdog}"
COOLDOWN_SECONDS="${SENTRY_WATCHDOG_COOLDOWN_SECONDS:-1800}"
SINCE_SECONDS="${SENTRY_WATCHDOG_SINCE_SECONDS:-600}"
SETTLE_SECONDS="${SENTRY_WATCHDOG_SETTLE_SECONDS:-30}"
WAIT_SECONDS="${SENTRY_WATCHDOG_WAIT_SECONDS:-180}"
TOPIC_REGEX="${SENTRY_WATCHDOG_TOPIC_REGEX:-ingest-events}"
PROJECT_NAME="${SENTRY_WATCHDOG_PROJECT_NAME:-sentry-self-hosted}"
DRY_RUN=0
FORCE=0

usage() {
    cat <<'USAGE'
Usage: sentry_watchdog [--dry-run] [--force]

Check Sentry self-hosted health and run known safe repairs. Currently detects recent Relay Kafka producer timeouts for issue ingest topics and repairs the Kafka path by stopping Relay, restarting Kafka, then starting Relay again.

Environment:
  SENTRY_COMPOSE_DIR                  Override Docker Compose working directory.
  SENTRY_WATCHDOG_TOPIC_REGEX         Relay Kafka topic regex. Default: ingest-events.
  SENTRY_WATCHDOG_SINCE_SECONDS       Log lookback window. Default: 600.
  SENTRY_WATCHDOG_COOLDOWN_SECONDS    Minimum seconds between repairs. Default: 1800.
  SENTRY_WATCHDOG_SETTLE_SECONDS      Post-repair log settling delay. Default: 30.
  SENTRY_WATCHDOG_WAIT_SECONDS        Container health wait timeout. Default: 180.
USAGE
}

log() {
    local message="$1"

    _info "${SCRIPT_NAME}: ${message}"
    if command -v logger >/dev/null 2>&1; then
        logger -t "${SCRIPT_NAME}" -- "${message}" || true
    fi
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
        --dry-run)
            DRY_RUN=1
            ;;
        --force)
            FORCE=1
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            _usage_error "${SCRIPT_NAME}: unknown argument: $1"
            ;;
        esac
        shift
    done
}

require_positive_integer_env() {
    _require_positive_integer "${COOLDOWN_SECONDS}" "SENTRY_WATCHDOG_COOLDOWN_SECONDS"
    _require_positive_integer "${SINCE_SECONDS}" "SENTRY_WATCHDOG_SINCE_SECONDS"
    _require_positive_integer "${SETTLE_SECONDS}" "SENTRY_WATCHDOG_SETTLE_SECONDS"
    _require_positive_integer "${WAIT_SECONDS}" "SENTRY_WATCHDOG_WAIT_SECONDS"
}

container_name_for_service() {
    local service="$1"
    local container_id
    local name

    container_id="$(_docker ps --filter "label=com.docker.compose.project=${PROJECT_NAME}" --filter "label=com.docker.compose.service=${service}" --format '{{.ID}}' | head -n 1)"
    if [ -z "${container_id}" ]; then
        return 1
    fi

    name="$(_docker inspect --format '{{.Name}}' "${container_id}" | sed 's#^/##')"
    [ -n "${name}" ] || return 1
    printf '%s\n' "${name}"
}

detect_compose_dir() {
    local relay_container="$1"
    local candidate
    local inspect_dir

    if [ -n "${SENTRY_COMPOSE_DIR:-}" ]; then
        printf '%s\n' "${SENTRY_COMPOSE_DIR}"
        return 0
    fi

    inspect_dir="$(_docker inspect --format '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' "${relay_container}" 2>/dev/null || true)"
    if [ -n "${inspect_dir}" ] && [ "${inspect_dir}" != "<no value>" ]; then
        printf '%s\n' "${inspect_dir}"
        return 0
    fi

    for candidate in /opt/sentry /home/ansible/sentry; do
        if [ -f "${candidate}/docker-compose.yml" ] || [ -f "${candidate}/compose.yaml" ] || [ -f "${candidate}/compose.yml" ]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done

    return 1
}

compose_cmd() {
    local compose_dir="$1"
    shift

    _docker compose --project-directory "${compose_dir}" "$@"
}

recent_relay_timeout_count() {
    local relay_container="$1"
    local since_seconds="${2:-${SINCE_SECONDS}}"

    _docker logs --since "${since_seconds}s" "${relay_container}" 2>&1 |
        awk -v topic_regex="${TOPIC_REGEX}" '
            /failed to produce message to Kafka/ && $0 ~ "tags.topic=\"(" topic_regex ")\"" { count++ }
            END { print count + 0 }
        '
}

last_errors_local_timestamp() {
    local clickhouse_container

    if ! clickhouse_container="$(container_name_for_service clickhouse)"; then
        printf 'unknown'
        return 0
    fi

    _docker exec "${clickhouse_container}" clickhouse-client --query 'select toString(max(timestamp)) from errors_local' 2>/dev/null || printf 'unknown'
}

last_repair_epoch() {
    local state_path="${STATE_DIR}/last-repair-epoch"

    if [ -f "${state_path}" ]; then
        cat "${state_path}"
    else
        printf '0'
    fi
}

detection_since_seconds() {
    local last_repair="$1"
    local now
    local seconds_since_repair

    now="$(date -u +%s)"
    if [[ "${last_repair}" =~ ^[0-9]+$ ]] && [ "${last_repair}" -gt 0 ] && [ $((now - last_repair)) -lt "${SINCE_SECONDS}" ]; then
        seconds_since_repair=$((now - last_repair))
        if [ "${seconds_since_repair}" -lt 1 ]; then
            printf '1\n'
        else
            printf '%s\n' "${seconds_since_repair}"
        fi
        return 0
    fi

    printf '%s\n' "${SINCE_SECONDS}"
}

store_repair_epoch() {
    local now="$1"

    _cmd sudo mkdir -p "${STATE_DIR}"
    printf '%s\n' "${now}" | sudo tee "${STATE_DIR}/last-repair-epoch" >/dev/null
}

wait_container_ready() {
    local container="$1"
    local deadline
    local health
    local running

    deadline=$((SECONDS + WAIT_SECONDS))
    while [ "${SECONDS}" -lt "${deadline}" ]; do
        running="$(_docker inspect --format '{{.State.Running}}' "${container}" 2>/dev/null || true)"
        health="$(_docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${container}" 2>/dev/null || true)"

        if [ "${running}" = "true" ] && { [ "${health}" = "healthy" ] || [ "${health}" = "none" ]; }; then
            return 0
        fi

        sleep 5
    done

    _error "${SCRIPT_NAME}: ${container} did not become ready within ${WAIT_SECONDS}s"
}

repair_kafka_path() {
    local compose_dir="$1"
    local kafka_container
    local relay_container

    log "stopping relay before Kafka restart"
    if [ "${DRY_RUN}" -eq 0 ]; then
        _cmd compose_cmd "${compose_dir}" stop relay
    fi

    log "restarting Kafka"
    if [ "${DRY_RUN}" -eq 0 ]; then
        _cmd compose_cmd "${compose_dir}" restart kafka
        kafka_container="$(container_name_for_service kafka)"
        wait_container_ready "${kafka_container}"
    fi

    log "starting relay"
    if [ "${DRY_RUN}" -eq 0 ]; then
        _cmd compose_cmd "${compose_dir}" up -d relay
        relay_container="$(container_name_for_service relay)"
        wait_container_ready "${relay_container}"
    fi
}

main() {
    local compose_dir
    local errors_before
    local errors_after
    local inspect_since_seconds
    local last_error_ts
    local last_repair
    local now
    local relay_container

    parse_args "$@"
    require_positive_integer_env
    _require_command docker
    _require_command flock

    exec 9>"${LOCK_PATH}"
    if ! flock -n 9; then
        log "another repair run is active"
        return 0
    fi

    relay_container="$(container_name_for_service relay)" || _error "${SCRIPT_NAME}: Relay container not found"
    compose_dir="$(detect_compose_dir "${relay_container}")" || _error "${SCRIPT_NAME}: Sentry Compose directory not found"
    last_repair="$(last_repair_epoch)"
    [[ "${last_repair}" =~ ^[0-9]+$ ]] || last_repair=0
    inspect_since_seconds="$(detection_since_seconds "${last_repair}")"

    errors_before="$(recent_relay_timeout_count "${relay_container}" "${inspect_since_seconds}")"
    if [ "${FORCE}" -eq 0 ] && [ "${errors_before}" -eq 0 ]; then
        log "healthy; no Relay Kafka producer timeouts in the last ${inspect_since_seconds}s for topic regex ${TOPIC_REGEX}"
        return 0
    fi

    now="$(date -u +%s)"
    if [ "${FORCE}" -eq 0 ] && [ $((now - last_repair)) -lt "${COOLDOWN_SECONDS}" ]; then
        log "recent Relay Kafka producer timeouts still present but repair cooldown is active"
        return 2
    fi

    last_error_ts="$(last_errors_local_timestamp)"
    log "detected ${errors_before} recent Relay Kafka producer timeout(s); last errors_local timestamp=${last_error_ts}; compose_dir=${compose_dir}"
    repair_kafka_path "${compose_dir}"

    if [ "${DRY_RUN}" -eq 1 ]; then
        log "dry run complete; no containers changed"
        return 0
    fi

    store_repair_epoch "$(date -u +%s)"
    sleep "${SETTLE_SECONDS}"

    relay_container="$(container_name_for_service relay)" || _error "${SCRIPT_NAME}: Relay container not found after repair"
    errors_after="$(recent_relay_timeout_count "${relay_container}" "${SETTLE_SECONDS}")"
    if [ "${errors_after}" -gt 0 ]; then
        log "repair completed but ${errors_after} recent Relay Kafka producer timeout(s) remain"
        return 2
    fi

    last_error_ts="$(last_errors_local_timestamp)"
    log "repair completed; Relay Kafka producer timeouts cleared; last errors_local timestamp=${last_error_ts}"
}

main "$@"
