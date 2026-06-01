# node_exporter

This role installs and configures Node Exporter as a system service.

## Features
- Install node_exporter components.
- Configure node_exporter components.
- Create textfile collector directory.
- Create node_exporter service file.
- Ensure node_exporter is restarted.
- Ensure node_exporter is enabled and started.
- Create node_exporter group.
- Create node_exporter user.
- Download node_exporter archive.
- Remove stale node_exporter extraction path.
- Additional focused setup tasks for the same role-owned desired state.

## Configuration
Set these required inputs before applying the role: `node_exporter_version`.

| Variable | Default |
| --- | --- |
| `node_exporter_version` | `~` |
| `node_exporter_download_base_url` | `https://github.com/prometheus/node_exporter/releases/download` |
| `node_exporter_arch_map` | `<complex>` |
| `node_exporter_arch` | `<derived>` |
| `node_exporter_archive_name` | `<derived>` |
| `node_exporter_archive_path` | `<derived>` |
| `node_exporter_archive_checksum` | `<derived>` |
| `node_exporter_extract_path` | `<derived>` |
| `node_exporter_binary_install_dir` | `/usr/local/bin` |
| `node_exporter_system_group` | `node-exp` |
| `node_exporter_system_user` | `<derived>` |
| `node_exporter_textfile_dir` | `/var/lib/node_exporter` |
| `node_exporter_web_listen_address` | `0.0.0.0:9100` |
| `node_exporter_web_telemetry_path` | `/metrics` |
| `node_exporter_verify_port` | `<derived>` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.node_exporter
      vars:
        node_exporter_version: <value>
```
