# runtime

This role prepares application runtime host resources, Docker secrets, and application PostgreSQL client environment files.

## Features
- Create Docker overlay networks for each runtime environment.
- Create `/home/<app>/postgres` directories.
- Create versioned Docker Swarm secrets with dotenv payloads for resolved app environment unit secret mappings as `<app>-<realm>-<env>-<unit>-<YYMMDDHHMMSS>-<hash>`.
- Render resolved PostgreSQL base mappings to `/home/<app>/postgres/<base>.env`.
- Create PostgreSQL users and databases from resolved PostgreSQL base mappings when complete admin credentials are provided.

## Configuration
Set these required inputs before applying the role: `runtime_apps`, `runtime_pg_bases`, `runtime_cluster_realm`, and `runtime_pg_host`.

| Variable | Default |
| --- | --- |
| `runtime_enabled` | `false` |
| `runtime_network_enabled` | `false` |
| `runtime_apps` | `[]` |
| `runtime_pg_bases` | `[]` |
| `runtime_cluster_realm` | `~` |
| `runtime_pg_admin_user` | `''` |
| `runtime_pg_admin_pass` | `''` |
| `runtime_pg_image` | `postgres:latest` |
| `runtime_pg_host` | `~` |
| `runtime_pg_port` | `5432` |
| `runtime_pg_ssl` | `disable` |
| `runtime_pg_backup_concurrency` | `1` |
| `runtime_pg_recover_concurrency` | `{{ runtime_pg_backup_concurrency }}` |
| `runtime_pg_recover_exclude_extensions` | `''` |
| `runtime_pg_recover_no_prepare` | `false` |
| `runtime_pg_recover_no_recreate` | `false` |
| `runtime_pg_backup_secret` | `''` |
| `runtime_pg_backup_s3_endpoint` | `''` |
| `runtime_pg_backup_s3_region` | `''` |
| `runtime_pg_backup_s3_bucket` | `''` |
| `runtime_pg_backup_s3_access_key` | `''` |
| `runtime_pg_backup_s3_secret_key` | `''` |
| `runtime_pg_recover_secret` | `{{ runtime_pg_backup_secret }}` |
| `runtime_pg_recover_s3_endpoint` | `{{ runtime_pg_backup_s3_endpoint }}` |
| `runtime_pg_recover_s3_region` | `{{ runtime_pg_backup_s3_region }}` |
| `runtime_pg_recover_s3_bucket` | `{{ runtime_pg_backup_s3_bucket }}` |
| `runtime_pg_recover_s3_access_key` | `{{ runtime_pg_backup_s3_access_key }}` |
| `runtime_pg_recover_s3_secret_key` | `{{ runtime_pg_backup_s3_secret_key }}` |

`runtime_apps` entries define app accounts, environments, and resolved per-service secret mappings. Service `secrets` mappings create Docker Swarm secrets with a timestamp and content hash suffix; the role creates a new Docker secret when the latest matching secret hash differs from the current canonical dotenv payload and does not remove old versions. Secret keys must be valid dotenv variable names, and secret values must be scalar. `runtime_pg_bases` entries define resolved application PostgreSQL env files and optional provisioning inputs; each entry must define `app`, `base`, `user`, and `pass`. PostgreSQL backup and recovery dotenv files use the fixed S3 prefix `postgres/<base>/<UTC yy>/<UTC ISO week>`. Recovery concurrency, secret, and S3 connection variables default to the corresponding backup variables and may be overridden independently. Empty PostgreSQL admin credentials render client env files without provisioning users or databases. Complete PostgreSQL admin credentials enable provisioning for all runtime bases.

## Usage

```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.runtime
      vars:
        runtime_cluster_realm: prd
        runtime_pg_host: postgres.local
        runtime_pg_ssl: disable
        runtime_apps:
          - name: app
            envs:
              - slug: live01
                services:
                  - name: api
                    secrets:
                      SECRET_KEY: example
        runtime_pg_bases:
          - app: app
            base: app_prd_live01_api
            user: app_prd_live01_api
            pass: example
```
