# docker_swarm_pghero

This role deploys PgHero as a Docker Swarm service and can provision PostgreSQL resources.

## Features
- Configure PGHero PostgreSQL resources.
- Deploy PGHero service from generated config file.
- Set PgHero config data.
- Set PgHero config hash.
- Ensure PgHero docker config created.
- Ensure PgHero swarm service created.
- Create pghero user.

## Configuration
Set these required inputs before applying the role: `docker_swarm_pghero_pg_user`, `docker_swarm_pghero_pg_pass`, `docker_swarm_pghero_pg_host`.

| Variable | Default |
| --- | --- |
| `docker_swarm_pghero_image_name` | `ankane/pghero` |
| `docker_swarm_pghero_image_tag` | `v3.7.0` |
| `docker_swarm_pghero_image_full` | `<derived>` |
| `docker_swarm_pghero_public_port` | `10000` |
| `docker_swarm_pghero_mem_res` | `300M` |
| `docker_swarm_pghero_mem_lim` | `450M` |
| `docker_swarm_pghero_pg_admin_user` | `''` |
| `docker_swarm_pghero_pg_admin_pass` | `''` |
| `docker_swarm_pghero_pg_admin_database` | `postgres` |
| `docker_swarm_pghero_pg_user` | `~` |
| `docker_swarm_pghero_pg_pass` | `~` |
| `docker_swarm_pghero_pg_host` | `~` |
| `docker_swarm_pghero_pg_port` | `5432` |
| `docker_swarm_pghero_pg_bases` | `[]` |
| `docker_swarm_pghero_pg_ssl` | `disable` |
| `docker_swarm_pghero_enabled` | `true` |
| `docker_swarm_pghero_ci_mode` | `<derived>` |
| `docker_swarm_pghero_debug_mode` | `<derived>` |
| `docker_swarm_pghero_nolog` | `<derived>` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.docker_swarm_pghero
      vars:
        docker_swarm_pghero_pg_user: <value>
        docker_swarm_pghero_pg_pass: <value>
        docker_swarm_pghero_pg_host: <value>
```
