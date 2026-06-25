# docker_grafana

This role runs Grafana in a standalone Docker container with provisioned datasources and dashboards.

## Features
- Create mount directories.
- Update static configs.
- Update templated configs.
- Update preinstalled dashboards.
- Create docker volumes.
- Start grafana container.

Dashboard definitions are stored as YAML under `files/dashboards/` for maintainability and deployed as JSON files for Grafana provisioning.

## Configuration
| Variable | Default |
| --- | --- |
| `docker_grafana_image_name` | `grafana/grafana-oss` |
| `docker_grafana_image_tag` | `<required>` |
| `docker_grafana_image_full` | `<derived>` |
| `docker_grafana_http_listen_port` | `3000` |
| `docker_grafana_loki_port` | `3100` |
| `docker_grafana_tempo_port` | `3200` |
| `docker_grafana_prometheus_port` | `9090` |
| `docker_grafana_mem_res` | `300M` |
| `docker_grafana_mem_lim` | `450M` |
| `docker_grafana_mem_swp` | `600M` |
| `docker_grafana_anonymous_enabled` | `'false'` |
| `docker_grafana_config_file` | `grafana.ini` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.docker_grafana
```
