# docker_swarm_traefik

This role deploys Traefik as a Docker Swarm service.

## Features
- Create directories.
- Create Traefik ACME storage.
- Create shared routing network for Traefik-managed services.
- Deploy Traefik static config.
- Emit JSON access logs with HAProxy-generated request ID headers retained for request correlation.
- Trust configured HAProxy ingress source ranges for forwarded client IP headers on Traefik entrypoints.
- Deploy Traefik as Docker Swarm service.
- Expose a private-network Traefik ping health route on the HTTP entrypoint.
- Force Traefik service update on config change.
- Verify the global Traefik service has running tasks on its expected active nodes.

## Configuration
Set this required input before applying the role: `docker_swarm_traefik_letsencrypt_email`.

| Variable | Default |
| --- | --- |
| `docker_swarm_traefik_image_name` | `traefik` |
| `docker_swarm_traefik_image_tag` | `<required>` |
| `docker_swarm_traefik_image_full` | `<derived>` |
| `docker_swarm_traefik_enabled` | `true` |
| `docker_swarm_traefik_service_manage_enabled` | `true` |
| `docker_swarm_traefik_network` | `traefik` |
| `docker_swarm_traefik_http_expose_port` | `1080` |
| `docker_swarm_traefik_https_expose_port` | `1443` |
| `docker_swarm_traefik_internal_health_domains` | `[]` (required non-empty list of internal machine FQDNs) |
| `docker_swarm_traefik_internal_health_paths` | `['/_traefik/health']` |
| `docker_swarm_traefik_forwarded_headers_trusted_ips` | `<complex>` |
| `docker_swarm_traefik_placement_constraints` | `[node.role == manager]` |
| `docker_swarm_traefik_update_order` | `stop-first` |
| `docker_swarm_traefik_update_parallelism` | `1` |
| `docker_swarm_traefik_letsencrypt_email` | `~` |
| `docker_swarm_traefik_letsencrypt_resolver` | `letsencrypt` |
| `docker_swarm_traefik_letsencrypt_storage` | `/etc/traefik/acme/acme.json` |
| `docker_swarm_traefik_mem_res` | `200M` |
| `docker_swarm_traefik_mem_lim` | `300M` |

The static Traefik config writes JSON access logs and keeps the `X-Request-ID` and `X-Forwarded-For` request headers. This allows requests proxied from HAProxy ALB to be correlated across HAProxy, Traefik, and backend application logs while the forwarded client IP remains visible during debugging. Other request headers remain dropped from Traefik access logs by default.

Traefik trusts `X-Forwarded-*` headers only from `docker_swarm_traefik_forwarded_headers_trusted_ips`. Keep this list limited to HAProxy ALB or other trusted ingress hops so Traefik can log the real client IP and forward the client IP chain to backend applications without accepting spoofed forwarded headers from arbitrary clients.

The automatic insecure API router is disabled. The role-owned `api@internal` router accepts dashboard and API paths only with a `localhost` or `127.0.0.1` Host header on the HTTP entrypoint, for access through a loopback SSH forward. The health router requires both a configured internal machine FQDN and one of the configured exact paths.

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.docker_swarm_traefik
      vars:
        docker_swarm_traefik_letsencrypt_email: <value>
```
