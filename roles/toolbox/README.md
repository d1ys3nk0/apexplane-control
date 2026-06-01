# toolbox

This role installs shared operator shell helpers and optional Docker, HAProxy, and PostgreSQL scripts.

## Features
- Create directories.
- Install psqlrc.
- Install toolbox shell library.
- Install bash toolbox.
- Install always-enabled executables from files.
- Install Docker executables from files.
- Remove disabled Docker executables.
- Install HAProxy executables from files.
- Remove disabled HAProxy executables.
- Install PostgreSQL executables from files.
- Remove disabled PostgreSQL executables.

## Configuration
| Variable | Default |
| --- | --- |
| `toolbox_install_dir` | `/opt/toolbox` |
| `toolbox_docker_enabled` | `false` |
| `toolbox_haproxy_enabled` | `false` |
| `toolbox_postgres_enabled` | `false` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.toolbox
```

## Operations
The `toolbox` role installs shell shortcuts plus always-enabled and optional operator scripts under `/opt/toolbox`. Executable scripts are installed without `.sh` extensions under `/opt/toolbox/bin`, which is added to `PATH` by the toolbox Bash definitions. The PostgreSQL scripts run client tools inside the configured `PG_IMAGE` Docker image with host networking.

Run scripts through `dotenv` so the required environment is loaded without printing secrets.

```sh
/opt/toolbox/bin/dotenv /path/to/env /opt/toolbox/bin/pg_client -d postgres -c '\l'
```

Load multiple dotenv files left-to-right by separating paths with `:`. Later files override values from earlier files.

```sh
/opt/toolbox/bin/dotenv /path/to/base.env:/path/to/app.env /opt/toolbox/bin/pg_client -d postgres -c '\l'
```

Override a value from the dotenv file for one command by placing the assignment after the dotenv file path and before the script path.

All PostgreSQL toolbox scripts use the same connection environment variables: `PG_IMAGE`, `PG_HOST`, `PG_PORT`, `PG_USER`, `PG_PASS`, and optional `PG_SSL`. Database-scoped scripts use `PG_BASE` as the managed database name. `pg_client` connects to `PG_BASE`.

Set `QUIET=1` or `QUIET=true` to suppress toolbox helper `_info`, `_warn`, and `_cmd` log lines while keeping the underlying command behavior unchanged.

### Installed Files

- `/opt/toolbox/psqlrc`
- `/opt/toolbox/lib/helpers.sh`, with shared elapsed-time logging and command execution helpers for toolbox scripts
- `/etc/skel/.bash_toolbox`, with `/opt/toolbox/bin` added to `PATH` and optional Docker and HAProxy definitions rendered only when their script families are enabled
- `/opt/toolbox/bin/dotenv`
- `/opt/toolbox/bin/sysrep`

Docker scripts are installed when `toolbox_docker_enabled` is true:

- `/opt/toolbox/bin/docker_cleanup`
- `/opt/toolbox/bin/docker_secret`

HAProxy scripts are installed when `toolbox_haproxy_enabled` is true:

- `/opt/toolbox/bin/certbot_dns_auth`
- `/opt/toolbox/bin/certbot_dns_cleanup`
- `/opt/toolbox/bin/certbot_dns_issue`
- `/opt/toolbox/bin/haproxy_report`

PostgreSQL scripts are installed when `toolbox_postgres_enabled` is true:

- `/opt/toolbox/bin/pg_client`
- `/opt/toolbox/bin/pg_vacuum`
- `/opt/toolbox/bin/pg_reindex`
- `/opt/toolbox/bin/pg_amcheck`
- `/opt/toolbox/bin/pg_backup`
- `/opt/toolbox/bin/pg_recover`
- `/opt/toolbox/bin/pg_user`

### Docker Secrets

View, edit, push, or prune timestamped Docker Swarm secrets from an app runtime secret file:

```sh
sudo /opt/toolbox/bin/docker_secret view app/eng/test01/api
sudo /opt/toolbox/bin/docker_secret edit app/eng/test01/api
sudo /opt/toolbox/bin/docker_secret push app/eng/test01/api
sudo /opt/toolbox/bin/docker_secret prune app/eng
```

### HAProxy Reports

Count requests per effective client IP from the current HAProxy traffic log:

```sh
sudo /opt/toolbox/bin/haproxy_report
```

Include rotated logs by passing files or quoted globs:

```sh
sudo /opt/toolbox/bin/haproxy_report '/var/log/haproxy/traffic.log*'
```

### Manual Wildcard Certificates

Use `certbot_dns_issue` to generate wildcard certificates before running roles that expect pre-existing HAProxy PEM files:

```sh
sudo /opt/toolbox/bin/certbot_dns_issue --cert-name wildcard-example --email admin@example.com --domain '*.example.com' --domain example.com
```

The script starts Certbot with DNS-01 manual auth hooks, prints the required `_acme-challenge` TXT records, waits for confirmation and DNS propagation, then installs `/etc/ssl/haproxy/<cert-name>-<md5(sorted-comma-joined-domains)>.pem`.

After the PEM is installed, run the HAProxy role so it validates SAN coverage, validates expiry, and reloads HAProxy with the new certificate.

### Backup and Restore

Create a backup:

```sh
sudo /opt/toolbox/bin/dotenv /path/to/pg-database.env /opt/toolbox/bin/pg_backup
```

By default, backups use `PG_BACKUP_FORMAT=dir` and `PG_BACKUP_CONCURRENCY=1`. Directory-format backups are archived as uncompressed `.tar` files so `pg_dump` can stay parallel without adding a serial gzip pass.

Create a local-only backup when S3 variables are configured:

```sh
sudo /opt/toolbox/bin/dotenv /path/to/pg-database.env PG_BACKUP_S3=0 /opt/toolbox/bin/pg_backup backups
```

Override dir-format backup concurrency:

```sh
sudo /opt/toolbox/bin/dotenv /path/to/pg-database.env PG_BACKUP_CONCURRENCY=8 /opt/toolbox/bin/pg_backup
```

Restore a local backup file:

```sh
sudo /opt/toolbox/bin/dotenv /path/to/pg-database.env /opt/toolbox/bin/pg_recover /var/backups/postgres/latest.tar
```

Restore format is detected from the backup extension. Set `PG_RECOVER_FORMAT=sql|dir|cst` only for backups with non-standard extensions; restore fails when it cannot determine the format.

Restore the latest S3 backup under `PG_RECOVER_S3_PREFIX`:

```sh
sudo /opt/toolbox/bin/dotenv /path/to/pg-database.env /opt/toolbox/bin/pg_recover
```

Run restore and post-restore analyze with multiple jobs:

```sh
sudo /opt/toolbox/bin/dotenv /path/to/pg-database.env PG_RECOVER_CONCURRENCY=8 /opt/toolbox/bin/pg_recover
```

Override restore format detection when restoring a backup with a non-standard extension:

```sh
sudo /opt/toolbox/bin/dotenv /path/to/pg-database.env PG_RECOVER_FORMAT=cst /opt/toolbox/bin/pg_recover /var/backups/postgres/manual.backup
```

Restore into an existing managed database by dropping all non-system schemas first:

```sh
sudo /opt/toolbox/bin/dotenv /path/to/pg-database.env PG_RECOVER_NO_RECREATE=true /opt/toolbox/bin/pg_recover
```

Exclude extension entries from an archive restore when the target role cannot create them:

```sh
sudo /opt/toolbox/bin/dotenv /path/to/pg-database.env PG_RECOVER_EXCLUDE_EXTENSIONS="pg_stat_statements" /opt/toolbox/bin/pg_recover
```

Restore an exact S3 object:

```sh
sudo /opt/toolbox/bin/dotenv /path/to/pg-database.env /opt/toolbox/bin/pg_recover s3:<prefix>/<object>.tar
```
