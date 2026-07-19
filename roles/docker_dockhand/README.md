# docker_dockhand

This role deploys Dockhand as a Docker container on every target host.

## Features
- Mount the host Docker Unix socket.
- Bind the Dockhand web UI to `127.0.0.1:3000`.
- Verify the container and local listener are ready.

## Configuration
| Variable | Default |
| --- | --- |
| `docker_dockhand_image_name` | `fnsys/dockhand` |
| `docker_dockhand_image_tag` | `<required>` |
| `docker_dockhand_image_full` | `<derived>` |
| `docker_dockhand_enabled` | `true` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.docker_dockhand
```
