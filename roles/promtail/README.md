# promtail

This role installs and configures Promtail as a system service.

## Features
- Install promtail components.
- Configure promtail components.
- Create config.
- Create service file.
- Ensure that Promtail is restarted.
- Ensure that Promtail is enabled and started.
- Download promtail deb package.
- Install promtail deb package.

## Configuration
Set these required inputs before applying the role: `promtail_version`, `promtail_loki_host`, `promtail_loki_port`.

| Variable | Default |
| --- | --- |
| `promtail_version` | `~` |
| `promtail_download_base_url` | `https://github.com/grafana/loki/releases/download` |
| `promtail_arch_map` | `<complex>` |
| `promtail_arch` | `<derived>` |
| `promtail_deb_package_name` | `<derived>` |
| `promtail_deb_package_path` | `<derived>` |
| `promtail_deb_package_checksum` | `<derived>` |
| `promtail_config_path` | `/etc/promtail/config.yml` |
| `promtail_service_path` | `/etc/systemd/system/promtail.service` |
| `promtail_http_listen_address` | `0.0.0.0` |
| `promtail_http_listen_port` | `3998` |
| `promtail_grpc_listen_address` | `0.0.0.0` |
| `promtail_grpc_listen_port` | `3999` |
| `promtail_positions_path` | `/var/log/positions.yaml` |
| `promtail_loki_host` | `~` |
| `promtail_loki_port` | `~` |
| `promtail_scrape_certbot_enabled` | `true` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.promtail
      vars:
        promtail_version: <value>
        promtail_loki_host: <value>
        promtail_loki_port: <value>
```
