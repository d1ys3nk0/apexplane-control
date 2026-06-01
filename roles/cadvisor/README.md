# cadvisor

This role installs and configures cAdvisor as a system service.

## Features
- Install cadvisor components.
- Configure cadvisor components.
- Create cadvisor service file.
- Ensure cadvisor is restarted.
- Ensure cadvisor is enabled and started.
- Download cadvisor binary.
- Install cadvisor binary.

## Configuration
Set these required inputs before applying the role: `cadvisor_version`.

| Variable | Default |
| --- | --- |
| `cadvisor_version` | `~` |
| `cadvisor_download_base_url` | `https://github.com/google/cadvisor/releases/download` |
| `cadvisor_arch_map` | `<complex>` |
| `cadvisor_arch` | `<derived>` |
| `cadvisor_binary_name` | `<derived>` |
| `cadvisor_binary_path` | `<derived>` |
| `cadvisor_binary_checksum` | `''` |
| `cadvisor_binary_install_dir` | `/usr/local/bin` |
| `cadvisor_listen_ip` | `0.0.0.0` |
| `cadvisor_port` | `3997` |
| `cadvisor_prometheus_endpoint` | `/metrics` |
| `cadvisor_system_group` | `root` |
| `cadvisor_system_user` | `<derived>` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.cadvisor
      vars:
        cadvisor_version: <value>
```
