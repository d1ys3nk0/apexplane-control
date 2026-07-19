# docker

This role installs and configures Docker daemon settings.

## Features
- Install apt packages.
- Update config.
- Restart Docker after approval through `YES` or an interactive confirmation.

## Configuration
| Variable | Default |
| --- | --- |
| `docker_deb_repo` | `https://download.docker.com/linux/ubuntu` |
| `docker_mirrors` | `[]` |
| `docker_interactive_mode` | `<derived>` |
| `docker_yes_mode` | `<derived>` |
| `docker_arch_map` | `<complex>` |
| `docker_dpkg_arch` | `<derived>` |

Docker daemon registry mirror URLs must be origin-only URLs without path, query, or fragment components because `dockerd` rejects path-bearing mirror values. Mirrors that expose Docker Hub under a registry namespace, for example `/mirror`, must be used as explicit image prefixes instead of `registry-mirrors` values.

If Docker daemon config changes during a live run, the role restarts Docker only after approval. Set `YES=1` or `YES=true` to preapprove the restart. Without `YES`, interactive live runs prompt for approval: type `yes` case-insensitively to proceed, press Enter to skip, or type any other value to fail. Set `INTERACTIVE=0` or `INTERACTIVE=false` to make required approval fail instead of prompting.

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.docker
```
