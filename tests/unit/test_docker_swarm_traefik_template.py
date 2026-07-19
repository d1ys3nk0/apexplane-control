from __future__ import annotations

from collections.abc import Mapping
from pathlib import Path
from typing import Any, cast

import yaml
from ansible.parsing.dataloader import DataLoader
from ansible.template import Templar


REPO_ROOT = Path(__file__).resolve().parents[2]
TRAEFIK_ROLE_DIR = REPO_ROOT / "roles" / "docker_swarm_traefik"
TRAEFIK_STATIC_CONFIG_TEMPLATE = TRAEFIK_ROLE_DIR / "templates" / "traefik.yml.j2"


def load_traefik_defaults() -> dict[str, Any]:
    defaults = yaml.safe_load((TRAEFIK_ROLE_DIR / "defaults" / "main.yml").read_text(encoding="utf-8"))
    assert isinstance(defaults, dict)
    return cast("dict[str, Any]", defaults)


def render_static_config(overrides: Mapping[str, Any] | None = None) -> Mapping[str, Any]:
    variables = load_traefik_defaults()
    variables["docker_swarm_traefik_letsencrypt_enabled"] = False
    variables.update(overrides or {})

    rendered = Templar(loader=DataLoader(), variables=variables).template(
        TRAEFIK_STATIC_CONFIG_TEMPLATE.read_text(encoding="utf-8")
    )
    assert isinstance(rendered, str)

    static_config = yaml.safe_load(rendered)
    assert isinstance(static_config, Mapping)
    return cast("Mapping[str, Any]", static_config)


def test_static_config_keeps_request_id_header_in_json_access_logs() -> None:
    static_config = render_static_config()

    access_log = static_config["accessLog"]
    assert isinstance(access_log, Mapping)
    fields = access_log["fields"]
    assert isinstance(fields, Mapping)
    headers = fields["headers"]
    assert isinstance(headers, Mapping)

    assert access_log["format"] == "json"
    assert fields["defaultMode"] == "keep"
    assert headers["defaultMode"] == "drop"
    assert headers["names"] == {"X-Forwarded-For": "keep", "X-Request-ID": "keep"}


def test_static_config_trusts_configured_forwarded_header_sources() -> None:
    trusted_ips = [
        "10.0.0.0/8",
        "100.64.0.0/10",
        "127.0.0.0/8",
        "169.254.0.0/16",
        "172.16.0.0/12",
        "192.168.0.0/16",
    ]

    static_config = render_static_config({"docker_swarm_traefik_forwarded_headers_trusted_ips": trusted_ips})

    entry_points = static_config["entryPoints"]
    assert isinstance(entry_points, Mapping)

    for entrypoint_name in ("web", "websecure"):
        entrypoint = entry_points[entrypoint_name]
        assert isinstance(entrypoint, Mapping)
        forwarded_headers = entrypoint["forwardedHeaders"]
        assert isinstance(forwarded_headers, Mapping)
        assert forwarded_headers["trustedIPs"] == trusted_ips


def test_static_config_disables_insecure_automatic_api_router() -> None:
    static_config = render_static_config()

    api = static_config["api"]
    assert isinstance(api, Mapping)
    assert api == {"dashboard": True, "insecure": False}
