#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=../lib/helpers.sh
source "${SCRIPT_DIR}/../lib/helpers.sh"

LOG_DIR="/var/log/wg_debug"
RUN_DIR="/run/wg_debug"
PID_FILE="${RUN_DIR}/pid"
TAG_FILE="${RUN_DIR}/tag"
LOG_PATH_FILE="${RUN_DIR}/log_path"
WG_PORT="${WG_DEBUG_PORT:-51820}"
WG_CONTAINER="${WG_DEBUG_WG_CONTAINER:-wg-easy}"
XRAY_CONTAINER="${WG_DEBUG_XRAY_CONTAINER:-xray}"
TPROXY_SERVICE="${WG_DEBUG_TPROXY_SERVICE:-xray-tproxy}"
TPROXY_CHAIN="${WG_DEBUG_TPROXY_CHAIN:-XRAY_TPROXY}"
TPROXY_ROUTE_TABLE="${WG_DEBUG_TPROXY_ROUTE_TABLE:-100}"
SAMPLE_INTERVAL="${WG_DEBUG_SAMPLE_INTERVAL:-5}"
LOG_PATH=""
STREAM_PIDS=()
STOP_REQUESTED=0
FINISH_REASON="timeout"

usage() {
    cat <<'EOF'
Usage:
  wg_debug start <seconds>
  wg_debug stop
  wg_debug status
  wg_debug --help

Starts a read-only WireGuard server-side debug capture.

Environment overrides:
  WG_DEBUG_PORT=51820
  WG_DEBUG_WG_CONTAINER=wg-easy
  WG_DEBUG_XRAY_CONTAINER=xray
  WG_DEBUG_TPROXY_SERVICE=xray-tproxy
  WG_DEBUG_TPROXY_CHAIN=XRAY_TPROXY
  WG_DEBUG_TPROXY_ROUTE_TABLE=100
  WG_DEBUG_SAMPLE_INTERVAL=5
EOF
}

script_path() {
    printf '%s/%s\n' "${SCRIPT_DIR}" "$(basename -- "${BASH_SOURCE[0]}")"
}

require_root() {
    if [ "$(id -u)" -eq 0 ]; then
        return 0
    fi

    command -v sudo >/dev/null 2>&1 || _error "wg_debug requires root or passwordless sudo"
    exec sudo -n bash "$(script_path)" "$@"
}

ensure_runtime_dirs() {
    install -d -m 0750 -o root -g root "${LOG_DIR}"
    install -d -m 0750 -o root -g root "${RUN_DIR}"
}

read_file() {
    local path="$1"

    if [ -f "${path}" ]; then
        cat -- "${path}"
    fi
}

running_pid() {
    local pid="$1"

    [[ "${pid}" =~ ^[1-9][0-9]*$ ]] || return 1
    kill -0 "${pid}" >/dev/null 2>&1
}

active_pid() {
    read_file "${PID_FILE}" | head -n 1
}

active_log_path() {
    read_file "${LOG_PATH_FILE}" | head -n 1
}

active_tag() {
    read_file "${TAG_FILE}" | head -n 1
}

cleanup_state() {
    rm -f -- "${PID_FILE}" "${TAG_FILE}" "${LOG_PATH_FILE}"
}

clear_stale_state() {
    local pid

    pid="$(active_pid || true)"
    if [ -n "${pid}" ] && running_pid "${pid}"; then
        return 0
    fi

    cleanup_state
}

command_available() {
    command -v "$1" >/dev/null 2>&1 || [ "$(type -t "$1" 2>/dev/null || true)" = "function" ]
}

docker_cli_available() {
    command -v sudo >/dev/null 2>&1 && command -v docker >/dev/null 2>&1
}

redact_stream() {
    sed -E \
        -e 's/((PrivateKey|PresharedKey|private key|preshared key)[[:space:]]*[:=][[:space:]]*)[^[:space:],]+/\1***REDACTED***/g' \
        -e 's/((password|passwd|token|secret|credential|authorization)[A-Za-z0-9_.-]*[[:space:]]*[:=][[:space:]]*)[^[:space:],]+/\1***REDACTED***/Ig' \
        -e 's/(Authorization:[[:space:]]*)[^[:space:]]+/\1***REDACTED***/Ig'
}

append_line() {
    printf '%s\n' "$*" >>"${LOG_PATH}"
}

append_section_header() {
    append_line
    append_line "================================================================================"
    append_line "## $*"
    append_line "## $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    append_line "================================================================================"
}

append_note() {
    append_section_header "$1"
    shift
    printf '%s\n' "$@" >>"${LOG_PATH}"
}

run_section() {
    local title="$1"
    local command_name
    local status

    shift
    command_name="$1"
    append_section_header "${title}"
    {
        printf '# '
        printf '%q ' "$@"
        printf '\n'
    } >>"${LOG_PATH}"

    if [ "${command_name}" = "_docker" ] && ! docker_cli_available; then
        printf 'skipped: sudo docker is not available\n' >>"${LOG_PATH}"
        return 0
    fi

    if ! command_available "${command_name}"; then
        printf 'skipped: %s is not available\n' "${command_name}" >>"${LOG_PATH}"
        return 0
    fi

    set +e
    "$@" 2>&1 | redact_stream >>"${LOG_PATH}"
    status=${PIPESTATUS[0]}
    set -e

    printf '\nexit_status=%s\n' "${status}" >>"${LOG_PATH}"
    return 0
}

docker_container_exists() {
    docker_cli_available || return 1
    command_available _docker || return 1
    _docker container inspect "$1" >/dev/null 2>&1
}

docker_service_exists() {
    docker_cli_available || return 1
    command_available _docker || return 1
    _docker service inspect "$1" >/dev/null 2>&1
}

collect_container_snapshot() {
    local container="$1"
    local label="$2"

    if ! docker_container_exists "${container}"; then
        append_note "${label} container" "skipped: container ${container} was not found"
        return 0
    fi

    # shellcheck disable=SC2016
    run_section "${label} container state" \
        _docker inspect \
        --format 'name={{.Name}}
image={{.Config.Image}}
state={{json .State}}
ports={{json .NetworkSettings.Ports}}
networks={{range $name, $network := .NetworkSettings.Networks}}{{printf "%s ip=%s gateway=%s mac=%s\n" $name $network.IPAddress $network.Gateway $network.MacAddress}}{{end}}
mounts={{range .Mounts}}{{printf "%s source=%s destination=%s\n" .Type .Source .Destination}}{{end}}' \
        "${container}"
    run_section "${label} container interfaces" _docker exec "${container}" ip -details addr show
    run_section "${label} container routes" _docker exec "${container}" ip route show table all
}

collect_wg_container_snapshot() {
    collect_container_snapshot "${WG_CONTAINER}" "wg-easy"

    if docker_container_exists "${WG_CONTAINER}"; then
        run_section "wg-easy WireGuard state" _docker exec "${WG_CONTAINER}" wg show
        run_section "wg-easy recent logs" _docker logs --tail 200 "${WG_CONTAINER}"
        run_section "wg-easy container DNS probe" _docker exec "${WG_CONTAINER}" sh -c 'getent hosts example.com 2>&1 || true'
        run_section "wg-easy container HTTP probe" _docker exec "${WG_CONTAINER}" sh -c 'command -v curl >/dev/null 2>&1 && curl -4 -fsS --max-time 5 https://ipinfo.io/ip || true'
    fi
}

collect_xray_snapshot() {
    collect_container_snapshot "${XRAY_CONTAINER}" "xray"

    if docker_container_exists "${XRAY_CONTAINER}"; then
        run_section "xray recent container logs" _docker logs --tail 200 "${XRAY_CONTAINER}"
    fi

    if docker_service_exists "xray"; then
        run_section "xray swarm service" _docker service ps --no-trunc "xray"
        run_section "xray recent swarm logs" _docker service logs --tail 200 "xray"
    else
        append_note "xray swarm service" "skipped: service xray was not found"
    fi
}

collect_snapshot() {
    local label="$1"

    append_section_header "${label} snapshot"
    run_section "Host identity" bash -c 'date -u "+utc=%Y-%m-%dT%H:%M:%SZ"; hostname; hostname -f 2>/dev/null || true; uname -a; uptime'
    run_section "Kernel command line" cat /proc/cmdline
    run_section "Network addresses" ip -details addr show
    run_section "Interface counters" ip -s link show
    run_section "Routes" ip route show table all
    run_section "Rules" ip rule show
    # shellcheck disable=SC2016
    run_section "Forwarding and mark sysctls" bash -c '
for key in \
  net.ipv4.ip_forward \
  net.ipv4.conf.all.forwarding \
  net.ipv4.conf.default.forwarding \
  net.ipv4.conf.all.src_valid_mark \
  net.ipv4.conf.default.src_valid_mark \
  net.ipv4.conf.all.rp_filter \
  net.ipv4.conf.default.rp_filter; do
    sysctl "$key" 2>&1 || true
done
'
    run_section "Host WireGuard state" wg show
    run_section "UDP listeners" ss -H -lunp
    run_section "UDP sockets" ss -H -uanp
    run_section "Docker containers" _docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
    collect_wg_container_snapshot
    run_section "iptables filter counters" iptables -L -n -v -x --line-numbers
    run_section "iptables nat counters" iptables -t nat -L -n -v -x --line-numbers
    run_section "iptables mangle counters" iptables -t mangle -L -n -v -x --line-numbers
    run_section "iptables-save counters" iptables-save -c
    run_section "nft ruleset" nft list ruleset
    run_section "TPROXY service status" systemctl status "${TPROXY_SERVICE}" --no-pager
    run_section "TPROXY route table" ip route show table "${TPROXY_ROUTE_TABLE}"
    run_section "TPROXY mangle chain" iptables -t mangle -L "${TPROXY_CHAIN}" -n -v -x --line-numbers
    collect_xray_snapshot
    run_section "Host DNS probe getent" getent hosts example.com
    run_section "Host DNS probe dig" dig +time=2 +tries=1 example.com
    run_section "Host HTTP public IP probe" curl -4 -fsS --max-time 5 https://ipinfo.io/ip
}

collect_periodic_sample() {
    append_section_header "Periodic sample"
    run_section "Host WireGuard state" wg show
    if docker_container_exists "${WG_CONTAINER}"; then
        run_section "wg-easy WireGuard state" _docker exec "${WG_CONTAINER}" wg show
    fi
    run_section "Interface counters" ip -s link show
    run_section "iptables filter counters" iptables -L -n -v -x --line-numbers
    run_section "iptables mangle counters" iptables -t mangle -L -n -v -x --line-numbers
    run_section "TPROXY mangle chain" iptables -t mangle -L "${TPROXY_CHAIN}" -n -v -x --line-numbers
}

start_stream() {
    local name="$1"
    local command_name
    local pid

    shift
    command_name="$1"
    if [ "${command_name}" = "_docker" ] && ! docker_cli_available; then
        append_note "Stream ${name}" "skipped: sudo docker is not available"
        return 0
    fi

    if ! command_available "${command_name}"; then
        append_note "Stream ${name}" "skipped: ${command_name} is not available"
        return 0
    fi

    (
        printf '\n================================================================================\n'
        printf '## stream %s started at %s\n' "${name}" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        printf '================================================================================\n'
        "$@" 2>&1 | redact_stream | sed -u "s/^/[${name}] /"
        printf '\n## stream %s ended at %s\n' "${name}" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    ) >>"${LOG_PATH}" &
    pid=$!
    STREAM_PIDS+=("${pid}")
}

start_streams() {
    start_stream "journal" journalctl -f -n 0 --no-pager -o short-iso --no-hostname \
        -u docker \
        -u "${WG_CONTAINER}" \
        -u "${XRAY_CONTAINER}" \
        -u "${TPROXY_SERVICE}" \
        -u iptables-config

    if docker_container_exists "${WG_CONTAINER}"; then
        start_stream "docker-${WG_CONTAINER}" _docker logs --tail 0 -f "${WG_CONTAINER}"
    else
        append_note "Stream docker-${WG_CONTAINER}" "skipped: container ${WG_CONTAINER} was not found"
    fi

    if docker_container_exists "${XRAY_CONTAINER}"; then
        start_stream "docker-${XRAY_CONTAINER}" _docker logs --tail 0 -f "${XRAY_CONTAINER}"
    else
        append_note "Stream docker-${XRAY_CONTAINER}" "skipped: container ${XRAY_CONTAINER} was not found"
    fi

    start_stream "tcpdump-udp-${WG_PORT}" tcpdump -i any -n -tttt -vv -s 160 udp port "${WG_PORT}"
}

stop_streams() {
    local pid

    for pid in "${STREAM_PIDS[@]}"; do
        pkill -TERM -P "${pid}" >/dev/null 2>&1 || true
        kill -TERM "${pid}" >/dev/null 2>&1 || true
    done

    sleep 1 || true

    for pid in "${STREAM_PIDS[@]}"; do
        if running_pid "${pid}"; then
            pkill -KILL -P "${pid}" >/dev/null 2>&1 || true
            kill -KILL "${pid}" >/dev/null 2>&1 || true
        fi
    done

    wait "${STREAM_PIDS[@]}" >/dev/null 2>&1 || true
}

handle_stop_signal() {
    STOP_REQUESTED=1
    FINISH_REASON="stopped"
}

daemon_main() {
    local duration="$1"
    local tag="$2"
    local end_time
    local now
    local next_sample

    LOG_PATH="$3"
    trap handle_stop_signal TERM INT

    {
        printf 'wg_debug tag=%s\n' "${tag}"
        printf 'started_at=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        printf 'duration_seconds=%s\n' "${duration}"
        printf 'wg_port=%s\n' "${WG_PORT}"
        printf 'wg_container=%s\n' "${WG_CONTAINER}"
        printf 'xray_container=%s\n' "${XRAY_CONTAINER}"
        printf 'tproxy_service=%s\n' "${TPROXY_SERVICE}"
        printf 'tproxy_chain=%s\n' "${TPROXY_CHAIN}"
        printf 'tproxy_route_table=%s\n' "${TPROXY_ROUTE_TABLE}"
    } >>"${LOG_PATH}"

    collect_snapshot "Initial"
    start_streams

    end_time=$(($(date -u '+%s') + duration))
    next_sample=0

    while [ "${STOP_REQUESTED}" -eq 0 ]; do
        now=$(date -u '+%s')
        if [ "${now}" -ge "${end_time}" ]; then
            break
        fi

        if [ "${now}" -ge "${next_sample}" ]; then
            collect_periodic_sample
            next_sample=$((now + SAMPLE_INTERVAL))
        fi

        sleep 1 || true
    done

    if [ "${STOP_REQUESTED}" -ne 0 ]; then
        FINISH_REASON="stopped"
    fi

    stop_streams
    collect_snapshot "Final"
    append_note "Capture complete" "finished_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "finish_reason=${FINISH_REASON}" "log_path=${LOG_PATH}"
    cleanup_state
}

start_capture() {
    local duration="${1:-}"
    local existing_pid
    local log_path
    local pid
    local tag

    _require_positive_integer "${duration}" "seconds"
    _require_positive_integer "${SAMPLE_INTERVAL}" "WG_DEBUG_SAMPLE_INTERVAL"
    ensure_runtime_dirs
    clear_stale_state

    existing_pid="$(active_pid || true)"
    if [ -n "${existing_pid}" ] && running_pid "${existing_pid}"; then
        printf 'wg_debug is already running: pid=%s log=%s\n' "${existing_pid}" "$(active_log_path || true)" >&2
        return 1
    fi

    tag="$(date -u '+%y%m%d%H%M%S')"
    log_path="${LOG_DIR}/${tag}.log"
    : >"${log_path}"
    chmod 0640 "${log_path}"

    printf '%s\n' "${tag}" >"${TAG_FILE}"
    printf '%s\n' "${log_path}" >"${LOG_PATH_FILE}"

    if command -v setsid >/dev/null 2>&1; then
        setsid bash "$(script_path)" __daemon "${duration}" "${tag}" "${log_path}" >/dev/null 2>&1 &
    else
        nohup bash "$(script_path)" __daemon "${duration}" "${tag}" "${log_path}" >/dev/null 2>&1 &
    fi
    pid=$!
    printf '%s\n' "${pid}" >"${PID_FILE}"

    sleep 1 || true
    if ! running_pid "${pid}"; then
        cleanup_state
        printf 'wg_debug failed to start. Log: %s\n' "${log_path}" >&2
        return 1
    fi

    printf 'wg_debug started: pid=%s log=%s timeout=%ss\n' "${pid}" "${log_path}" "${duration}"
}

stop_capture() {
    local log_path
    local pid

    ensure_runtime_dirs
    pid="$(active_pid || true)"
    log_path="$(active_log_path || true)"

    if [ -z "${pid}" ]; then
        printf 'wg_debug is not running\n'
        return 1
    fi

    if ! running_pid "${pid}"; then
        cleanup_state
        printf 'wg_debug was not running; stale state removed'
        if [ -n "${log_path}" ]; then
            printf ' log=%s' "${log_path}"
        fi
        printf '\n'
        return 1
    fi

    kill -TERM "${pid}" >/dev/null 2>&1 || true
    for _ in $(seq 1 30); do
        if ! running_pid "${pid}"; then
            break
        fi
        sleep 1 || true
    done

    if running_pid "${pid}"; then
        kill -KILL "${pid}" >/dev/null 2>&1 || true
        cleanup_state
        printf 'wg_debug forced to stop: pid=%s' "${pid}"
    else
        printf 'wg_debug stopped: pid=%s' "${pid}"
    fi

    if [ -n "${log_path}" ]; then
        printf ' log=%s' "${log_path}"
    fi
    printf '\n'
}

status_capture() {
    local log_path
    local pid
    local tag

    ensure_runtime_dirs
    pid="$(active_pid || true)"
    tag="$(active_tag || true)"
    log_path="$(active_log_path || true)"

    if [ -n "${pid}" ] && running_pid "${pid}"; then
        printf 'wg_debug running: pid=%s tag=%s log=%s\n' "${pid}" "${tag:-unknown}" "${log_path:-unknown}"
        return 0
    fi

    if [ -n "${pid}" ]; then
        cleanup_state
        printf 'wg_debug not running; stale state removed'
        if [ -n "${log_path}" ]; then
            printf ' last_log=%s' "${log_path}"
        fi
        printf '\n'
        return 1
    fi

    printf 'wg_debug not running\n'
}

main() {
    local command="${1:-}"

    case "${command}" in
    start)
        shift
        [ "$#" -eq 1 ] || _usage_error "wg_debug start requires exactly one positive integer timeout"
        _require_positive_integer "$1" "seconds"
        require_root start "$@"
        start_capture "$1"
        ;;
    stop)
        shift
        [ "$#" -eq 0 ] || _usage_error "wg_debug stop does not accept arguments"
        require_root stop
        stop_capture
        ;;
    status)
        shift
        [ "$#" -eq 0 ] || _usage_error "wg_debug status does not accept arguments"
        require_root status
        status_capture
        ;;
    --help | -h)
        usage
        ;;
    __daemon)
        shift
        [ "$#" -eq 3 ] || _error "invalid daemon invocation"
        daemon_main "$@"
        ;;
    "")
        _usage_error "missing command"
        ;;
    *)
        _usage_error "unknown command: ${command}"
        ;;
    esac
}

main "$@"
