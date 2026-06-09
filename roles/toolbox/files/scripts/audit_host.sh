#!/usr/bin/env bash

set -o pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=../lib/helpers.sh
source "${SCRIPT_DIR}/../lib/helpers.sh"

AUDIT_QUIET="${AUDIT_QUIET:-0}"
AUDIT_LOG_ERROR_REGEX="${AUDIT_LOG_ERROR_REGEX:-(?i)\b(fatal|panic|critical|crit|error|exception|traceback)\b}"
AUDIT_LOG_IGNORE_REGEX="${AUDIT_LOG_IGNORE_REGEX:-(?i)\b(no errors?|0 errors?|without errors?|error=0)\b|level=(debug|info|warn|warning)|failed to validate image signature.*\x65xp\x65ct\x65d image index descriptor}"
AUDIT_LOG_MATCH_LIMIT="${AUDIT_LOG_MATCH_LIMIT:-20}"
AUDIT_ISSUES=()
AUDIT_CHECKS=0

usage() {
    printf 'Usage: %s [--quiet]\n' "$(basename "$0")"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
    --quiet)
        AUDIT_QUIET=1
        shift
        ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        _usage_error "unknown argument: $1"
        ;;
    esac
done

_audit_is_quiet() {
    _is_true "${AUDIT_QUIET}" "AUDIT_QUIET"
}

_audit_info() {
    if ! _audit_is_quiet; then
        printf '%s\n' "$*"
    fi
}

_audit_issue() {
    AUDIT_ISSUES+=("$*")
}

_audit_check() {
    AUDIT_CHECKS=$((AUDIT_CHECKS + 1))
}

_audit_list_contains() {
    local needle="$1"
    local item

    shift
    for item in "$@"; do
        if [ "${item}" = "${needle}" ]; then
            return 0
        fi
    done
    return 1
}

_audit_read_lines() {
    local var_name="$1"
    local line

    while IFS= read -r line || [ -n "${line}" ]; do
        [ -n "${line}" ] && printf '%s\0' "${line}"
    done <<<"${!var_name:-}"
}

_audit_match_error() {
    local line="$1"

    printf '%s\n' "${line}" | grep -P "${AUDIT_LOG_ERROR_REGEX}" >/dev/null 2>&1 || return 1
    if printf '%s\n' "${line}" | grep -P "${AUDIT_LOG_IGNORE_REGEX}" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

_audit_require_commands() {
    local command_name

    for command_name in awk cat df find grep journalctl ls python3 sshd stat systemctl ufw visudo; do
        if ! command -v "${command_name}" >/dev/null 2>&1; then
            _audit_issue "Missing required command: ${command_name}"
        fi
    done
}

_audit_check_ufw() {
    local output

    _audit_check
    output=$(ufw status 2>&1)
    if ! printf '%s\n' "${output}" | grep -qi "status: active"; then
        _audit_issue "UFW is not active. Status: ${output}"
    fi
}

_audit_check_ssh() {
    local output

    _audit_check
    if ! output=$(sshd -T 2>&1); then
        _audit_issue "SSH effective configuration could not be gathered: ${output}"
        return
    fi

    output=$(printf '%s\n' "${output}" | tr '[:upper:]' '[:lower:]')
    for expected in \
        "passwordauthentication no" \
        "permitrootlogin no" \
        "kbdinteractiveauthentication no" \
        "pubkeyauthentication yes" \
        "permitemptypasswords no" \
        "maxauthtries 3" \
        "logingracetime 30" \
        "x11forwarding no" \
        "port ${AUDIT_SSH_PORT:-22}"; do
        if ! grep -Fqx "${expected}" <<<"${output}"; then
            _audit_issue "SSH effective configuration is missing: ${expected}"
        fi
    done

    if [ -n "${AUDIT_SSH_USERS:-}" ] && ! grep -q "^allowusers " <<<"${output}"; then
        _audit_issue "SSH effective configuration is missing AllowUsers."
    fi
}

_audit_check_systemd() {
    local unit state type active_state failed_state line logs match_count
    local critical_units inactive_units running_states unit_files

    mapfile -d '' -t critical_units < <(_audit_read_lines AUDIT_CRITICAL_SYSTEMD_UNITS)
    mapfile -d '' -t inactive_units < <(_audit_read_lines AUDIT_INACTIVE_SYSTEMD_UNITS)
    mapfile -d '' -t running_states < <(_audit_read_lines AUDIT_RUNNING_SYSTEMD_UNIT_FILE_STATES)

    _audit_check
    for unit in "${critical_units[@]}"; do
        if ! systemctl cat "${unit}" >/dev/null 2>&1; then
            _audit_issue "${unit} service unit is not installed."
        fi
    done

    if ! unit_files=$(systemctl list-unit-files --type=service --no-legend --no-pager 2>&1); then
        _audit_issue "Installed systemd service units could not be listed: ${unit_files}"
        return
    fi

    while read -r unit state _; do
        [ -n "${unit}" ] || continue
        [[ "${unit}" == *"@."* ]] && continue

        failed_state=$(systemctl is-failed "${unit}" 2>&1)
        case "$?" in
        0) _audit_issue "${unit} is failed." ;;
        1) ;;
        *) _audit_issue "${unit} failed state could not be checked: ${failed_state}" ;;
        esac

        match_count=0
        logs=$(journalctl -u "${unit}" --since "${AUDIT_SYSTEMD_LOG_SINCE_JOURNAL:-5 minutes ago}" --no-pager -o short-iso 2>&1)
        case "$?" in
        0 | 1)
            while IFS= read -r line || [ -n "${line}" ]; do
                if _audit_match_error "${line}"; then
                    match_count=$((match_count + 1))
                    if [ "${match_count}" -le "${AUDIT_LOG_MATCH_LIMIT:-20}" ]; then
                        _audit_issue "Recent journal logs for ${unit} contain error pattern: ${line}"
                    fi
                fi
            done <<<"${logs}"
            ;;
        *) _audit_issue "Recent journal logs for ${unit} could not be gathered: ${logs}" ;;
        esac

        if ! _audit_list_contains "${state}" "${running_states[@]}"; then
            continue
        fi

        if ! type=$(systemctl show --property=Type --value "${unit}" 2>&1); then
            _audit_issue "${unit} service type could not be checked: ${type}"
            continue
        fi
        [ "${type}" = "oneshot" ] && continue
        _audit_list_contains "${unit}" "${inactive_units[@]}" && continue

        if ! active_state=$(systemctl is-active "${unit}" 2>&1); then
            _audit_issue "${unit} is configured to start but is not active. State: ${active_state}"
        fi
    done <<<"${unit_files}"
}

_audit_check_apt_timer() {
    _audit_check
    if [ -e /lib/systemd/system/apt-daily-upgrade.timer ] && ! systemctl is-enabled apt-daily-upgrade.timer >/dev/null 2>&1; then
        _audit_issue "apt-daily-upgrade timer is not enabled."
    fi
}

_audit_check_sysctl() {
    local line name expected actual path params

    _audit_check
    if ! params=$(
             python3 - <<'PY' 2>&1
import json
import os

for item in json.loads(os.environ.get("AUDIT_SYSCTL_PARAMS_JSON", "[]")):
    print(f"{item['name']}={item['value']}")
PY
    ); then
        _audit_issue "Sysctl expectations could not be parsed: ${params}"
        return
    fi

    while IFS= read -r line || [ -n "${line}" ]; do
        [ -n "${line}" ] || continue
        name="${line%%=*}"
        expected="${line#*=}"
        path="/proc/sys/${name//./\/}"
        if [ ! -r "${path}" ]; then
            _audit_issue "Sysctl ${name} is not readable at ${path}."
            continue
        fi
        actual=$(cat "${path}")
        if [ "${actual}" != "${expected}" ]; then
            _audit_issue "Sysctl ${name} expected ${expected}, got ${actual}."
        fi
    done <<<"${params}"
}

_audit_check_users() {
    local home_users allowed_users user empty_passwords uid0_users

    mapfile -t home_users < <(ls -1 /home 2>/dev/null || true)
    mapfile -d '' -t allowed_users < <(
        _audit_read_lines AUDIT_SERVICE_USERS
        _audit_read_lines AUDIT_ADMIN_USERS
    )

    _audit_check
    for user in "${home_users[@]}"; do
        if ! _audit_list_contains "${user}" "${allowed_users[@]}"; then
            _audit_issue "Unauthorized local user in /home: ${user}"
        fi
    done

    empty_passwords=$(awk -F: '$2 == "" {print $1}' /etc/shadow 2>&1)
    if [ -n "${empty_passwords}" ]; then
        _audit_issue "Accounts with empty passwords: ${empty_passwords}"
    fi

    uid0_users=$(awk -F: '$3 == 0 && $1 != "root" {print $1}' /etc/passwd 2>&1)
    if [ -n "${uid0_users}" ]; then
        _audit_issue "Extra UID 0 users found: ${uid0_users}"
    fi
}

_audit_check_file_state() {
    local path="$1"
    local expected_mode="$2"
    local expected_owner="$3"
    local expected_group="$4"
    local actual_mode actual_owner actual_group

    if [ ! -e "${path}" ]; then
        _audit_issue "${path} is missing."
        return
    fi

    actual_mode=$(stat -c "%a" "${path}" 2>&1)
    actual_owner=$(stat -c "%U" "${path}" 2>&1)
    actual_group=$(stat -c "%G" "${path}" 2>&1)
    if [ "${actual_mode}" != "${expected_mode}" ] || [ "${actual_owner}" != "${expected_owner}" ] || [ "${actual_group}" != "${expected_group}" ]; then
        _audit_issue "${path} has incorrect state. Expected ${expected_mode} ${expected_owner}:${expected_group}, got ${actual_mode} ${actual_owner}:${actual_group}"
    fi
}

_audit_check_files() {
    local tmp_mode rhosts visudo_output

    _audit_check
    _audit_check_file_state /etc/shadow 640 root shadow
    _audit_check_file_state /etc/passwd 644 root root
    _audit_check_file_state /etc/ssh/sshd_config 644 root root
    _audit_check_file_state /etc/sudoers 440 root root

    if ! visudo_output=$(visudo -c 2>&1); then
        _audit_issue "sudoers configuration is invalid: ${visudo_output}"
    fi

    if ! tmp_mode=$(stat -c "%a" /tmp 2>&1); then
        _audit_issue "/tmp state could not be checked: ${tmp_mode}"
    elif [ "$((10#${tmp_mode} / 1000))" -lt 1 ]; then
        _audit_issue "/tmp does not have sticky bit set (mode ${tmp_mode})."
    fi

    rhosts=$(find /root /home \( -name .rhosts -o -name .shosts -o -name hosts.equiv \) -print 2>/dev/null)
    if [ -n "${rhosts}" ]; then
        _audit_issue "rhosts files found: ${rhosts}"
    fi
}

_audit_check_docker() {
    local output

    _audit_check
    if ! systemctl cat docker >/dev/null 2>&1; then
        return
    fi

    if ! output=$(
             python3 - <<'PY' 2>&1
import json
with open("/etc/docker/daemon.json", encoding="utf-8") as daemon_file:
    data = json.load(daemon_file)
if any("tcp://" in host for host in data.get("hosts", [])):
    raise SystemExit("Docker daemon.json appears to expose TCP insecurely.")
PY
    ); then
        _audit_issue "Docker daemon configuration failed audit: ${output}"
    fi
}

_audit_check_disk() {
    local usage

    _audit_check
    usage=$(df -P / | awk 'NR == 2 { gsub("%", "", $5); print $5 }')
    if [ -z "${usage}" ]; then
        _audit_issue "Root filesystem usage could not be checked."
    elif [ "${usage}" -ge "${AUDIT_DISK_THRESHOLD:-90}" ]; then
        _audit_issue "Root filesystem usage is above ${AUDIT_DISK_THRESHOLD:-90}%."
    fi
}

_audit_check_fstab() {
    local counts exact_count swap_count

    _audit_check
    if [ ! -r /etc/fstab ]; then
        _audit_issue "/etc/fstab is not readable."
        return
    fi

    counts=$(awk '
        /^[[:space:]]*($|#)/ { next }
        $3 == "swap" {
            swap_count += 1
            if (NF == 6 && $1 == "/swapfile" && $2 == "none" && $4 == "sw" && $5 == "0" && $6 == "0") {
                exact_count += 1
            }
        }
        END { printf "%d %d\n", swap_count, exact_count }
    ' /etc/fstab)
    swap_count="${counts%% *}"
    exact_count="${counts##* }"
    if [ "${swap_count}" -ne 1 ] || [ "${exact_count}" -ne 1 ]; then
        _audit_issue "/etc/fstab must contain exactly one active swap entry: /swapfile none swap sw 0 0"
    fi
}

_audit_print_result() {
    local issue

    if [ "${#AUDIT_ISSUES[@]}" -eq 0 ]; then
        _audit_info "Audit passed (${AUDIT_CHECKS} check groups)."
        return 0
    fi

    if ! _audit_is_quiet; then
        printf 'Audit found %s issue(s):\n' "${#AUDIT_ISSUES[@]}"
    fi

    for issue in "${AUDIT_ISSUES[@]}"; do
        printf '%s\n' "${issue}"
    done

    return 1
}

_audit_info "Running host audit."
_audit_require_commands
if [ "${#AUDIT_ISSUES[@]}" -eq 0 ]; then
    _audit_check_ufw
    _audit_check_ssh
    _audit_check_systemd
    _audit_check_apt_timer
    _audit_check_sysctl
    _audit_check_users
    _audit_check_files
    _audit_check_docker
    _audit_check_disk
    _audit_check_fstab
fi
_audit_print_result
