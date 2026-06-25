# docker_loki

This role runs Loki in a standalone Docker container.

## Features
- Create mount directories.
- Upload configs.
- Create docker volumes.
- Start loki container.

## Configuration
| Variable | Default |
| --- | --- |
| `docker_loki_image_name` | `grafana/loki` |
| `docker_loki_image_tag` | `<required>` |
| `docker_loki_image_full` | `<derived>` |
| `docker_loki_grpc_listen_port` | `3099` |
| `docker_loki_http_listen_port` | `3100` |
| `docker_loki_alertmanager_host` | `localhost` |
| `docker_loki_alertmanager_port` | `9093` |
| `docker_loki_config_template` | `loki-config.yaml.j2` |
| `docker_loki_mem_res` | `1000M` |
| `docker_loki_mem_lim` | `1500M` |
| `docker_loki_mem_swp` | `2000M` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.docker_loki
```

## Operations
Explore labels:

```sh
curl -s "http://localhost:43100/loki/api/v1/labels" | jq
curl -s "http://localhost:43100/loki/api/v1/label/level/values" | jq .data
```

Query a service over a fixed range:

```sh
SERVICE="<service>"
START=$(date -u -d '72 hours ago' +%s)
END=$(date -u -d '71 hours ago' +%s)
curl -G 'http://localhost:43100/loki/api/v1/query_range' \
  --data-urlencode "query={service=\"$SERVICE\"}" \
  --data-urlencode "start=${START}000000000" \
  --data-urlencode "end=${END}000000000" \
  --data-urlencode "step=60s" \
  | jq
```

Keep labels and values minimal. High-cardinality labels make Loki expensive and harder to operate.
