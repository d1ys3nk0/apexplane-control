# docker_rabbit

This role runs RabbitMQ in a standalone Docker container.

## Features
- Create docker volumes.
- Start rabbit container.

## Configuration
Set these required inputs before applying the role: `docker_rabbit_default_pass`.

| Variable | Default |
| --- | --- |
| `docker_rabbit_image_name` | `rabbitmq` |
| `docker_rabbit_image_tag` | `<required>` |
| `docker_rabbit_image_full` | `<derived>` |
| `docker_rabbit_data_volume` | `rabbit-data` |
| `docker_rabbit_ci_mode` | `<derived>` |
| `docker_rabbit_debug_mode` | `<derived>` |
| `docker_rabbit_nolog` | `<derived>` |
| `docker_rabbit_default_user` | `admin` |
| `docker_rabbit_default_pass` | `~` |
| `docker_rabbit_mem_res` | `200M` |
| `docker_rabbit_mem_lim` | `300M` |
| `docker_rabbit_mem_swp` | `400M` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.docker_rabbit
      vars:
        docker_rabbit_default_pass: <value>
```
