# docker_swarm_traefik

This role deploys Traefik as a Docker Swarm service.

## Features
- Create directories.
- Create Traefik ACME storage.
- Create shared routing network for Traefik-managed services.
- Deploy Traefik static config.
- Deploy Traefik as Docker Swarm service.
- Expose a private-network Traefik ping health route on the HTTP entrypoint.
- Force Traefik service update on config change.
- Verify the global Traefik service has running tasks on its expected active nodes.

## Configuration
Set these required inputs before applying the role: `docker_swarm_traefik_domain`, `docker_swarm_traefik_letsencrypt_email`.

| Variable | Default |
| --- | --- |
| `docker_swarm_traefik_image_name` | `traefik` |
| `docker_swarm_traefik_image_tag` | `v3.7.1` |
| `docker_swarm_traefik_image_full` | `<derived>` |
| `docker_swarm_traefik_enabled` | `true` |
| `docker_swarm_traefik_service_manage_enabled` | `true` |
| `docker_swarm_traefik_network` | `traefik` |
| `docker_swarm_traefik_domain` | `~` |
| `docker_swarm_traefik_http_expose_port` | `1080` |
| `docker_swarm_traefik_https_expose_port` | `1443` |
| `docker_swarm_traefik_ping_path` | `/_traefik/health` |
| `docker_swarm_traefik_health_allowed_cidrs` | `<complex>` |
| `docker_swarm_traefik_placement_constraints` | `[node.role == manager]` |
| `docker_swarm_traefik_update_order` | `stop-first` |
| `docker_swarm_traefik_update_parallelism` | `1` |
| `docker_swarm_traefik_letsencrypt_email` | `~` |
| `docker_swarm_traefik_letsencrypt_resolver` | `letsencrypt` |
| `docker_swarm_traefik_letsencrypt_storage` | `/etc/traefik/acme/acme.json` |
| `docker_swarm_traefik_mem_res` | `200M` |
| `docker_swarm_traefik_mem_lim` | `300M` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.docker_swarm_traefik
      vars:
        docker_swarm_traefik_domain: <value>
        docker_swarm_traefik_letsencrypt_email: <value>
```
