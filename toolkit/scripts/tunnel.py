#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import webbrowser
from pathlib import Path
from typing import Any
from urllib.parse import quote


HOST_INDEX_PATTERN = re.compile(r"^[0-9]{2}$")
HOSTNAME_PATTERN = re.compile(r"^[a-z0-9][a-z0-9-]*[a-z0-9]$")
MAX_PORT = 65535
SELECTOR_ARGUMENT_COUNT = 2
REQUIRED_ENV = (
    "TUNNEL_REALM",
    "TUNNEL_PLATFORM",
    "TUNNEL_CLUSTER",
    "TUNNEL_SERVICE",
    "TUNNEL_LOCAL_PORT",
    "TUNNEL_REMOTE_PORT",
    "TUNNEL_URL_PATH",
)


class TunnelError(RuntimeError):
    pass


def env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise TunnelError(f"{name} is required")
    return value


def inventory_data(path: Path) -> dict[str, Any]:
    command = ["uv", "run", "ansible-inventory", "-i", str(path), "--list"]
    result = subprocess.run(command, check=False, capture_output=True, text=True)  # noqa: S603
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise TunnelError(f"cannot read inventory {path}: {detail}")
    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise TunnelError(f"inventory {path} did not produce valid JSON") from error
    if not isinstance(data, dict):
        raise TunnelError(f"inventory {path} did not produce an object")
    return data


def inventory_hosts(data: dict[str, Any]) -> dict[str, dict[str, Any]]:
    hostvars = data.get("_meta", {}).get("hostvars", {})
    if not isinstance(hostvars, dict):
        raise TunnelError("inventory host variables are invalid")
    return {str(name): values for name, values in hostvars.items() if isinstance(values, dict)}


def selected_hostname(selector: str, realm: str, platform: str, cluster: str) -> str:
    if HOST_INDEX_PATTERN.fullmatch(selector):
        return f"{realm}-{platform}-{cluster}{selector}"
    if HOSTNAME_PATTERN.fullmatch(selector):
        return selector
    raise TunnelError("host selector must be a two-digit index or an exact inventory hostname")


def positive_port(name: str) -> int:
    value = env(name)
    try:
        port = int(value)
    except ValueError as error:
        raise TunnelError(f"{name} must be an integer") from error
    if not 1 <= port <= MAX_PORT:
        raise TunnelError(f"{name} must be between 1 and {MAX_PORT}")
    return port


def host_value(hostvars: dict[str, Any], *names: str, default: str = "") -> str:
    for name in names:
        value = hostvars.get(name)
        if value is not None and str(value).strip():
            return str(value).strip()
    return default


def assert_local_port_available(port: int) -> None:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 0)
        try:
            listener.bind(("127.0.0.1", port))
        except OSError as error:
            raise TunnelError(f"local port 127.0.0.1:{port} is already occupied") from error


def wait_until_ready(process: subprocess.Popen[bytes], port: int, timeout: float = 15.0) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        status = process.poll()
        if status is not None:
            raise TunnelError(f"SSH tunnel exited before readiness with status {status}")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.25):
                return
        except OSError:
            time.sleep(0.1)
    raise TunnelError(f"SSH local forward did not become ready on 127.0.0.1:{port}")


def ssh_config(
    hostname: str,
    address: str,
    port: str,
    user: str,
    key: str,
    jump_host: str,
    jump_port: str,
    jump_user: str,
    jump_key: str,
) -> str:
    lines = [
        "Host tunnel-target",
        f"  HostName {address}",
        f"  Port {port}",
        f"  User {user}",
        "  IdentitiesOnly yes",
    ]
    if key:
        lines.append(f"  IdentityFile {key}")
    if jump_host:
        lines.append("  ProxyJump tunnel-jump")
    lines.extend(
        [
            "",
            "Host tunnel-jump",
            f"  HostName {jump_host or hostname}",
            f"  Port {jump_port or '22'}",
            f"  User {jump_user or user}",
            "  IdentitiesOnly yes",
        ]
    )
    if jump_key:
        lines.append(f"  IdentityFile {jump_key}")
    return "\n".join(lines) + "\n"


def tunnel_command(config_path: Path, local_port: int, remote_port: int) -> list[str]:
    return [
        "ssh",
        "-F",
        str(config_path),
        "-N",
        "-L",
        f"127.0.0.1:{local_port}:127.0.0.1:{remote_port}",
        "-o",
        "ExitOnForwardFailure=yes",
        "-o",
        "ServerAliveInterval=30",
        "-o",
        "ServerAliveCountMax=3",
        "tunnel-target",
    ]


def open_browser(url: str) -> bool:
    return webbrowser.open(url)


def terminate_process(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()


def run() -> int:
    for name in REQUIRED_ENV:
        env(name)
    if len(sys.argv) != SELECTOR_ARGUMENT_COUNT:
        raise TunnelError("provide exactly one host selector after --")

    realm = env("TUNNEL_REALM")
    platform = env("TUNNEL_PLATFORM")
    cluster = env("TUNNEL_CLUSTER")
    service = env("TUNNEL_SERVICE")
    local_port = positive_port("TUNNEL_LOCAL_PORT")
    remote_port = positive_port("TUNNEL_REMOTE_PORT")
    url_path = env("TUNNEL_URL_PATH")
    inventory_path = Path("inventories") / cluster / f"{realm}.yml"
    if not inventory_path.is_file():
        raise TunnelError(f"service {service} is unavailable: inventory {inventory_path} does not exist")

    hostname = selected_hostname(sys.argv[1], realm, platform, cluster)
    hosts = inventory_hosts(inventory_data(inventory_path))
    if hostname not in hosts:
        raise TunnelError(f"host {hostname} is not a member of {inventory_path}")
    values = hosts[hostname]
    inventory_platform = host_value(values, "iv_platform")
    if inventory_platform and inventory_platform != platform:
        raise TunnelError(f"host {hostname} belongs to platform {inventory_platform}, not {platform}")

    address = host_value(values, "ansible_host", "iv_ssh_host", default=hostname)
    port = host_value(values, "ansible_port", "iv_ssh_port", default="22")
    user = host_value(values, "ansible_user", default=os.environ.get("ANSIBLE_SSH_USER", ""))
    key = host_value(values, "ansible_ssh_private_key_file", default=os.environ.get("ANSIBLE_SSH_KEY_PATH", ""))
    jump_host = host_value(values, "iv_jmp_host")
    jump_port = host_value(values, "iv_jmp_port", default="22" if jump_host else "")
    jump_user = os.environ.get("ANSIBLE_JMP_USER", "").strip()
    jump_key = os.environ.get("ANSIBLE_JMP_KEY_PATH", "").strip()
    if not user:
        raise TunnelError("SSH user is missing; set ANSIBLE_SSH_USER or ansible_user")
    if jump_host and not jump_user:
        raise TunnelError("jump host is configured but ANSIBLE_JMP_USER is missing")
    if not shutil.which("ssh"):
        raise TunnelError("ssh executable is not available")

    assert_local_port_available(local_port)
    url = f"http://127.0.0.1:{local_port}{quote(url_path, safe='/%;=?&')}"
    config = ssh_config(hostname, address, port, user, key, jump_host, jump_port, jump_user, jump_key)
    with tempfile.TemporaryDirectory(prefix="apexplane-tunnel-") as directory:
        config_path = Path(directory) / "ssh_config"
        config_path.write_text(config, encoding="utf-8")
        config_path.chmod(0o600)
        command = tunnel_command(config_path, local_port, remote_port)
        sys.stdout.write(f"Opening {service} on {hostname}: {url}\n")
        sys.stdout.flush()
        process = subprocess.Popen(command)  # noqa: S603

        def stop(_signum: int, _frame: object) -> None:
            terminate_process(process)

        signal.signal(signal.SIGINT, stop)
        signal.signal(signal.SIGTERM, stop)
        try:
            wait_until_ready(process, local_port)
            if not open_browser(url):
                sys.stderr.write(f"Browser could not be opened automatically. Open {url}\n")
            return process.wait()
        finally:
            terminate_process(process)


if __name__ == "__main__":
    try:
        raise SystemExit(run())
    except TunnelError as error:
        sys.stderr.write(f"Error: {error}\n")
        raise SystemExit(2) from error
