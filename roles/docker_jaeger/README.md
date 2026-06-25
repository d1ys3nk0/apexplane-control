# docker_jaeger

This role runs Jaeger in a standalone Docker container.

## Features
- Create directories.
- Upload configs.
- Create docker volumes.
- Start jaeger container.

## Configuration
| Variable | Default |
| --- | --- |
| `docker_jaeger_config_template` | `config.yaml.j2` |
| `docker_jaeger_http_port` | `16686` |
| `docker_jaeger_image_name` | `jaegertracing/jaeger` |
| `docker_jaeger_image_tag` | `<required>` |
| `docker_jaeger_image_full` | `<derived>` |
| `docker_jaeger_mem_res` | `500M` |
| `docker_jaeger_mem_lim` | `750M` |
| `docker_jaeger_mem_swp` | `1000M` |
| `docker_jaeger_otlp_grpc_port` | `4319` |
| `docker_jaeger_otlp_http_port` | `4320` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.docker_jaeger
```
