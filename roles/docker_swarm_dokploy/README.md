# docker_swarm_dokploy

This role deploys Dokploy, its bundled PostgreSQL and Redis services, and the Dokploy-managed Traefik container on an existing Docker Swarm manager.

## Features
- Validate required Dokploy secrets, paths, ports, and Docker Swarm manager state.
- Create the Dokploy data directory and attachable overlay network.
- Store Dokploy PostgreSQL and auth credentials as Docker secrets.
- Deploy bundled PostgreSQL, Redis, and Dokploy as Docker Swarm services.
- Run Dokploy Traefik as a standalone Docker container attached to the Dokploy overlay network.
- Verify Swarm service tasks, the Dokploy web UI port, the Traefik container state, and Traefik listener ports.

## Configuration
Set these required inputs before applying the role: `docker_swarm_dokploy_postgres_password`, `docker_swarm_dokploy_auth_secret`.

| Variable | Default |
| --- | --- |
| `docker_swarm_dokploy_ci_mode` | `<derived>` |
| `docker_swarm_dokploy_debug_mode` | `<derived>` |
| `docker_swarm_dokploy_nolog` | `<derived>` |
| `docker_swarm_dokploy_enabled` | `true` |
| `docker_swarm_dokploy_image_name` | `dokploy/dokploy` |
| `docker_swarm_dokploy_image_tag` | `v0.29.8` |
| `docker_swarm_dokploy_image_full` | `<derived>` |
| `docker_swarm_dokploy_postgres_image_name` | `postgres` |
| `docker_swarm_dokploy_postgres_image_tag` | `'16'` |
| `docker_swarm_dokploy_postgres_image_full` | `<derived>` |
| `docker_swarm_dokploy_redis_image_name` | `redis` |
| `docker_swarm_dokploy_redis_image_tag` | `'7'` |
| `docker_swarm_dokploy_redis_image_full` | `<derived>` |
| `docker_swarm_dokploy_traefik_image_name` | `traefik` |
| `docker_swarm_dokploy_traefik_image_tag` | `v3.6.7` |
| `docker_swarm_dokploy_traefik_image_full` | `<derived>` |
| `docker_swarm_dokploy_service_name` | `dokploy` |
| `docker_swarm_dokploy_postgres_service_name` | `dokploy-postgres` |
| `docker_swarm_dokploy_redis_service_name` | `dokploy-redis` |
| `docker_swarm_dokploy_traefik_container_name` | `dokploy-traefik` |
| `docker_swarm_dokploy_network` | `dokploy-network` |
| `docker_swarm_dokploy_data_dir` | `/etc/dokploy` |
| `docker_swarm_dokploy_docker_socket` | `/var/run/docker.sock` |
| `docker_swarm_dokploy_docker_config_volume` | `dokploy` |
| `docker_swarm_dokploy_postgres_data_volume` | `dokploy-postgres` |
| `docker_swarm_dokploy_redis_data_volume` | `dokploy-redis` |
| `docker_swarm_dokploy_postgres_password_secret_name` | `dokploy-postgres-password` |
| `docker_swarm_dokploy_auth_secret_name` | `dokploy-auth-secret` |
| `docker_swarm_dokploy_postgres_password` | `~` |
| `docker_swarm_dokploy_auth_secret` | `~` |
| `docker_swarm_dokploy_postgres_user` | `dokploy` |
| `docker_swarm_dokploy_postgres_database` | `dokploy` |
| `docker_swarm_dokploy_http_expose_port` | `3000` |
| `docker_swarm_dokploy_traefik_http_expose_port` | `80` |
| `docker_swarm_dokploy_traefik_https_expose_port` | `443` |
| `docker_swarm_dokploy_advertise_addr` | `<derived>` |
| `docker_swarm_dokploy_endpoint_mode` | `vip` |
| `docker_swarm_dokploy_release_tag` | `latest` |
| `docker_swarm_dokploy_postgres_mem_res` | `300M` |
| `docker_swarm_dokploy_postgres_mem_lim` | `500M` |
| `docker_swarm_dokploy_redis_mem_res` | `100M` |
| `docker_swarm_dokploy_redis_mem_lim` | `200M` |
| `docker_swarm_dokploy_mem_res` | `600M` |
| `docker_swarm_dokploy_mem_lim` | `900M` |
| `docker_swarm_dokploy_traefik_mem_res` | `200M` |
| `docker_swarm_dokploy_traefik_mem_lim` | `300M` |

Run Docker and Docker Swarm setup before this role. The role intentionally does not install Docker, initialize Swarm, or reset Swarm state.

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.docker_swarm_dokploy
      vars:
        docker_swarm_dokploy_postgres_password: <value>
        docker_swarm_dokploy_auth_secret: <value>
```
