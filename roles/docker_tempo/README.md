# docker_tempo

This role runs Tempo in a standalone Docker container.

## Features
- Create directories.
- Upload configs.
- Create docker volumes.
- Ensure Tempo volume permissions.
- Start tempo container.

## Configuration
Set these required inputs before applying the role: `docker_tempo_cluster_name`, `docker_tempo_cluster_realm`, `docker_tempo_cluster_platform`.

| Variable | Default |
| --- | --- |
| `docker_tempo_cluster_name` | `~` |
| `docker_tempo_cluster_realm` | `~` |
| `docker_tempo_cluster_platform` | `~` |
| `docker_tempo_grpc_port` | `3199` |
| `docker_tempo_http_port` | `3200` |
| `docker_tempo_image_name` | `grafana/tempo` |
| `docker_tempo_image_tag` | `2.10.5` |
| `docker_tempo_image_full` | `<derived>` |
| `docker_tempo_init_image_name` | `busybox` |
| `docker_tempo_init_image_tag` | `1.37.0` |
| `docker_tempo_init_image_full` | `<derived>` |
| `docker_tempo_mem_res` | `1000M` |
| `docker_tempo_mem_lim` | `1500M` |
| `docker_tempo_mem_swp` | `2000M` |
| `docker_tempo_otlp_grpc_port` | `4315` |
| `docker_tempo_otlp_http_port` | `4316` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.docker_tempo
      vars:
        docker_tempo_cluster_name: <value>
        docker_tempo_cluster_realm: <value>
        docker_tempo_cluster_platform: <value>
```
