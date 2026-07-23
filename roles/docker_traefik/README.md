# docker_traefik

This role deploys Traefik as a standalone Docker container on an enabled Docker Swarm manager.

## Features

- Validate that the enabled target is an active Docker Swarm manager.
- Create Traefik directories and optional ACME storage.
- Create an attachable overlay network for Traefik-managed Swarm services.
- Deploy static configuration for the Swarm and file providers.
- Deploy role-owned dashboard/API and ping routers through dynamic file configuration.
- Emit JSON access logs with selected request headers retained for request correlation.
- Trust configured ingress source ranges for forwarded client IP headers.
- Run a host-local `traefik` container with explicit HTTP and HTTPS host port bindings.
- Restart the local container when role-owned static or dynamic configuration changes, and let the container module recreate it when the image or container specification changes.
- Verify that the container is running, both published ports accept connections, and every configured health path returns HTTP 200.

## Configuration

Set the required `docker_traefik_image_tag` input before applying the role. Set `docker_traefik_letsencrypt_email` to enable ACME.

| Variable | Default |
| --- | --- |
| `docker_traefik_image_name` | `traefik` |
| `docker_traefik_image_tag` | `<required>` |
| `docker_traefik_image_full` | `<derived>` |
| `docker_traefik_enabled` | `true` |
| `docker_traefik_network` | `traefik` |
| `docker_traefik_http_expose_port` | `1080` |
| `docker_traefik_https_expose_port` | `1443` |
| `docker_traefik_health_paths` | `['/_traefik/health']` |
| `docker_traefik_forwarded_headers_trusted_ips` | `<complex>` |
| `docker_traefik_letsencrypt_email` | `~` |
| `docker_traefik_letsencrypt_resolver` | `letsencrypt` |
| `docker_traefik_letsencrypt_storage` | `/etc/traefik/acme/acme.json` |
| `docker_traefik_mem_res` | `200M` |
| `docker_traefik_mem_lim` | `300M` |

The static Traefik config writes JSON access logs and keeps the `X-Request-ID` and `X-Forwarded-For` request headers. Other request headers remain dropped from Traefik access logs by default.

Traefik trusts `X-Forwarded-*` headers only from `docker_traefik_forwarded_headers_trusted_ips`. Keep this list limited to trusted ingress hops so Traefik can preserve the client IP chain without accepting spoofed forwarded headers from arbitrary clients.

The role-owned dynamic configuration routes `/api` and `/dashboard` path prefixes to `api@internal`. Every exact path in `docker_traefik_health_paths` routes to `ping@internal`. These routers use the HTTP entrypoint and do not constrain the request `Host`.

## Usage

```yaml
---

- hosts: docker_swarm_managers
  roles:
    - role: apexplane.control.docker_traefik
      vars:
        docker_traefik_image_tag: <value>
```
