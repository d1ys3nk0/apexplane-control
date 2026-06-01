# app_stack

This role provisions application stack host configuration and PostgreSQL environment files.

## Features
- Create app stack docker overlay networks for each environment.
- Create app stack PostgreSQL env directory.
- Create app stack secret directory.
- Create app stack secrets for each environment.
- Create app stack PostgreSQL users for app user definitions.
- Create app stack PostgreSQL databases for app database definitions.
- Create app stack PostgreSQL users for services.
- Create app stack PostgreSQL databases for services.
- Create app stack service PostgreSQL env files.
- Create app stack admin PostgreSQL client env file.
- Additional focused setup tasks for the same role-owned desired state.

## Configuration
Set these required inputs before applying the role: `app_stack_app_name`, `app_stack_cluster_realm`, `app_stack_pg_host`.

| Variable | Default |
| --- | --- |
| `app_stack_enabled` | `false` |
| `app_stack_network_enabled` | `false` |
| `app_stack_app_name` | `~` |
| `app_stack_apps` | `[]` |
| `app_stack_cluster_realm` | `~` |
| `app_stack_pg_admin_user` | `''` |
| `app_stack_pg_admin_pass` | `''` |
| `app_stack_pg_image` | `postgres:14-alpine` |
| `app_stack_pg_host` | `~` |
| `app_stack_pg_port` | `5432` |
| `app_stack_pg_sslmode` | `disable` |
| `app_stack_pg_backup_concurrency` | `1` |
| `app_stack_pg_recover_concurrency` | `1` |
| `app_stack_pg_recover_no_prepare` | `false` |
| `app_stack_pg_recover_no_recreate` | `false` |
| `app_stack_secrets` | `{}` |
| `app_stack_realm_secrets` | `{}` |
| `app_stack_backups_secret` | `''` |
| `app_stack_backups_s3_endpoint` | `''` |
| `app_stack_backups_s3_region` | `''` |
| `app_stack_backups_s3_bucket` | `''` |
| `app_stack_backups_s3_access_key` | `''` |
| `app_stack_backups_s3_secret_key` | `''` |
| `app_stack_extra_pg_envs` | `[]` |
| `app_stack_postgres_backup_sudoers_enabled` | `false` |
| `app_stack_postgres_backup_sudoers_path` | `''` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.app_stack
      vars:
        app_stack_app_name: <value>
        app_stack_cluster_realm: <value>
        app_stack_pg_host: <value>
```
