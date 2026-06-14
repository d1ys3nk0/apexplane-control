# runtime

This role prepares application runtime host resources, Docker secrets, and application PostgreSQL resources.

## Features
- Create Docker overlay networks for each runtime environment.
- Create versioned Docker Swarm secrets with dotenv payloads for resolved app environment unit secret mappings as `<app>-<realm>-<env>-<unit>-<YYMMDDHHMMSS>-<hash>`.
- Optionally persist the exact Docker secret dotenv payloads under `/home/<app>/secrets/<realm>_<env>_<unit>.env`.
- Create PostgreSQL users and databases from resolved PostgreSQL base mappings when complete admin credentials are provided.

## Configuration
Set these required inputs before applying the role: `runtime_apps`, `runtime_pg_bases`, `runtime_cluster_realm`, and `runtime_pg_host`.

| Variable | Default |
| --- | --- |
| `runtime_enabled` | `false` |
| `runtime_network_enabled` | `false` |
| `runtime_secrets_dotenv` | `false` |
| `runtime_docker_secret_manager_path` | `/opt/toolbox/bin/docker_secret_manager` |
| `runtime_apps` | `[]` |
| `runtime_pg_bases` | `[]` |
| `runtime_cluster_realm` | `~` |
| `runtime_pg_admin_user` | `''` |
| `runtime_pg_admin_pass` | `''` |
| `runtime_pg_host` | `~` |
| `runtime_pg_port` | `5432` |
| `runtime_pg_ssl` | `disable` |

`runtime_apps` entries define app accounts, environments, and resolved per-service secret mappings. Service `secrets` mappings create Docker Swarm secrets with a timestamp and content hash suffix through `runtime_docker_secret_manager_path`; the role creates a new Docker secret when the latest matching secret hash differs from the current dotenv payload and does not remove old versions. Run the `toolbox` role with `toolbox_docker_enabled: true` before this role when runtime unit secrets are configured. Set `runtime_secrets_dotenv: true` to use `/home/<app>/secrets/<realm>_<env>_<unit>.env` as the Docker secret source; the role creates that file only when it is missing and never overwrites an existing file. When disabled, the role uses temporary dotenv files and removes them after the secret manager runs. Secret keys must be valid dotenv variable names, and secret values must be scalar. `runtime_pg_bases` entries define resolved application PostgreSQL provisioning inputs; each entry must define `app`, `base`, `user`, and `pass`; optional `owner` overrides the database owner and defaults to `user`. Empty PostgreSQL admin credentials skip provisioning users and databases. Complete PostgreSQL admin credentials enable provisioning for all runtime bases. Use the `backups` role to render PostgreSQL backup and recovery dotenv files.

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
            owner: app_prd_live01_api
            pass: example
```
