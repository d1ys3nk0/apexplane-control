# docker_ctop

This role installs the ctop Docker monitoring utility.

## Features
- Download ctop binary.

## Configuration
| Variable | Default |
| --- | --- |
| `docker_ctop_version` | `0.7.7` |
| `docker_ctop_download_base_url` | `https://github.com/bcicen/ctop/releases/download` |
| `docker_ctop_arch_map` | `<complex>` |
| `docker_ctop_arch` | `<derived>` |
| `docker_ctop_binary_name` | `<derived>` |
| `docker_ctop_binary_path` | `/usr/local/bin/ctop` |
| `docker_ctop_binary_checksum` | `<derived>` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.docker_ctop
```
