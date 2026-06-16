from __future__ import annotations

from pathlib import Path
from typing import Any

from ansible.parsing.dataloader import DataLoader
from ansible.template import Templar


REPO_ROOT = Path(__file__).resolve().parents[2]
HAPROXY_ALB_TEMPLATE_DIR = REPO_ROOT / "roles" / "haproxy_alb" / "templates" / "haproxy"


def render_template(template_name: str, variables: dict[str, Any]) -> str:
    rendered = Templar(loader=DataLoader(), variables=variables).template(
        HAPROXY_ALB_TEMPLATE_DIR.joinpath(template_name).read_text(encoding="utf-8")
    )
    assert isinstance(rendered, str)
    return rendered


def max_consecutive_blank_lines(rendered: str) -> int:
    max_run = 0
    current_run = 0

    for line in rendered.splitlines():
        if line == "":
            current_run += 1
            max_run = max(max_run, current_run)
        else:
            current_run = 0

    return max_run


def base_haproxy_alb_variables() -> dict[str, Any]:
    return {
        "haproxy_alb_acme_enabled": False,
        "haproxy_alb_auth": [],
        "haproxy_alb_auth_whitelist_cidrs": [],
        "haproxy_alb_backend_group": "edge_nodes",
        "haproxy_alb_crowdsec_enabled": False,
        "haproxy_alb_default_target_group": "",
        "haproxy_alb_default_target_host": "",
        "haproxy_alb_redirect_all_http": False,
        "haproxy_alb_routes": [
            {
                "domain": "alpha.example.test",
                "name": "alpha",
                "target_host": "10.0.0.10",
                "target_port": 8080,
            },
            {
                "domain": "docs.example.test",
                "name": "docs",
                "request_header_rewrites": [
                    {"name": "X-Forwarded-Proto", "pattern": "^.*$", "replacement": "https"},
                    {"name": "X-Service-Name", "pattern": "^.*$", "replacement": "docs"},
                ],
                "response_header_deletes": ["X-Frame-Options"],
                "response_headers": {"Content-Security-Policy": "frame-ancestors 'self' https://*.example.test"},
                "target_host": "10.0.0.20",
                "target_port": 8080,
            },
            {
                "backend_proto": "h2",
                "domain": "edge.example.test",
                "name": "edge",
                "target_group": "edge_nodes",
                "target_port": 9090,
            },
        ],
        "haproxy_alb_target_groups": {
            "edge_nodes": {
                "edge01": "10.0.1.10",
                "edge02": "10.0.1.20",
            },
        },
        "haproxy_alb_throttle_deny_status": 429,
        "haproxy_alb_throttles": [],
        "haproxy_alb_trusted_proxy_cidrs": [],
        "haproxy_alb_whitelists_enforced": [],
    }


def test_fe_web_renders_header_updates_and_rewrites_on_separate_lines() -> None:
    rendered = render_template("fe_web.cfg.j2", base_haproxy_alb_variables())
    lines = rendered.splitlines()

    assert lines[0] == "frontend web"
    assert "\\n" not in rendered
    assert max_consecutive_blank_lines(rendered) <= 1
    assert not any(line.count("http-response ") > 1 for line in lines)
    assert not any(line.count("http-request replace-header ") > 1 for line in lines)
    assert "  http-response del-header X-Frame-Options if { var(txn.route) -m str docs }" in lines
    assert (
        "  http-response set-header Content-Security-Policy \"frame-ancestors 'self' https://*.example.test\" "
        "if { var(txn.route) -m str docs }"
    ) in lines
    assert "  http-request replace-header X-Forwarded-Proto ^.*$ https if host_docs" in lines
    assert "  http-request replace-header X-Service-Name ^.*$ docs if host_docs" in lines


def test_be_local_renders_each_backend_and_server_on_separate_lines() -> None:
    rendered = render_template("be_local.cfg.j2", base_haproxy_alb_variables())
    lines = rendered.splitlines()

    assert "\\n" not in rendered
    assert max_consecutive_blank_lines(rendered) <= 1
    assert not any("backend " in line and "server " in line for line in lines)
    assert not any(line.count("  server ") > 1 for line in lines)
    assert [line for line in lines if line.startswith("backend ")] == ["backend alpha", "backend docs"]
    assert [line for line in lines if line.strip().startswith("server ")] == [
        "  server 10.0.0.10:8080 10.0.0.10:8080 check inter 5s fall 2 rise 1",
        "  server 10.0.0.20:8080 10.0.0.20:8080 check inter 5s fall 2 rise 1",
    ]


def test_be_group_renders_group_servers_on_separate_lines() -> None:
    rendered = render_template("be_group.cfg.j2", base_haproxy_alb_variables())
    lines = rendered.splitlines()
    server_lines = [line for line in lines if line.strip().startswith("server ")]

    assert "\\n" not in rendered
    assert max_consecutive_blank_lines(rendered) <= 1
    assert not any("backend " in line and "server " in line for line in lines)
    assert not any(line.count("  server ") > 1 for line in lines)
    assert [line for line in lines if line.startswith("backend ")] == ["backend edge"]
    assert server_lines == [
        "  server edge01:9090 10.0.1.10:9090 check inter 5s fall 2 rise 1 proto h2",
        "  server edge02:9090 10.0.1.20:9090 check inter 5s fall 2 rise 1 proto h2",
    ]
