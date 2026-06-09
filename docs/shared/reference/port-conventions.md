# Shared Role Port Conventions

This document lists default listen or expose ports owned by `apexplane.control`. It does not list client, upstream, database target, SMTP relay, or other project-specific remote ports.

## Observability

| Component | Purpose | Port | Variable |
| --- | --- | --- | --- |
| Alloy | Metrics/exporter listener | 12345 | `alloy_http_port` |
| Prometheus | HTTP | 9090 | `docker_prometheus_http_port` |
| Alertmanager | HTTP | 9093 | `docker_alertmanager_http_port` |
| Grafana | HTTP | 3000 | `docker_grafana_http_port` |
| Loki | HTTP | 3100 | `docker_loki_http_port` |
| Tempo | OTLP gRPC | 4315 | `docker_tempo_otlp_grpc_port` |
| Tempo | OTLP HTTP | 4316 | `docker_tempo_otlp_http_port` |
| Jaeger | UI | 16686 | `docker_jaeger_ui_port` |

## Edge and Routing

| Component | Purpose | Port | Variable |
| --- | --- | --- | --- |
| HAProxy | Syslog UDP input | 514 | `haproxy_syslog_udp_port` |
| HAProxy ALB | HTTP listener | 80 | template-local listener |
| HAProxy ALB | HTTPS listener | 443 | template-local listener |
| HAProxy ALB | Stats | 8404 | `haproxy_alb_stats_port` |
| HAProxy ALB | Prometheus exporter | 8405 | `haproxy_alb_prometheus_exporter_port` |
| Docker Swarm Traefik | HTTP listener | 80 | template-local listener |
| Docker Swarm Traefik | HTTPS listener | 443 | template-local listener |
| Docker Swarm Traefik | HTTP published port | 1080 | `docker_swarm_traefik_http_expose_port` |
| Docker Swarm Traefik | HTTPS published port | 1443 | `docker_swarm_traefik_https_expose_port` |
| CrowdSec | Local API | 8080 | `crowdsec_http_port` |
| CrowdSec | AppSec local listener | 7422 | template-local listener |
| CrowdSec | SPOA bouncer | 9000 | `crowdsec_spoa_port` |

## Data Services

| Component | Purpose | Port | Variable |
| --- | --- | --- | --- |
| PostgreSQL | PostgreSQL | 5432 | `docker_postgres_pg_port` |
| PostgreSQL exporter | Metrics | 9187 | `docker_swarm_postgres_exporter_port` |
| PgHero | HTTP | 10000 | `docker_swarm_pghero_http_port` |
| Redis | Redis | 6379 | `docker_redis_port` |
| Valkey | Valkey | 6379 | `docker_valkey_port` |
| NATS | Client | 4222 | `docker_nats_client_port` |
| NATS | Monitoring | 8222 | `docker_nats_monitoring_port` |
| RabbitMQ | AMQP | 5672 | `docker_rabbit_amqp_port` |
| Elastic | HTTP | 9200 | `docker_elastic_http_port` |
| MinIO | API | 9000 | `docker_minio_api_port` |
| MinIO | Console | 9001 | `docker_minio_console_port` |

## Applications and Tooling

| Component | Purpose | Port | Variable |
| --- | --- | --- | --- |
| Dockhand | HTTP expose | 9999 | `docker_swarm_dockhand_http_expose_port` |
| GitLab | HTTP | 80 | `gitlab_http_port` |
| GitLab | SSH | 22 | `gitlab_ssh_port` |
| Mattermost | HTTP | 8065 | `mattermost_http_port` |
| Sentry | HTTP | 9000 | `sentry_http_port` |

## Maintenance Rules

- Prefer role defaults and dynamic vars for shared ports.
- Traefik listens on `80/443` inside the container and publishes `1080/1443` by default regardless of whether Let's Encrypt is enabled.
- If a consuming repository intentionally overrides a role port, define a project variable and map it into the role-prefixed variable.
- Keep public ports documented in project topology when they are externally reachable.
