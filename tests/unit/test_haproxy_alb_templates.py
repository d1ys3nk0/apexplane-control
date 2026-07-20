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
        "haproxy_alb_backend_group": "edge_nodes",
        "haproxy_alb_crowdsec_enabled": False,
        "haproxy_alb_default_target_group": "",
        "haproxy_alb_default_target_host": "",
        "haproxy_alb_prometheus_exporter_port": 8405,
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
        "haproxy_alb_tunnel_timeout": "1h",
        "haproxy_alb_stats_port": 8404,
        "haproxy_alb_userlists": {},
        "haproxy_alb_whitelists_enforced": [],
    }


def test_main_config_binds_statistics_listener_to_loopback() -> None:
    rendered = render_template("haproxy.cfg.j2", base_haproxy_alb_variables())
    lines = rendered.splitlines()

    assert "listen stats" in lines
    assert "  bind 127.0.0.1:8404" in lines
    assert "  bind :8404" not in lines


def test_fe_web_renders_header_updates_and_rewrites_on_separate_lines() -> None:
    rendered = render_template("fe_web.cfg.j2", base_haproxy_alb_variables())
    lines = rendered.splitlines()

    assert lines[0] == "frontend web"
    assert "\\n" not in rendered
    assert max_consecutive_blank_lines(rendered) <= 1
    assert "  monitor-uri /_health" not in lines
    assert "  monitor-uri /_haproxy/health" not in lines
    assert (
        '  http-request return status 200 content-type text/plain string "OK" if { path /_haproxy/health } || { path /_health }'
        in lines
    )
    assert not any(line.count("http-response ") > 1 for line in lines)
    assert not any(line.count("http-request replace-header ") > 1 for line in lines)
    assert "  http-response del-header X-Frame-Options if { var(txn.route) -m str docs }" in lines
    assert (
        "  http-response set-header Content-Security-Policy \"frame-ancestors 'self' https://*.example.test\" "
        "if { var(txn.route) -m str docs }"
    ) in lines
    assert "  http-request replace-header X-Forwarded-Proto ^.*$ https if host_docs" in lines
    assert "  http-request replace-header X-Service-Name ^.*$ docs if host_docs" in lines


def test_fe_web_renders_generated_request_id_headers() -> None:
    rendered = render_template("fe_web.cfg.j2", base_haproxy_alb_variables())
    lines = rendered.splitlines()

    assert "  unique-id-format %[uuid()]" in lines
    assert "  unique-id-header X-Request-ID" in lines
    assert "  unique-id-header X-Unique-ID" not in lines
    assert "  http-request set-header X-Request-ID %[unique-id]" not in lines


def test_fe_web_renders_userlist_skip_origins_auth_bypass() -> None:
    variables = base_haproxy_alb_variables()
    variables["haproxy_alb_routes"][1]["userlist"] = "docs_users"
    variables["haproxy_alb_routes"][1]["userlist_skip_origins"] = [
        "https://app.example.test",
        "https://*.parent.example.test",
    ]

    rendered = render_template("fe_web.cfg.j2", variables)
    lines = rendered.splitlines()

    assert "  acl userlist_origin_iframe_1 req.hdr(Sec-Fetch-Dest) -i iframe" in lines
    assert "  acl userlist_origin_subresource_1 req.hdr(Sec-Fetch-Site) -i same-origin" in lines
    assert "  acl userlist_origin_subresource_dest_1 req.hdr(Sec-Fetch-Dest) -i empty script style image font" in lines
    assert "  acl userlist_origin_parent_1 req.hdr(Referer) -m beg https://app.example.test/" in lines
    assert (
        "  acl userlist_origin_parent_1 req.hdr(Referer) -m reg ^https://[^/][^/]*[.]parent[.]example[.]test(/|$)"
    ) in lines
    assert (
        "  http-request set-var(txn.userlist_origin_skip_1) str(true) if host_docs "
        "userlist_origin_iframe_1 userlist_origin_parent_1"
    ) in lines
    assert (
        "  http-request set-var(txn.userlist_origin_skip_1) str(true) if host_docs "
        "userlist_origin_subresource_1 userlist_origin_subresource_dest_1"
    ) in lines
    assert (
        "  http-request auth realm infra if !is_acme host_docs "
        "!{ http_auth(docs_users) } !{ var(txn.userlist_origin_skip_1) -m str true }"
    ) in lines


def test_fe_web_renders_userlist_skip_cidrs_auth_bypass() -> None:
    variables = base_haproxy_alb_variables()
    variables["haproxy_alb_routes"][1]["userlist"] = "docs_users"
    variables["haproxy_alb_routes"][1]["userlist_skip_cidrs"] = ["10.1.0.0/16", "192.0.2.0/24"]

    rendered = render_template("fe_web.cfg.j2", variables)
    lines = rendered.splitlines()

    assert (
        "  http-request auth realm infra if !is_acme host_docs "
        "!{ src -m ip 10.1.0.0/16 192.0.2.0/24 } !{ http_auth(docs_users) }"
    ) in lines


def test_fe_web_renders_userlist_skip_prefixes_and_headers_auth_bypass() -> None:
    variables = base_haproxy_alb_variables()
    variables["haproxy_alb_routes"][1]["userlist"] = "docs_users"
    variables["haproxy_alb_routes"][1]["userlist_skip_headers"] = {"X-API-Key": "secret"}
    variables["haproxy_alb_routes"][1]["userlist_skip_prefixes"] = ["/api/", "/health"]

    rendered = render_template("fe_web.cfg.j2", variables)
    lines = rendered.splitlines()

    assert (
        "  http-request auth realm infra if !is_acme host_docs !{ hdr(X-API-Key) -m str secret } "
        "!{ path_beg /api/ } !{ path_beg /health } !{ http_auth(docs_users) }"
    ) in lines


def test_fe_web_renders_route_restricted_cidr_deny_after_source_rewrite() -> None:
    variables = base_haproxy_alb_variables()
    variables["haproxy_alb_trusted_proxy_cidrs"] = ["10.0.0.0/8"]
    variables["haproxy_alb_routes"][0]["restricted_cidrs"] = ["10.1.0.0/16", "192.0.2.0/24"]

    rendered = render_template("fe_web.cfg.j2", variables)
    lines = rendered.splitlines()
    deny_line = "  http-request deny deny_status 403 if !is_acme host_alpha !{ src -m ip 10.1.0.0/16 192.0.2.0/24 }"

    assert deny_line in lines
    assert not any("host_docs !{ src -m ip" in line for line in lines)
    assert not any("host_edge !{ src -m ip" in line for line in lines)
    source_rewrite_line = (
        "  http-request set-src hdr_ip(X-Forwarded-For,-1) if from_trusted_proxy "
        "{ hdr_ip(X-Forwarded-For,-1) -m found }"
    )
    assert lines.index(source_rewrite_line) < lines.index(deny_line)
    assert lines.index(deny_line) < lines.index("  use_backend alpha if host_alpha")


def test_fe_web_renders_route_restricted_cidr_skip_prefixes() -> None:
    variables = base_haproxy_alb_variables()
    variables["haproxy_alb_routes"][0]["restricted_cidrs"] = ["10.1.0.0/16"]
    variables["haproxy_alb_routes"][0]["restricted_skip_prefixes"] = ["/api/", "/health"]

    rendered = render_template("fe_web.cfg.j2", variables)
    lines = rendered.splitlines()

    assert (
        "  http-request deny deny_status 403 if !is_acme host_alpha !{ src -m ip 10.1.0.0/16 } "
        "!{ path_beg /api/ } !{ path_beg /health }"
    ) in lines


def test_fe_web_renders_more_specific_route_access_exclusion() -> None:
    variables = base_haproxy_alb_variables()
    variables["haproxy_alb_routes"][0]["restricted_cidrs"] = ["10.1.0.0/16"]
    variables["haproxy_alb_routes"].append(
        {
            "domain": "alpha.example.test",
            "name": "alpha_api",
            "prefix": "/api/",
            "target_host": "10.0.0.10",
            "target_port": 8080,
        }
    )

    rendered = render_template("fe_web.cfg.j2", variables)
    lines = rendered.splitlines()

    assert (
        "  http-request deny deny_status 403 if !is_acme host_alpha !{ path_beg /api/ } !{ src -m ip 10.1.0.0/16 }"
    ) in lines


def test_be_local_renders_each_backend_and_server_on_separate_lines() -> None:
    rendered = render_template("be_local.cfg.j2", base_haproxy_alb_variables())
    lines = rendered.splitlines()

    assert "\\n" not in rendered.replace("\\r\\n", "")
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
