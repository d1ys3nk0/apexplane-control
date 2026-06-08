# docker_ctop

This role installs the ctop Docker monitoring utility.

## Features
- Install ctop from a persistent controller-side cache.
- Skip network and content checks when the target binary already exists.

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
| `docker_ctop_cache_dir` | `<controller home>/.cache/apexplane-control/docker_ctop` |
| `docker_ctop_cache_path` | `<derived>` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.docker_ctop
```
