#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="${PWD}"
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="${HOME}/.ssh/known_hosts")

prompt() {
    local label="$1" default="$2" val
    while true; do
        read -r -p "${label}${default:+ [${default}]}: " val
        val="${val:-${default}}"
        [ -n "$val" ] && break
    done
    echo "$val"
}

copy_ssh_key() {
    echo "Running ssh-copy-id..."
    ssh-copy-id "${SSH_OPTS[@]}" -p "${SSH_PORT}" "${SSH_USER}@${SSH_HOST}"
}

setup_provisioner_on_remote() {
    ssh "${SSH_OPTS[@]}" -p "${SSH_PORT}" "${SSH_USER}@${SSH_HOST}" bash -s "${SSH_USER}" "${SSH_USER_AFTER}" "${SSH_PORT}" "${SSH_PORT_AFTER}" <<'REMOTE'
set -euo pipefail

OLD_USER="$1"
NEW_USER="$2"
OLD_PORT="$3"
NEW_PORT="$4"
SSHD_CONFIG_PATH="/etc/ssh/sshd_config"

as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo -n "$@"
    fi
}

has_command() {
    command -v "$1" >/dev/null 2>&1
}

find_sshd_binary() {
    local detected path
    local candidates=("/usr/sbin/sshd" "/usr/local/sbin/sshd" "/usr/bin/sshd")

    detected="$(command -v sshd 2>/dev/null || true)"
    [ -n "$detected" ] && candidates+=("$detected")

    for path in "${candidates[@]}"; do
        if [ -x "$path" ]; then
            echo "$path"
            return
        fi
    done

    echo "ERROR: could not find sshd binary for config validation." >&2
    return 1
}

systemd_property() {
    local unit="$1" property="$2"
    as_root systemctl show "$unit" --property="$property" --value 2>/dev/null || true
}

systemd_unit_is_loaded() {
    local unit="$1" load_state unit_file_state
    load_state="$(systemd_property "$unit" LoadState)"
    unit_file_state="$(systemd_property "$unit" UnitFileState)"

    if [[ "$load_state" == "masked" || "$unit_file_state" == masked* ]]; then
        echo "${unit} is masked; skipping it."
        return 1
    fi

    if [ "$load_state" != "loaded" ]; then
        return 1
    fi

    return 0
}

select_ssh_service_unit() {
    local active_candidate="" enabled_candidate="" loaded_candidate=""
    local active_state load_state unit unit_file_state

    for unit in ssh.service sshd.service; do
        load_state="$(systemd_property "$unit" LoadState)"
        unit_file_state="$(systemd_property "$unit" UnitFileState)"
        active_state="$(systemd_property "$unit" ActiveState)"

        if [[ "$load_state" == "masked" || "$unit_file_state" == masked* ]]; then
            echo "${unit} is masked; skipping it." >&2
            continue
        fi

        [ "$load_state" = "loaded" ] || continue

        echo "Detected ${unit}: active=${active_state:-unknown}, enabled=${unit_file_state:-unknown}." >&2
        loaded_candidate="${loaded_candidate:-$unit}"

        if [ "$active_state" = "active" ]; then
            active_candidate="${active_candidate:-$unit}"
        fi

        if [[ "$unit_file_state" == enabled* ]]; then
            enabled_candidate="${enabled_candidate:-$unit}"
        fi
    done

    echo "${active_candidate:-${enabled_candidate:-$loaded_candidate}}"
}

select_ssh_socket_unit() {
    local preferred_state="$1"
    local log_probe="${2:-0}"
    local active_state candidate="" load_state unit unit_file_state

    for unit in ssh.socket sshd.socket; do
        load_state="$(systemd_property "$unit" LoadState)"
        unit_file_state="$(systemd_property "$unit" UnitFileState)"
        active_state="$(systemd_property "$unit" ActiveState)"

        if [[ "$load_state" == "masked" || "$unit_file_state" == masked* ]]; then
            [ "$log_probe" = "1" ] && echo "${unit} is masked; skipping it." >&2
            continue
        fi

        [ "$load_state" = "loaded" ] || continue

        [ "$log_probe" = "1" ] && echo "Detected ${unit}: active=${active_state:-unknown}, enabled=${unit_file_state:-unknown}." >&2

        case "$preferred_state" in
            active)
                [ "$active_state" = "active" ] && candidate="${candidate:-$unit}"
                ;;
            enabled)
                [[ "$unit_file_state" == enabled* ]] && candidate="${candidate:-$unit}"
                ;;
        esac
    done

    echo "$candidate"
}

configure_ssh_socket_port() {
    local port="$1" unit="$2"

    if ! systemd_unit_is_loaded "$unit"; then
        return
    fi

    echo "Configuring ${unit} for ${port}..."
    as_root mkdir -p "/etc/systemd/system/${unit}.d"
    printf '[Socket]\nListenStream=\nListenStream=%s\n' "$port" | as_root tee "/etc/systemd/system/${unit}.d/listen.conf" >/dev/null
    as_root systemctl daemon-reload
}

restart_systemd_unit() {
    local unit="$1"

    echo "Restarting ${unit}..."
    as_root systemctl restart "$unit"
    as_root systemctl is-active --quiet "$unit"
}

restart_ssh_with_systemd() {
    local active_socket_unit enabled_socket_unit port service_unit
    port="$1"
    active_socket_unit="$(select_ssh_socket_unit active 1)"
    enabled_socket_unit="$(select_ssh_socket_unit enabled)"
    service_unit="$(select_ssh_service_unit)"

    if [ -n "$active_socket_unit" ]; then
        echo "Applying SSH changes through active socket unit ${active_socket_unit}."
        configure_ssh_socket_port "$port" "$active_socket_unit"
        restart_systemd_unit "$active_socket_unit"
        return 0
    fi

    if [ -n "$enabled_socket_unit" ]; then
        echo "Configuring enabled socket unit ${enabled_socket_unit} for the next socket-managed start."
        configure_ssh_socket_port "$port" "$enabled_socket_unit"
    fi

    if [ -n "$service_unit" ]; then
        echo "Applying SSH changes through service unit ${service_unit}."
        restart_systemd_unit "$service_unit"
        return 0
    fi

    if [ -n "$enabled_socket_unit" ]; then
        echo "Applying SSH changes through enabled socket unit ${enabled_socket_unit}."
        restart_systemd_unit "$enabled_socket_unit"
        return 0
    fi

    echo "ERROR: could not find a manageable SSH systemd service or socket unit." >&2
    return 1
}

restart_ssh_with_service_command() {
    local service_name

    for service_name in ssh sshd; do
        if [ -x "/etc/init.d/${service_name}" ]; then
            echo "Applying SSH changes through service command ${service_name}."
            as_root service "$service_name" restart
            return
        fi
    done

    echo "ERROR: could not find systemctl or a legacy SSH service command." >&2
    return 1
}

set_sshd_config_port() {
    local port="$1"

    if as_root grep -Eq '^[#[:space:]]*Port[[:space:]]+' "$SSHD_CONFIG_PATH"; then
        as_root sed -i -E "s/^[#[:space:]]*Port[[:space:]]+.*/Port ${port}/" "$SSHD_CONFIG_PATH"
    else
        printf '\nPort %s\n' "$port" | as_root tee -a "$SSHD_CONFIG_PATH" >/dev/null
    fi
}

validate_sshd_config() {
    local sshd_binary
    sshd_binary="$(find_sshd_binary)"
    as_root "$sshd_binary" -t -f "$SSHD_CONFIG_PATH"
}

restart_ssh() {
    local port="$1"

    if has_command systemctl; then
        restart_ssh_with_systemd "$port"
    else
        restart_ssh_with_service_command
    fi
}

if { [ "$OLD_USER" != "$NEW_USER" ] || [ "$OLD_PORT" != "$NEW_PORT" ]; } && [ "$(id -u)" -ne 0 ] && ! sudo -n true 2>/dev/null; then
    echo "ERROR: SSH user $(id -un) must have passwordless sudo before bootstrap can continue." >&2
    echo "Fix on remote: echo '$(id -un) ALL=(ALL:ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/$(id -un) && sudo chmod 440 /etc/sudoers.d/$(id -un)" >&2
    exit 1
fi

if [ "$OLD_USER" != "$NEW_USER" ]; then
    echo "Creating user ${NEW_USER}..."
    id "$NEW_USER" &>/dev/null || as_root useradd -m -s /bin/bash "$NEW_USER"

    as_root mkdir -p "/home/$NEW_USER/.ssh"
    as_root tee "/home/$NEW_USER/.ssh/authorized_keys" >/dev/null < "$HOME/.ssh/authorized_keys"
    as_root chown -R "$NEW_USER:$NEW_USER" "/home/$NEW_USER/.ssh"
    as_root chmod 700 "/home/$NEW_USER/.ssh"
    as_root chmod 600 "/home/$NEW_USER/.ssh/authorized_keys"

    echo "$NEW_USER ALL=(ALL:ALL) NOPASSWD:ALL" | as_root tee "/etc/sudoers.d/$NEW_USER" >/dev/null
    as_root chmod 440 "/etc/sudoers.d/$NEW_USER"
else
    echo "SSH user is unchanged (${OLD_USER}); skipping user creation."
fi

if [ "$OLD_PORT" != "$NEW_PORT" ]; then
    echo "Ensuring that new SSH port is open in UFW..."
    as_root ufw allow "${NEW_PORT}/tcp" || true

    echo "Ensuring that old SSH port is open in UFW..."
    as_root ufw allow "${OLD_PORT}/tcp" || true

    echo "Ensuring SSH is configured for ${NEW_PORT}..."
    set_sshd_config_port "$NEW_PORT"
    validate_sshd_config
    restart_ssh "$NEW_PORT"
else
    echo "SSH port is unchanged (${OLD_PORT}); skipping SSH port update."
fi
REMOTE
}

remove_old_ssh_port_on_remote() {
    if [ "${SSH_PORT}" = "${SSH_PORT_AFTER}" ]; then
        return
    fi

    ssh "${SSH_OPTS[@]}" -p "${SSH_PORT_AFTER}" "${SSH_USER_AFTER}@${SSH_HOST}" bash -s "${SSH_PORT}" <<'REMOTE'
set -euo pipefail

OLD_PORT="$1"

as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo -n "$@"
    fi
}

echo "Removing old SSH port from UFW..."
as_root ufw delete allow "${OLD_PORT}/tcp" || true
REMOTE
}

update_inventory() {
    export JMP_HOST JMP_PORT JMP_USER
    uv run python - "${INVENTORY_PATH}" "${NEW_HOSTNAME}" "${SSH_HOST}" "${SSH_PORT_AFTER}" "${SSH_USER_AFTER}" "${REALM}" "${PLATFORM}" "${CLUSTER}" <<'PY'
import pathlib
import sys
import yaml
import os

path = pathlib.Path(sys.argv[1])
hostname, ssh_host, ssh_port, ssh_user_after = sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5]
realm, platform, cluster = sys.argv[6], sys.argv[7], sys.argv[8]
jmp_host = os.environ.get("JMP_HOST", "")
jmp_port = os.environ.get("JMP_PORT", "")
jmp_user = os.environ.get("JMP_USER", "")

txt = path.read_text() if path.exists() else ""
data = yaml.safe_load(txt) if txt.strip() else {}

def get_cluster_node(node, cluster_name):
    if not isinstance(node, dict): return None
    if "children" in node and isinstance(node["children"], dict):
        for k, v in node["children"].items():
            if k.endswith(f"_{cluster_name}") and isinstance(v, dict):
                return v
            res = get_cluster_node(v, cluster_name)
            if res: return res
    return None

if not data:
    data = {"all": {"children": {realm: {"children": {f"{realm}_{platform}": {"vars": {"iv_platform": platform}, "children": {f"{realm}_{platform}_{cluster}": {}}}}}}}}

cluster_node = get_cluster_node(data.get("all", {}), cluster)
if not cluster_node:
    all_children = data.setdefault("all", {}).setdefault("children", {})
    realm_node = all_children.setdefault(realm, {})
    realm_children = realm_node.setdefault("children", {})
    platform_node = realm_children.setdefault(f"{realm}_{platform}", {})
    platform_vars = platform_node.setdefault("vars", {})
    platform_vars.setdefault("iv_platform", platform)
    platform_children = platform_node.setdefault("children", {})
    cluster_node = platform_children.setdefault(f"{realm}_{platform}_{cluster}", {})

hosts = cluster_node.setdefault("hosts", {})
host_entry = hosts.setdefault(hostname, {})
host_entry["iv_ssh_host"] = ssh_host
host_entry["iv_ssh_port"] = ssh_port
if ssh_user_after != "iac":
    host_entry["gv_ansible_ssh_user"] = ssh_user_after

if jmp_host:
    vars_node = cluster_node.setdefault("vars", {})
    vars_node["iv_jmp_host"] = jmp_host
    if jmp_port: vars_node["iv_jmp_port"] = int(jmp_port) if jmp_port.isdigit() else jmp_port
    if jmp_user: vars_node["iv_jmp_user"] = jmp_user

out = yaml.safe_dump(data, sort_keys=False, default_flow_style=False, explicit_start=True)
path.write_text(out.replace("---\n", "---\n\n", 1), encoding="utf-8")
PY
}

main() {
    if [ "$#" -ne 3 ]; then
        echo "Usage: $0 <realm> <platform> <cluster>"
        echo "Example: $0 prd ycl bal"
        exit 1
    fi

    REALM="$1"
    PLATFORM="$2"
    CLUSTER="$3"

    INVENTORY_PATH="${PROJECT_ROOT}/inventories/${CLUSTER}/${REALM}.yml"
    mkdir -p "$(dirname "${INVENTORY_PATH}")"

    SSH_HOST="${SSH_HOST:-$(prompt "SSH Host" "")}"
    SSH_PORT="${SSH_PORT:-$(prompt "SSH Port" "22")}"
    SSH_USER="${SSH_USER:-$(prompt "SSH User" "root")}"
    NEW_HOSTNAME="${NEW_HOSTNAME:-$(prompt "New Hostname" "${REALM}-${PLATFORM}-${CLUSTER}01")}"
    SSH_PORT_AFTER="${SSH_PORT_AFTER:-$(prompt "SSH Port After" "${SSH_PORT}")}"
    SSH_USER_AFTER="${SSH_USER_AFTER:-$(prompt "SSH User After" "iac")}"

    if [ -n "${JMP_HOST:-}" ]; then
        JMP_PORT="${JMP_PORT:-22}"
        JMP_USER="${JMP_USER:-bastion}"
        SSH_OPTS+=("-o" "ProxyJump=${JMP_USER}@${JMP_HOST}:${JMP_PORT}")
        echo "Will use jump host ${JMP_USER}@${JMP_HOST}:${JMP_PORT} for connection"
    fi

    copy_ssh_key
    if [ "${SSH_PORT}" != "${SSH_PORT_AFTER}" ]; then
        echo "Will change SSH port from ${SSH_PORT} to ${SSH_PORT_AFTER}"
    fi
    setup_provisioner_on_remote

    if ! ssh "${SSH_OPTS[@]}" -p "${SSH_PORT_AFTER}" "${SSH_USER_AFTER}@${SSH_HOST}" true 2>/dev/null; then
        echo "ERROR: could not connect to ${SSH_HOST}:${SSH_PORT_AFTER} as ${SSH_USER_AFTER}"
        exit 1
    fi

    remove_old_ssh_port_on_remote
    update_inventory

    echo "Upserted ${NEW_HOSTNAME} in ${INVENTORY_PATH} (iv_ssh_port=${SSH_PORT_AFTER})"
}

main "$@"
