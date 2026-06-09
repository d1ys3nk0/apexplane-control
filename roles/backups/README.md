# backups

This role renders backup and recovery client environment files for PostgreSQL databases.

## Features
- Create `<home>/postgres` directories for configured PostgreSQL databases.
- Render PostgreSQL backup and recovery dotenv files as `<home>/postgres/<base>.env`.
- Keep backup dotenv generation separate from database provisioning roles.
- Support per-database home, owner, group, port, SSL mode, and PostgreSQL client image overrides.

## Configuration
Set `backups_enabled` to `true` and define `backups_postgres_databases` before applying the role.

| Variable | Default |
| --- | --- |
| `backups_enabled` | `false` |
| `backups_postgres_databases` | `[]` |
| `backups_postgres_image` | `alpine/psql:latest` |
| `backups_postgres_port` | `5432` |
| `backups_postgres_ssl` | `disable` |
| `backups_postgres_backup_concurrency` | `1` |
| `backups_postgres_recover_concurrency` | `{{ backups_postgres_backup_concurrency }}` |
| `backups_postgres_recover_exclude_extensions` | `''` |
| `backups_postgres_recover_no_prepare` | `false` |
| `backups_postgres_recover_no_recreate` | `false` |
| `backups_postgres_backup_secret` | `''` |
| `backups_postgres_backup_s3_endpoint` | `''` |
| `backups_postgres_backup_s3_region` | `''` |
| `backups_postgres_backup_s3_bucket` | `''` |
| `backups_postgres_backup_s3_access_key` | `''` |
| `backups_postgres_backup_s3_secret_key` | `''` |
| `backups_postgres_recover_secret` | `{{ backups_postgres_backup_secret }}` |
| `backups_postgres_recover_s3_endpoint` | `{{ backups_postgres_backup_s3_endpoint }}` |
| `backups_postgres_recover_s3_region` | `{{ backups_postgres_backup_s3_region }}` |
| `backups_postgres_recover_s3_bucket` | `{{ backups_postgres_backup_s3_bucket }}` |
| `backups_postgres_recover_s3_access_key` | `{{ backups_postgres_backup_s3_access_key }}` |
| `backups_postgres_recover_s3_secret_key` | `{{ backups_postgres_backup_s3_secret_key }}` |

Each `backups_postgres_databases` item must define `base`, `user`, `pass`, and `host`. Optional item fields are `home`, `owner`, `group`, `port`, `ssl`, `image`, and `backup`. The default dotenv path is `/home/<user>/postgres/<base>.env`; set `home` when the OS account home differs from the database username. Set `backup: false` to skip rendering an item. PostgreSQL backup and recovery dotenv files use the fixed S3 prefix `postgres/<base>/<UTC yy>/<UTC ISO week>`. Recovery concurrency, secret, and S3 connection variables default to the corresponding backup variables and may be overridden independently.

## Usage

```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.backups
      vars:
        backups_enabled: true
        backups_postgres_backup_s3_endpoint: https://s3.example.test
        backups_postgres_backup_s3_region: us-east-1
        backups_postgres_backup_s3_bucket: backups
        backups_postgres_backup_s3_access_key: example
        backups_postgres_backup_s3_secret_key: example
        backups_postgres_databases:
          - base: app_prd_live01_api
            user: app
            pass: example
            host: postgres.local
          - base: zitadel
            user: zitadel
            pass: example
            host: postgres.local
            home: /home/zitadel
```
