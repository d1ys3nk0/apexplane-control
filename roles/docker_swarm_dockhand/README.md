# docker_swarm_dockhand

This role deploys Dockhand as a Docker Swarm service.

## Features
- Deploy Dockhand service from leader.
- Ensure Dockhand data directory exists.
- Inspect Docker socket.
- Ensure Dockhand swarm service is started.

## Configuration
| Variable | Default |
| --- | --- |
| `docker_swarm_dockhand_service_name` | `dockhand` |
| `docker_swarm_dockhand_image_name` | `fnsys/dockhand` |
| `docker_swarm_dockhand_image_tag` | `v1.0.29` |
| `docker_swarm_dockhand_image_full` | `<derived>` |
| `docker_swarm_dockhand_data_dir` | `/opt/dockhand` |
| `docker_swarm_dockhand_docker_socket` | `/var/run/docker.sock` |
| `docker_swarm_dockhand_user` | `'0:0'` |
| `docker_swarm_dockhand_http_listen_port` | `3000` |
| `docker_swarm_dockhand_http_expose_port` | `9999` |
| `docker_swarm_dockhand_mem_res` | `600M` |
| `docker_swarm_dockhand_mem_lim` | `900M` |
| `docker_swarm_dockhand_enabled` | `true` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.docker_swarm_dockhand
```
