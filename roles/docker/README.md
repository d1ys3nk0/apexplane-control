# docker

This role installs and configures Docker daemon settings.

## Features
- Install apt packages.
- Update config.
- Optionally expose the Docker daemon on a TCP socket.
- Restart Docker after approval through `YES` or an interactive confirmation.

## Configuration
| Variable | Default |
| --- | --- |
| `docker_deb_repo` | `https://download.docker.com/linux/ubuntu` |
| `docker_mirrors` | `[]` |
| `docker_tcp_socket_enabled` | `false` |
| `docker_tcp_socket_bind_address` | `0.0.0.0` |
| `docker_tcp_socket_port` | `2375` |
| `docker_interactive_mode` | `<derived>` |
| `docker_yes_mode` | `<derived>` |
| `docker_arch_map` | `<complex>` |
| `docker_dpkg_arch` | `<derived>` |

When `docker_tcp_socket_enabled` is true, the role configures Docker to listen on `unix:///var/run/docker.sock` and `tcp://{{ docker_tcp_socket_bind_address }}:{{ docker_tcp_socket_port }}`. The role also manages the systemd override required on Debian and Ubuntu systems so Docker does not receive conflicting daemon host settings from both systemd and `/etc/docker/daemon.json`. Exposing the Docker API over TCP grants root-equivalent host access to callers that can reach the port; restrict access with host or network firewalls.

Docker daemon registry mirror URLs must be origin-only URLs without path, query, or fragment components because `dockerd` rejects path-bearing mirror values. Mirrors that expose Docker Hub under a registry namespace, for example `/mirror`, must be used as explicit image prefixes instead of `registry-mirrors` values.

If Docker daemon config changes during a live run, the role restarts Docker only after approval. Set `YES=1` or `YES=true` to preapprove the restart. Without `YES`, interactive live runs prompt for approval: type `yes` case-insensitively to proceed, press Enter to skip, or type any other value to fail. Set `INTERACTIVE=0` or `INTERACTIVE=false` to make required approval fail instead of prompting.

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.docker
```
