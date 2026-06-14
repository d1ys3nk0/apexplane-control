# docker_prometheus

This role runs Prometheus and Blackbox Exporter in standalone Docker containers.

## Features
- Create mount directories.
- Update config.
- Update config from content.
- Update rules.
- Update rules from content.
- Create docker volumes.
- Start prometheus container.
- Configure blackbox exporter.
- Create blackbox exporter config directory.
- Deploy blackbox exporter configuration.
- Additional focused setup tasks for the same role-owned desired state.

## Configuration
Set these required inputs before applying the role: `docker_prometheus_cluster_platform`, `docker_prometheus_cluster_realm`, `docker_prometheus_fqdn_ext`.

| Variable | Default |
| --- | --- |
| `docker_prometheus_cluster_platform` | `~` |
| `docker_prometheus_cluster_realm` | `~` |
| `docker_prometheus_ci_mode` | `<derived>` |
| `docker_prometheus_debug_mode` | `<derived>` |
| `docker_prometheus_nolog` | `<derived>` |
| `docker_prometheus_alertmanager_host` | `127.0.0.1` |
| `docker_prometheus_alertmanager_http_port` | `9093` |
| `docker_prometheus_config_content` | `''` |
| `docker_prometheus_config_template` | `prometheus.yml.j2` |
| `docker_prometheus_custom_alerts` | `''` |
| `docker_prometheus_common_labels` | `{}` |
| `docker_prometheus_fqdn_ext` | `~` |
| `docker_prometheus_http_port` | `9090` |
| `docker_prometheus_image_name` | `prom/prometheus` |
| `docker_prometheus_image_tag` | `v3.12.0` |
| `docker_prometheus_image_full` | `<derived>` |
| `docker_prometheus_promtool_image_name` | `dnanexus/promtool` |
| `docker_prometheus_promtool_image_tag` | `2.9.2` |
| `docker_prometheus_promtool_image_full` | `<derived>` |
| `docker_prometheus_blackbox_image_name` | `prom/blackbox-exporter` |
| `docker_prometheus_blackbox_image_tag` | `v0.28.0` |
| `docker_prometheus_blackbox_image_full` | `<derived>` |
| `docker_prometheus_data_volume` | `prometheus-data` |
| `docker_prometheus_blackbox_container_name` | `blackbox-exporter` |
| `docker_prometheus_blackbox_config_content` | `''` |
| `docker_prometheus_blackbox_targets` | `[]` |
| `docker_prometheus_blackbox_modules` | `<mapping>` |
| `docker_prometheus_blackbox_relabel_configs` | `<list>` |
| `docker_prometheus_loki_host` | `127.0.0.1` |
| `docker_prometheus_loki_http_port` | `3100` |
| `docker_prometheus_mem_res` | `1000M` |
| `docker_prometheus_mem_lim` | `1500M` |
| `docker_prometheus_mem_swp` | `2000M` |
| `docker_prometheus_blackbox_mem_res` | `100M` |
| `docker_prometheus_blackbox_mem_lim` | `150M` |
| `docker_prometheus_blackbox_mem_swp` | `200M` |
| `docker_prometheus_rules_content` | `''` |
| `docker_prometheus_rules_template` | `alerts.yml.j2` |
| `docker_prometheus_targets` | `[]` |
| `docker_prometheus_web_external_url` | `''` |
| `docker_prometheus_extra_args` | `[]` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.docker_prometheus
      vars:
        docker_prometheus_cluster_platform: <value>
        docker_prometheus_cluster_realm: <value>
        docker_prometheus_fqdn_ext: <value>
```
