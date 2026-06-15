# docker

This role installs and configures Docker daemon settings.

## Features
- Install apt packages.
- Update config.
- Restart Docker only when force mode is enabled and the operator approves the daemon restart interactively.

## Configuration
| Variable | Default |
| --- | --- |
| `docker_deb_repo` | `https://download.docker.com/linux/ubuntu` |
| `docker_mirrors` | `['https://cr.yandex/mirror', 'https://dockerhub.timeweb.cloud']` |
| `docker_force_mode` | `<derived>` |
| `docker_interactive_mode` | `<derived>` |
| `docker_arch_map` | `<complex>` |
| `docker_dpkg_arch` | `<derived>` |

`docker_force_mode` is enabled by setting `FORCE=1` or `FORCE=true`. If Docker daemon config changes during a live run with force mode enabled, the role restarts Docker only after interactive approval. Set `INTERACTIVE=0` or `INTERACTIVE=false` to make required restarts fail instead of prompting. In interactive live runs, approve the restart by typing exactly `yes`.

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.docker
```
