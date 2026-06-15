# docker

This role installs and configures Docker daemon settings.

## Features
- Install apt packages.
- Update config.
- Optionally expose the Docker daemon on a TCP socket.
- Restart Docker only when force mode is enabled and the operator approves the daemon restart interactively.

## Configuration
| Variable | Default |
| --- | --- |
| `docker_deb_repo` | `https://download.docker.com/linux/ubuntu` |
| `docker_mirrors` | `['https://cr.yandex/mirror', 'https://dockerhub.timeweb.cloud']` |
| `docker_tcp_socket_enabled` | `false` |
| `docker_tcp_socket_bind_address` | `0.0.0.0` |
| `docker_tcp_socket_port` | `2375` |
| `docker_force_mode` | `<derived>` |
| `docker_interactive_mode` | `<derived>` |
| `docker_arch_map` | `<complex>` |
| `docker_dpkg_arch` | `<derived>` |

When `docker_tcp_socket_enabled` is true, the role configures Docker to listen on `unix:///var/run/docker.sock` and `tcp://{{ docker_tcp_socket_bind_address }}:{{ docker_tcp_socket_port }}`. The role also manages the systemd override required on Debian and Ubuntu systems so Docker does not receive conflicting daemon host settings from both systemd and `/etc/docker/daemon.json`. Exposing the Docker API over TCP grants root-equivalent host access to callers that can reach the port; restrict access with host or network firewalls.

`docker_force_mode` is enabled by setting `FORCE=1` or `FORCE=true`. If Docker daemon config changes during a live run with force mode enabled, the role restarts Docker only after interactive approval. Set `INTERACTIVE=0` or `INTERACTIVE=false` to make required restarts fail instead of prompting. In interactive live runs, approve the restart by typing exactly `yes`.

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.docker
```
