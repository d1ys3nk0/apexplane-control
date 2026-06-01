# docker_mailpit

This role runs Mailpit in a standalone Docker container.

## Features
- Create mailpit directories.
- Deploy mailpit container.

## Configuration
| Variable | Default |
| --- | --- |
| `docker_mailpit_image_name` | `axllent/mailpit` |
| `docker_mailpit_image_tag` | `v1.30.0` |
| `docker_mailpit_image_full` | `<derived>` |
| `docker_mailpit_data_dir` | `/opt/mailpit/data` |
| `docker_mailpit_smtp_port` | `1025` |
| `docker_mailpit_web_port` | `8025` |
| `docker_mailpit_mem_res` | `100M` |
| `docker_mailpit_mem_lim` | `150M` |
| `docker_mailpit_mem_swp` | `200M` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.docker_mailpit
```
