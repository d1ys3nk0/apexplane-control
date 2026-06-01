# docker_valkey

This role runs Valkey in a standalone Docker container.

## Features
- Show Valkey memory limit.
- Create docker volumes.
- Start valkey container.

## Configuration
| Variable | Default |
| --- | --- |
| `docker_valkey_command` | `''` |
| `docker_valkey_container_name` | `valkey` |
| `docker_valkey_data_volume` | `valkey-data` |
| `docker_valkey_healthcheck_enabled` | `true` |
| `docker_valkey_hostname` | `valkey` |
| `docker_valkey_image_name` | `valkey/valkey` |
| `docker_valkey_image_tag` | `9.0.4` |
| `docker_valkey_image_full` | `<derived>` |
| `docker_valkey_mem_res` | `200M` |
| `docker_valkey_mem_lim` | `300M` |
| `docker_valkey_mem_swp` | `400M` |
| `docker_valkey_port` | `6379` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.docker_valkey
```
