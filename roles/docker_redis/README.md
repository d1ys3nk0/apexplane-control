# docker_redis

This role runs Redis in a standalone Docker container.

## Features
- Show Redis memory limit.
- Create docker volumes.
- Start redis container.

## Configuration
| Variable | Default |
| --- | --- |
| `docker_redis_command` | `''` |
| `docker_redis_container_name` | `redis` |
| `docker_redis_data_volume` | `redis-data` |
| `docker_redis_healthcheck_enabled` | `true` |
| `docker_redis_hostname` | `redis` |
| `docker_redis_image_name` | `redis` |
| `docker_redis_image_tag` | `7.4.9` |
| `docker_redis_image_full` | `<derived>` |
| `docker_redis_mem_res` | `200M` |
| `docker_redis_mem_lim` | `300M` |
| `docker_redis_mem_swp` | `400M` |
| `docker_redis_port` | `6379` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.docker_redis
```
