# docker_sonarqube

This role runs SonarQube in a standalone Docker container.

## Features
- Create SonarQube directories.
- Create Docker volumes for SonarQube.
- Start PostgreSQL container.
- Start SonarQube container.

## Configuration
Set these required inputs before applying the role: `docker_sonarqube_postgres_pass`.

| Variable | Default |
| --- | --- |
| `docker_sonarqube_ci_mode` | `<derived>` |
| `docker_sonarqube_debug_mode` | `<derived>` |
| `docker_sonarqube_nolog` | `<derived>` |
| `docker_sonarqube_image_name` | `sonarqube` |
| `docker_sonarqube_image_tag` | `26.6.0.123539-community` |
| `docker_sonarqube_image_full` | `<derived>` |
| `docker_sonarqube_postgres_image_name` | `postgres` |
| `docker_sonarqube_postgres_image_tag` | `17-alpine` |
| `docker_sonarqube_postgres_image_full` | `<derived>` |
| `docker_sonarqube_web_host` | `127.0.0.1` |
| `docker_sonarqube_port` | `9000` |
| `docker_sonarqube_postgres_user` | `sonar` |
| `docker_sonarqube_postgres_pass` | `~` |
| `docker_sonarqube_postgres_database` | `sonar` |
| `docker_sonarqube_postgres_mem_res` | `500M` |
| `docker_sonarqube_postgres_mem_lim` | `750M` |
| `docker_sonarqube_postgres_mem_swp` | `1000M` |
| `docker_sonarqube_cpus` | `2.0` |
| `docker_sonarqube_mem_res` | `1000M` |
| `docker_sonarqube_mem_lim` | `1500M` |
| `docker_sonarqube_mem_swp` | `2000M` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.docker_sonarqube
      vars:
        docker_sonarqube_postgres_pass: <value>
```
