# Shared Role Port Conventions

This document records stable listener and published ports exposed by shared roles. It does not list client, upstream, database target, SMTP relay, or other outbound connection ports. Consumer repositories should use these values directly, with inline comments, instead of wrapping them in project globals unless a project intentionally needs a different port.

Port conflicts are evaluated per host. Reusing a port in different clusters or on different hosts is acceptable. Reusing a port on the same host is acceptable only when the listeners are mutually exclusive, bound to different addresses, or owned by the same service path.

## Observability

These ports are the default observability convention for this collection.

| Service | Purpose | Port | Role variable |
| --- | --- | ---: | --- |
| Grafana | Web UI | 3000 | `docker_grafana_http_listen_port` |
| Prometheus | HTTP | 9090 | `docker_prometheus_http_port` |
| Alertmanager | HTTP | 9093 | `docker_alertmanager_http_port` |
| Loki | gRPC | 3099 | `docker_loki_grpc_listen_port` |
| Loki | HTTP | 3100 | `docker_loki_http_listen_port` |
| Tempo | gRPC | 3199 | `docker_tempo_grpc_port` |
| Tempo | HTTP | 3200 | `docker_tempo_http_port` |
| Tempo | OTLP gRPC | 4315 | `docker_tempo_otlp_grpc_port` |
| Tempo | OTLP HTTP | 4316 | `docker_tempo_otlp_http_port` |
| Alloy | Web UI/API | 12345 | `alloy_web_port` |
| Alloy | OTLP gRPC | 4317 | `alloy_otlp_grpc_port` |
| Alloy | OTLP HTTP | 4318 | `alloy_otlp_http_port` |
| Jaeger | Web UI | 16686 | `docker_jaeger_http_port` |
| Jaeger | OTLP gRPC | 4319 | `docker_jaeger_otlp_grpc_port` |
| Jaeger | OTLP HTTP | 4320 | `docker_jaeger_otlp_http_port` |

## Edge and Routing

| Service | Purpose | Port | Role variable |
| --- | --- | ---: | --- |
| HAProxy | Syslog UDP input | 514 | `haproxy_syslog_udp_port` |
| HAProxy ALB | HTTP listener | 80 | template-local listener |
| HAProxy ALB | HTTPS listener | 443 | template-local listener |
| HAProxy ALB | Stats | 8404 | `haproxy_alb_stats_port` |
| HAProxy ALB | Prometheus exporter | 8405 | `haproxy_alb_prometheus_exporter_port` |
| Docker Swarm Traefik | HTTP listener | 80 | template-local listener |
| Docker Swarm Traefik | HTTPS listener | 443 | template-local listener |
| Docker Swarm Traefik | HTTP published port | 1080 | `docker_swarm_traefik_http_expose_port` |
| Docker Swarm Traefik | HTTPS published port | 1443 | `docker_swarm_traefik_https_expose_port` |

## Data Services

| Service | Purpose | Port | Role variable |
| --- | --- | ---: | --- |
| PostgreSQL | Server | 5432 | `docker_postgres_port` |
| PostgreSQL exporter | Public exporter | 9187 | `docker_swarm_postgres_exporter_public_port` |
| Redis | Server | 6379 | `docker_redis_port` |
| Valkey | Server | 6379 | `docker_valkey_port` |
| NATS | Client listener | 4222 | `docker_nats_port` |
| NATS | Monitoring HTTP | 8222 | `docker_nats_http_port` |
| Zitadel | Container HTTP | 8080 | `docker_swarm_zitadel_http_listen_port` |
| Zitadel | HTTP published port | 18080 | `docker_swarm_zitadel_http_public_port` |
| PgHero | Web UI | 10000 | `docker_swarm_pghero_public_port` |

## Exporters and Agents

| Service | Purpose | Port | Role variable |
| --- | --- | ---: | --- |
| cAdvisor | Web metrics | 3997 | `cadvisor_port` |
| Promtail | HTTP | 3998 | `promtail_http_listen_port` |
| Promtail | gRPC | 3999 | `promtail_grpc_listen_port` |
| Node exporter | Web metrics | 9100 | `node_exporter_web_listen_address`, `node_exporter_verify_port` |

## Applications and Tooling

| Service | Purpose | Port | Role variable |
| --- | --- | ---: | --- |
| Base hardening | SSH | 22 | `base_hardening_ssh_port` |
| CrowdSec | Local API/dashboard | 8080 | `crowdsec_http_port` |
| CrowdSec | AppSec local listener | 7422 | template-local listener |
| CrowdSec | SPOA bouncer | 9000 | `crowdsec_spoa_port` |
| CrowdSec | SPOA bouncer local listener | 60601 | template-local listener |
| Docker daemon | TCP API | 2375 | `docker_tcp_socket_port` |
| Dockhand | Web UI listen | 3000 | `docker_swarm_dockhand_http_listen_port` |
| Dockhand | Web UI expose | 9999 | `docker_swarm_dockhand_http_expose_port` |
| GitLab | Node exporter | 9100 | `gitlab_node_exporter_port` |
| Mailpit | SMTP | 1025 | `docker_mailpit_smtp_port` |
| Mailpit | Web UI | 8025 | `docker_mailpit_web_port` |
| Mattermost | HTTP listen address | project-defined | `mattermost_listen_address` |
| Nexus | HTTP | 8081 | `docker_nexus_http_port` |
| SonarQube | HTTP | 9000 | `docker_sonarqube_port` |

## Maintenance Rules

- Shared role defaults and dynamic vars are the source of truth for stable shared-role ports.
- Traefik listens on `80/443` inside the container and publishes `1080/1443` by default regardless of whether Let's Encrypt is enabled.
- Project firewall variables should list the numeric port with a service comment.
- Consumer repositories should inline these standard numeric ports instead of wrapping them in `gv_*_port` variables.
- Consumer repositories should use `gv_*_port` variables only for non-standard project ports that intentionally override shared role defaults.
- Add new standard ports here when adding or changing a shared role default.
- Prefer a focused lint test when a port convention should be enforced.
