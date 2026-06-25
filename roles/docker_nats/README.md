# docker_nats

This role runs NATS in a standalone Docker container.

## Features
- Create nats directory.
- Create docker volumes.
- Start nats container.

## Configuration
| Variable | Default |
| --- | --- |
| `docker_nats_image_name` | `nats` |
| `docker_nats_image_tag` | `<required>` |
| `docker_nats_image_full` | `<derived>` |
| `docker_nats_port` | `4222` |
| `docker_nats_http_port` | `8222` |
| `docker_nats_mem_res` | `100M` |
| `docker_nats_mem_lim` | `150M` |
| `docker_nats_mem_swp` | `200M` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.docker_nats
```
