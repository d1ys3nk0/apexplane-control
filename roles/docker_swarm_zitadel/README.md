# docker_swarm_zitadel

This role deploys ZITADEL as a Docker Swarm service and can provision PostgreSQL resources.

## Features
- Deploy Zitadel swarm service from Docker Swarm manager.
- Configure Zitadel PostgreSQL resources.
- Ensure Zitadel swarm service is started.
- Create Zitadel user.
- Create Zitadel database.
- Select the Zitadel runtime command from explicit input or first-instance org bootstrap data.

## Configuration
Set these required inputs before applying the role: `docker_swarm_zitadel_domain`, `docker_swarm_zitadel_masterkey`, `docker_swarm_zitadel_pg_base`, `docker_swarm_zitadel_pg_user`, `docker_swarm_zitadel_pg_pass`, `docker_swarm_zitadel_pg_host`.

| Variable | Default |
| --- | --- |
| `docker_swarm_zitadel_enabled` | `true` |
| `docker_swarm_zitadel_service_name` | `zitadel` |
| `docker_swarm_zitadel_domain` | `~` |
| `docker_swarm_zitadel_http_listen_port` | `8080` |
| `docker_swarm_zitadel_http_public_port` | `18080` |
| `docker_swarm_zitadel_image_name` | `ghcr.io/zitadel/zitadel` |
| `docker_swarm_zitadel_image_tag` | `v4.15.0` |
| `docker_swarm_zitadel_image_full` | `<derived>` |
| `docker_swarm_zitadel_command` | `''` (derive from first-instance org inputs) |
| `docker_swarm_zitadel_masterkey` | `~` |
| `docker_swarm_zitadel_mem_res` | `500M` |
| `docker_swarm_zitadel_mem_lim` | `750M` |
| `docker_swarm_zitadel_init_org_name` | `''` |
| `docker_swarm_zitadel_init_org_human_username` | `''` |
| `docker_swarm_zitadel_init_org_human_password` | `''` |
| `docker_swarm_zitadel_init_org_human_password_change_required` | `false` |
| `docker_swarm_zitadel_pg_admin_pass` | `''` |
| `docker_swarm_zitadel_pg_admin_user` | `''` |
| `docker_swarm_zitadel_pg_base` | `~` |
| `docker_swarm_zitadel_pg_user` | `~` |
| `docker_swarm_zitadel_pg_pass` | `~` |
| `docker_swarm_zitadel_pg_host` | `~` |
| `docker_swarm_zitadel_pg_port` | `5432` |
| `docker_swarm_zitadel_pg_ssl` | `disable` |
| `docker_swarm_zitadel_pg_image` | `postgres:18-alpine` |
| `docker_swarm_zitadel_pg_backup_concurrency` | `1` |
| `docker_swarm_zitadel_pg_recover_concurrency` | `{{ docker_swarm_zitadel_pg_backup_concurrency }}` |
| `docker_swarm_zitadel_pg_recover_exclude_extensions` | `''` |
| `docker_swarm_zitadel_pg_recover_no_prepare` | `false` |
| `docker_swarm_zitadel_pg_recover_no_recreate` | `false` |
| `docker_swarm_zitadel_pg_backup_secret` | `''` |
| `docker_swarm_zitadel_pg_backup_s3_endpoint` | `''` |
| `docker_swarm_zitadel_pg_backup_s3_region` | `''` |
| `docker_swarm_zitadel_pg_backup_s3_bucket` | `''` |
| `docker_swarm_zitadel_pg_backup_s3_access_key` | `''` |
| `docker_swarm_zitadel_pg_backup_s3_secret_key` | `''` |
| `docker_swarm_zitadel_pg_recover_secret` | `{{ docker_swarm_zitadel_pg_backup_secret }}` |
| `docker_swarm_zitadel_pg_recover_s3_endpoint` | `{{ docker_swarm_zitadel_pg_backup_s3_endpoint }}` |
| `docker_swarm_zitadel_pg_recover_s3_region` | `{{ docker_swarm_zitadel_pg_backup_s3_region }}` |
| `docker_swarm_zitadel_pg_recover_s3_bucket` | `{{ docker_swarm_zitadel_pg_backup_s3_bucket }}` |
| `docker_swarm_zitadel_pg_recover_s3_access_key` | `{{ docker_swarm_zitadel_pg_backup_s3_access_key }}` |
| `docker_swarm_zitadel_pg_recover_s3_secret_key` | `{{ docker_swarm_zitadel_pg_backup_s3_secret_key }}` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.docker_swarm_zitadel
      vars:
        docker_swarm_zitadel_domain: <value>
        docker_swarm_zitadel_masterkey: <value>
        docker_swarm_zitadel_pg_base: <value>
        docker_swarm_zitadel_pg_user: <value>
        docker_swarm_zitadel_pg_pass: <value>
        docker_swarm_zitadel_pg_host: <value>
        docker_swarm_zitadel_pg_ssl: disable
```

## Operations
The `docker_swarm_zitadel` role manages the Docker Swarm service and root-owned PostgreSQL helper dotenv file at `/opt/zitadel/postgres/<database>.env`.

PostgreSQL backup and recovery dotenv files use the fixed S3 prefix `postgres/<database>/<UTC yy>/<UTC ISO week>`. Recovery concurrency, secret, and S3 connection variables default to the corresponding backup variables and may be overridden independently.

By default the service command is dynamic: when `docker_swarm_zitadel_command` is empty and all first-instance org credential variables are set, the role runs `zitadel start-from-init`; otherwise it runs `zitadel start`. Set `docker_swarm_zitadel_command` to `start`, `start-from-setup`, or `start-from-init` only when an explicit override is needed.

ZITADEL documents `start-from-init` as running init, setup, and then the runtime server; see the [ZITADEL CLI command overview](https://zitadel.com/docs/self-hosting/manage/cli/overview). Use it only for first bootstrap of an empty database. If the database user and database are manually provisioned without PostgreSQL admin access, ZITADEL still requires schema bootstrapping with `zitadel init schema` before `start-from-setup` or `start`; see the [ZITADEL database guide](https://zitadel.com/docs/self-hosting/manage/database).

Example first-instance bootstrap inputs:

```yaml
docker_swarm_zitadel_init_org_name: <org-name>
docker_swarm_zitadel_init_org_human_username: <admin-email>
docker_swarm_zitadel_init_org_human_password: <admin-password>
docker_swarm_zitadel_init_org_human_password_change_required: false
```
