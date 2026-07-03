# docker_engine_events_exporter

This role runs Docker Engine events exporter in a standalone Docker container.

## Features
- Deploy Docker Engine events exporter.
- Expose exporter metrics on a localhost-only port.
- Verify the exporter container and metrics port are ready.

## Configuration
| Variable | Default |
| --- | --- |
| `docker_engine_events_exporter_image_name` | `ghcr.io/neuroforgede/docker-engine-events-exporter` |
| `docker_engine_events_exporter_image_tag` | `<required>` |
| `docker_engine_events_exporter_image_full` | `<derived>` |
| `docker_engine_events_exporter_container_name` | `docker-engine-events-exporter` |
| `docker_engine_events_exporter_hostname` | `<inventory hostname>` |
| `docker_engine_events_exporter_http_port` | `9324` |
| `docker_engine_events_exporter_mem_res` | `128M` |
| `docker_engine_events_exporter_mem_lim` | `256M` |
| `docker_engine_events_exporter_mem_swp` | `384M` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.docker_engine_events_exporter
      vars:
        docker_engine_events_exporter_image_tag: <value>
```
