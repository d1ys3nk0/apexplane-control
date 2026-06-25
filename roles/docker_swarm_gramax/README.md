# docker_swarm_gramax

This role deploys Gramax as a Docker Swarm service.

## Features
- Deploy Gramax service from leader.
- Gramax is started in swarm cluster.

## Configuration
Set these required inputs before applying the role: `docker_swarm_gramax_gramax_admin_login`, `docker_swarm_gramax_gramax_admin_pass`, `docker_swarm_gramax_gramax_pull_token`, `docker_swarm_gramax_gramax_secret`.

| Variable | Default |
| --- | --- |
| `docker_swarm_gramax_ci_mode` | `<derived>` |
| `docker_swarm_gramax_debug_mode` | `<derived>` |
| `docker_swarm_gramax_nolog` | `<derived>` |
| `docker_swarm_gramax_gramax_admin_login` | `~` |
| `docker_swarm_gramax_gramax_admin_pass` | `~` |
| `docker_swarm_gramax_gramax_pull_token` | `~` |
| `docker_swarm_gramax_gramax_secret` | `~` |
| `docker_swarm_gramax_image_name` | `docker.io/gramax/docportal` |
| `docker_swarm_gramax_image_tag` | `<required>` |
| `docker_swarm_gramax_image_full` | `<derived>` |
| `docker_swarm_gramax_mem_res` | `500M` |
| `docker_swarm_gramax_mem_lim` | `750M` |
| `docker_swarm_gramax_enabled` | `true` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.docker_swarm_gramax
      vars:
        docker_swarm_gramax_gramax_admin_login: <value>
        docker_swarm_gramax_gramax_admin_pass: <value>
        docker_swarm_gramax_gramax_pull_token: <value>
        docker_swarm_gramax_gramax_secret: <value>
```
