# postgres

This role installs PostgreSQL packages and can provision an admin user.

## Features
- Download PostgreSQL GPG key.
- Convert PostgreSQL GPG key.
- Install PostgreSQL packages.
- PostgreSQL service is started and enabled.
- Create PostgreSQL admin user.

## Configuration
| Variable | Default |
| --- | --- |
| `postgres_ci_mode` | `<derived>` |
| `postgres_debug_mode` | `<derived>` |
| `postgres_nolog` | `<derived>` |
| `postgres_key_url` | `https://www.postgresql.org/media/keys/ACCC4CF8.asc` |
| `postgres_key_fingerprint` | `B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8` |
| `postgres_key_asc_path` | `/usr/share/keyrings/postgresql-archive-keyring.asc` |
| `postgres_keyring_path` | `/usr/share/keyrings/postgresql-archive-keyring.gpg` |
| `postgres_pg_admin_pass` | `''` |
| `postgres_pg_admin_user` | `''` |
| `postgres_version` | `18` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.postgres
```
