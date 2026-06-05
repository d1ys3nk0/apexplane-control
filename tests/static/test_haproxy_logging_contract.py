from __future__ import annotations

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
HAPROXY_ALB_DIR = REPO_ROOT / "roles" / "haproxy_alb"
FE_WEB_TEMPLATE = HAPROXY_ALB_DIR / "templates" / "haproxy" / "fe_web.cfg.j2"
MAIN_TEMPLATE = HAPROXY_ALB_DIR / "templates" / "haproxy" / "haproxy.cfg.j2"


def test_haproxy_alb_traffic_logs_use_structured_loki_fields() -> None:
    template = FE_WEB_TEMPLATE.read_text(encoding="utf-8")

    expected_fields = (
        "id=%ID",
        "ts=%tr",
        "host=%{+Q}[var(txn.host)]",
        "method=%HM",
        "path=%{+Q}HP",
        "proto=%HV",
        "status=%ST",
        "bytes=%B",
        "client_ip=%ci",
        "client_port=%cp",
        "peer_ip=%[var(txn.peer_ip)]",
        "frontend=%ft",
        "backend=%b",
        "server=%s",
        "term=%tsc",
        "timing=%TR/%Tw/%Tc/%Tr/%Ta",
        "conn=%ac/%fc/%bc/%sc/%rc",
        "queue=%sq/%bq",
        "ssl=%[ssl_fc]",
        "sni=%{+Q}[ssl_fc_sni]",
        "tls=%{+Q}[ssl_fc_protocol]",
        "alpn=%{+Q}[ssl_fc_alpn]",
    )

    for field in expected_fields:
        assert field in template

    assert "q=%{+Q}r" not in template
    assert "%HQ" not in template
    assert "req.hdr(host)" not in template.partition("log-format ")[2].partition("\n")[0]
    assert "http-request set-var(txn.host) req.hdr(host)" in template
    assert "http-request set-var(txn.peer_ip) src" in template


def test_haproxy_alb_internal_endpoints_do_not_emit_traffic_logs() -> None:
    frontend_template = FE_WEB_TEMPLATE.read_text(encoding="utf-8")
    main_template = MAIN_TEMPLATE.read_text(encoding="utf-8")

    assert "http-request set-log-level silent if { path /_health }" in frontend_template
    assert "http-request set-log-level silent if { path /_stats }" in main_template
    assert "http-request set-log-level silent if { path /metrics }" in main_template


def test_haproxy_alb_crowdsec_inspects_requests_before_redirects_and_auth() -> None:
    template = FE_WEB_TEMPLATE.read_text(encoding="utf-8")

    set_src_index = template.index("http-request set-src hdr_ip(X-Forwarded-For,-1)")
    crowdsec_index = template.index("http-request send-spoe-group crowdsec crowdsec-http-body")
    redirect_index = template.index("http-request redirect scheme https")
    auth_index = template.index("{{ auth_rule_line(auth_rule) }}")

    assert set_src_index < crowdsec_index
    assert crowdsec_index < redirect_index
    assert crowdsec_index < auth_index
