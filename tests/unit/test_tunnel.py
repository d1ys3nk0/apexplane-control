from __future__ import annotations

import importlib.util
import socket
import subprocess
from pathlib import Path
from typing import TYPE_CHECKING

import pytest


if TYPE_CHECKING:
    from types import ModuleType


REPO_ROOT = Path(__file__).resolve().parents[2]
TUNNEL_SCRIPT = REPO_ROOT / "toolkit" / "scripts" / "tunnel.py"


def load_tunnel_module() -> ModuleType:
    spec = importlib.util.spec_from_file_location("apexplane_tunnel", TUNNEL_SCRIPT)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_selector_expands_two_digit_index_and_preserves_exact_hostname() -> None:
    tunnel = load_tunnel_module()

    assert tunnel.selected_hostname("01", "prd", "ycl", "app") == "prd-ycl-app01"
    assert tunnel.selected_hostname("prd-ycl-app02", "prd", "ycl", "app") == "prd-ycl-app02"

    with pytest.raises(tunnel.TunnelError, match="two-digit index"):
        tunnel.selected_hostname("1", "prd", "ycl", "app")


def test_inventory_hosts_returns_only_structured_host_variables() -> None:
    tunnel = load_tunnel_module()

    hosts = tunnel.inventory_hosts(
        {
            "_meta": {
                "hostvars": {
                    "prd-ycl-app01": {"iv_ssh_host": "10.0.0.10"},
                    "invalid": "not-a-mapping",
                }
            }
        }
    )

    assert hosts == {"prd-ycl-app01": {"iv_ssh_host": "10.0.0.10"}}


def test_ssh_config_resolves_jump_users_and_keys() -> None:
    tunnel = load_tunnel_module()

    config = tunnel.ssh_config(
        hostname="prd-ycl-app01",
        address="10.0.0.10",
        port="32123",
        user="operator",
        key="/keys/operator",
        jump_host="203.0.113.10",
        jump_port="2222",
        jump_user="bastion",
        jump_key="/keys/bastion",
    )

    assert "HostName 10.0.0.10" in config
    assert "Port 32123" in config
    assert "User operator" in config
    assert "IdentityFile /keys/operator" in config
    assert "ProxyJump tunnel-jump" in config
    assert "HostName 203.0.113.10" in config
    assert "User bastion" in config
    assert "IdentityFile /keys/bastion" in config


def test_occupied_local_port_is_rejected() -> None:
    tunnel = load_tunnel_module()

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.bind(("127.0.0.1", 0))
        port = listener.getsockname()[1]
        with pytest.raises(tunnel.TunnelError, match="already occupied"):
            tunnel.assert_local_port_available(port)


def test_tunnel_command_uses_loopback_forward_failure_and_keepalives() -> None:
    tunnel = load_tunnel_module()

    command = tunnel.tunnel_command(Path("/private/config"), 1080, 1080)

    assert command == [
        "ssh",
        "-F",
        "/private/config",
        "-N",
        "-L",
        "127.0.0.1:1080:127.0.0.1:1080",
        "-o",
        "ExitOnForwardFailure=yes",
        "-o",
        "ServerAliveInterval=30",
        "-o",
        "ServerAliveCountMax=3",
        "tunnel-target",
    ]


def test_browser_helper_delegates_to_default_browser(monkeypatch: pytest.MonkeyPatch) -> None:
    tunnel = load_tunnel_module()
    opened: list[str] = []
    monkeypatch.setattr(tunnel.webbrowser, "open", lambda url: opened.append(url) or True)

    assert tunnel.open_browser("http://127.0.0.1:3000/") is True
    assert opened == ["http://127.0.0.1:3000/"]


def test_cleanup_terminates_then_kills_unresponsive_process() -> None:
    tunnel = load_tunnel_module()

    class Process:
        def __init__(self) -> None:
            self.events: list[str] = []
            self.running = True

        def poll(self) -> None:
            return None

        def terminate(self) -> None:
            self.events.append("terminate")

        def wait(self, timeout: int | None = None) -> int:
            self.events.append(f"wait:{timeout}")
            if timeout is not None:
                raise subprocess.TimeoutExpired("ssh", timeout)
            self.running = False
            return 0

        def kill(self) -> None:
            self.events.append("kill")

    process = Process()
    tunnel.terminate_process(process)

    assert process.events == ["terminate", "wait:5", "kill", "wait:None"]
