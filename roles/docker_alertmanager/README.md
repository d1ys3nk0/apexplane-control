# docker_alertmanager

This role runs Alertmanager in a standalone Docker container.

## Features
- Create mount directories.
- Upload config from template.
- Upload config from static file.
- Upload config from content.
- Create docker volumes.
- Start alertmanager container.

## Configuration
| Variable | Default |
| --- | --- |
| `docker_alertmanager_config_content` | `''` |
| `docker_alertmanager_config_file` | `alertmanager.yml` |
| `docker_alertmanager_config_template` | `alertmanager.yml.j2` |
| `docker_alertmanager_ci_mode` | `<derived>` |
| `docker_alertmanager_debug_mode` | `<derived>` |
| `docker_alertmanager_nolog` | `<derived>` |
| `docker_alertmanager_global` | `<complex>` |
| `docker_alertmanager_http_port` | `9093` |
| `docker_alertmanager_image_name` | `prom/alertmanager` |
| `docker_alertmanager_image_tag` | `v0.32.1` |
| `docker_alertmanager_image_full` | `<derived>` |
| `docker_alertmanager_mem_res` | `100M` |
| `docker_alertmanager_mem_lim` | `150M` |
| `docker_alertmanager_mem_swp` | `200M` |
| `docker_alertmanager_receivers` | `<complex>` |
| `docker_alertmanager_route_group_by` | `<complex>` |
| `docker_alertmanager_route_group_interval` | `5m` |
| `docker_alertmanager_route_group_wait` | `30s` |
| `docker_alertmanager_route_receiver` | `blackhole` |
| `docker_alertmanager_route_repeat_interval` | `24h` |
| `docker_alertmanager_routes` | `[]` |
| `docker_alertmanager_template_files` | `[]` |
| `docker_alertmanager_telegram_alerts_chat` | `''` |
| `docker_alertmanager_telegram_alerts_token` | `''` |
| `docker_alertmanager_telegram_receiver_name` | `''` |
| `docker_alertmanager_url` | `http://127.0.0.1:9093` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.docker_alertmanager
```
