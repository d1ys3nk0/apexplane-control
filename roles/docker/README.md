# docker

This role installs and configures Docker daemon settings.

## Features
- Install apt packages.
- Update config.
- Restart Docker when force mode is enabled.
- Allow configured users to manage Docker without sudo.
- Take the newly added docker group into account.

## Configuration
| Variable | Default |
| --- | --- |
| `docker_deb_repo` | `https://download.docker.com/linux/ubuntu` |
| `docker_mirrors` | `['https://cr.yandex/mirror', 'https://dockerhub.timeweb.cloud']` |
| `docker_force_mode` | `<derived>` |
| `docker_users` | `[]` |
| `docker_arch_map` | `<complex>` |
| `docker_dpkg_arch` | `<derived>` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.docker
```
