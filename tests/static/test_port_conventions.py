from __future__ import annotations

from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[2]
EXPECTED_OBSERVABILITY_PORTS = {
    "alloy_otlp_grpc_port": 4317,
    "alloy_otlp_http_port": 4318,
    "alloy_web_port": 12345,
    "docker_alertmanager_http_port": 9093,
    "docker_grafana_http_listen_port": 3000,
    "docker_jaeger_http_port": 16686,
    "docker_jaeger_otlp_grpc_port": 4319,
    "docker_jaeger_otlp_http_port": 4320,
    "docker_loki_grpc_listen_port": 3099,
    "docker_loki_http_listen_port": 3100,
    "docker_prometheus_http_port": 9090,
    "docker_tempo_grpc_port": 3199,
    "docker_tempo_http_port": 3200,
    "docker_tempo_otlp_grpc_port": 4315,
    "docker_tempo_otlp_http_port": 4316,
}
EXPECTED_APP_CLUSTER_PORTS = {
    "docker_swarm_dockhand_http_listen_port": 3000,
    "docker_swarm_dockhand_http_expose_port": 9999,
    "docker_swarm_pghero_public_port": 10000,
    "docker_swarm_postgres_exporter_public_port": 9187,
}
EXPECTED_EDGE_PORTS = {
    "haproxy_alb_stats_port": 8404,
    "haproxy_alb_prometheus_exporter_port": 8405,
}


def _defaults(role: str) -> dict[str, object]:
    path = REPO_ROOT / "roles" / role / "defaults" / "main.yml"
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def test_observability_port_defaults_match_shared_conventions() -> None:
    defaults = {
        **_defaults("alloy"),
        **_defaults("docker_alertmanager"),
        **_defaults("docker_grafana"),
        **_defaults("docker_jaeger"),
        **_defaults("docker_loki"),
        **_defaults("docker_prometheus"),
        **_defaults("docker_tempo"),
    }

    for port_name, expected_port in EXPECTED_OBSERVABILITY_PORTS.items():
        assert defaults[port_name] == expected_port


def test_app_cluster_port_defaults_match_shared_conventions() -> None:
    defaults = {
        **_defaults("docker_swarm_dockhand"),
        **_defaults("docker_swarm_pghero"),
        **_defaults("docker_swarm_postgres_exporter"),
    }

    for port_name, expected_port in EXPECTED_APP_CLUSTER_PORTS.items():
        assert defaults[port_name] == expected_port


def test_edge_port_defaults_match_shared_conventions() -> None:
    defaults = _defaults("haproxy_alb")

    for port_name, expected_port in EXPECTED_EDGE_PORTS.items():
        assert defaults[port_name] == expected_port
