# docker_swarm_alloy

This role deploys Grafana Alloy as a singleton Docker Swarm service for metrics scrape jobs that are not tied to a specific host.

## Features
- Render a metrics-only Alloy configuration from explicit scrape targets.
- Validate rendered Alloy configuration with the pinned Alloy container image before service updates.
- Store the rendered Alloy configuration in a Docker secret.
- Create configured overlay networks for service-to-service scraping.
- Deploy Alloy as a replicated Docker Swarm service with one replica.
- Verify the Alloy Swarm service has a running task.

## Configuration
Set these required inputs before applying the role: `docker_swarm_alloy_metrics_url`, `docker_swarm_alloy_metrics_targets`, `docker_swarm_alloy_cluster_name`, `docker_swarm_alloy_cluster_platform`, `docker_swarm_alloy_cluster_realm`, `docker_swarm_alloy_cluster_world`.

| Variable | Default |
| --- | --- |
| `docker_swarm_alloy_service_name` | `alloy-scraper` |
| `docker_swarm_alloy_ci_mode` | `<derived>` |
| `docker_swarm_alloy_debug_mode` | `<derived>` |
| `docker_swarm_alloy_nolog` | `<derived>` |
| `docker_swarm_alloy_enabled` | `true` |
| `docker_swarm_alloy_image_name` | `grafana/alloy` |
| `docker_swarm_alloy_image_tag` | `<required>` |
| `docker_swarm_alloy_image_full` | `<derived>` |
| `docker_swarm_alloy_config_secret_name_prefix` | `alloy-scraper-config` |
| `docker_swarm_alloy_config_filename` | `/etc/alloy/config.alloy` |
| `docker_swarm_alloy_data_volume` | `<derived>` |
| `docker_swarm_alloy_storage_path` | `/var/lib/alloy/data` |
| `docker_swarm_alloy_http_listen_port` | `12345` |
| `docker_swarm_alloy_metrics_url` | `~` |
| `docker_swarm_alloy_metrics_user` | `''` |
| `docker_swarm_alloy_metrics_pass` | `''` |
| `docker_swarm_alloy_metrics_targets` | `[]` |
| `docker_swarm_alloy_cluster_name` | `~` |
| `docker_swarm_alloy_cluster_platform` | `~` |
| `docker_swarm_alloy_cluster_realm` | `~` |
| `docker_swarm_alloy_cluster_world` | `~` |
| `docker_swarm_alloy_networks` | `[]` |
| `docker_swarm_alloy_placement_constraints` | `[]` |
| `docker_swarm_alloy_mem_res` | `150M` |
| `docker_swarm_alloy_mem_lim` | `250M` |

`docker_swarm_alloy_metrics_targets` is a list of target groups:

```yaml
docker_swarm_alloy_metrics_targets:
  - job_name: postgres
    scheme: http
    metrics_path: /metrics
    scrape_interval: 15s
    targets:
      - address: postgres-exporter:9187
        instance: postgres-exporter
        labels:
          component: postgres_exporter
```

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.docker_swarm_alloy
      vars:
        docker_swarm_alloy_metrics_url: https://prometheus.example.test/api/v1/write
        docker_swarm_alloy_cluster_name: app
        docker_swarm_alloy_cluster_platform: ycl
        docker_swarm_alloy_cluster_realm: prd
        docker_swarm_alloy_cluster_world: example
        docker_swarm_alloy_metrics_targets:
          - job_name: postgres
            targets:
              - address: postgres-exporter:9187
                instance: postgres-exporter
                labels:
                  component: postgres_exporter
```
