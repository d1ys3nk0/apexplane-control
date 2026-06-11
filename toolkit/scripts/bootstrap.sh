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

as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo -n "$@"
    fi
}

systemd_property() {
    local unit="$1" property="$2"
    as_root systemctl show "$unit" --property="$property" --value 2>/dev/null || true
}

ssh_socket_should_manage() {
    local active_state load_state unit_file_state
    load_state="$(systemd_property ssh.socket LoadState)"
    unit_file_state="$(systemd_property ssh.socket UnitFileState)"
    active_state="$(systemd_property ssh.socket ActiveState)"

    if [[ "$load_state" == "masked" || "$unit_file_state" == masked* ]]; then
        echo "SSH socket is masked; skipping ssh.socket configuration."
        return 1
    fi

    if [ "$load_state" != "loaded" ]; then
        echo "SSH socket is unavailable (${load_state:-unknown}); skipping ssh.socket configuration."
        return 1
    fi

    if [[ "$active_state" == "active" || "$unit_file_state" == enabled* ]]; then
        return 0
    fi

    echo "SSH socket is ${unit_file_state:-not enabled} and ${active_state:-not active}; skipping ssh.socket configuration."
    return 1
}

configure_ssh_socket_port() {
    local port="$1"

    if ! ssh_socket_should_manage; then
        return
    fi

    echo "Configuring ssh.socket for ${port}..."
    as_root mkdir -p /etc/systemd/system/ssh.socket.d
    printf '[Socket]\nListenStream=\nListenStream=%s\n' "$port" | as_root tee /etc/systemd/system/ssh.socket.d/listen.conf >/dev/null
    as_root systemctl daemon-reload
    as_root systemctl restart ssh.socket
}

set_sshd_config_port() {
    local port="$1"

    if as_root grep -Eq '^[#[:space:]]*Port[[:space:]]+' /etc/ssh/sshd_config; then
        as_root sed -i -E "s/^[#[:space:]]*Port[[:space:]]+.*/Port ${port}/" /etc/ssh/sshd_config
    else
        printf '\nPort %s\n' "$port" | as_root tee -a /etc/ssh/sshd_config >/dev/null
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
    as_root /usr/sbin/sshd -t -f /etc/ssh/sshd_config
    configure_ssh_socket_port "$NEW_PORT"
    as_root systemctl restart ssh.service
    as_root systemctl is-active --quiet ssh.service
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
