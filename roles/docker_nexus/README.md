# docker_nexus

This role runs Nexus Repository in a standalone Docker container.

## Features
- Create docker volumes.
- Start nexus container.

## Configuration
| Variable | Default |
| --- | --- |
| `docker_nexus_image_name` | `sonatype/nexus3` |
| `docker_nexus_image_tag` | `<required>` |
| `docker_nexus_image_full` | `<derived>` |
| `docker_nexus_http_port` | `8081` |
| `docker_nexus_mem_res` | `1000M` |
| `docker_nexus_mem_lim` | `1500M` |
| `docker_nexus_mem_swp` | `2000M` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.docker_nexus
```
