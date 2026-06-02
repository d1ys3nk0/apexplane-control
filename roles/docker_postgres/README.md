# docker_postgres

This role runs PostgreSQL in a standalone Docker container with optional WAL-G and DR operations.

## Features
- Run standalone PostgreSQL DR action.
- Set up vanilla PostgreSQL when `docker_postgres_walg_binary_url` is empty.
- Set up PostgreSQL with WAL-G when `docker_postgres_walg_binary_url` is set.
- Install shared PostgreSQL directories, configs, dotenv, history, and Docker volume.
- Install WAL-G executables and build the WAL-G image only for the WAL-G setup path.
- Restore PostgreSQL replica from active leader.
- Start PostgreSQL container.
- Promote PostgreSQL leader during DR.
- Configure WAL-G.

## Configuration
Set these required inputs before applying the role: `docker_postgres_data_dir`, `docker_postgres_pg_admin_pass`, `docker_postgres_pg_admin_user`, `docker_postgres_mode`. The PostgreSQL container defaults to `docker_postgres_container: postgres`, and the listener/readiness port defaults to `docker_postgres_port: 5432`.

| Variable | Default |
| --- | --- |
| `docker_postgres_image_name` | `postgres` |
| `docker_postgres_image_tag` | `'18'` |
| `docker_postgres_image_full` | `<derived>` |
| `docker_postgres_image_runtime` | `<derived>` |
| `docker_postgres_connections` | `100` |
| `docker_postgres_container` | `postgres` |
| `docker_postgres_data_volume` | `postgres-data` |
| `docker_postgres_data_root` | `/var/lib/postgresql` |
| `docker_postgres_data_dir` | `~` |
| `docker_postgres_ci_mode` | `<derived>` |
| `docker_postgres_debug_mode` | `<derived>` |
| `docker_postgres_nolog` | `<derived>` |
| `docker_postgres_dr_action` | `none` |
| `docker_postgres_dr_mode` | `false` |
| `docker_postgres_max_wal_size` | `4GB` |
| `docker_postgres_mem_res` | `1000M` |
| `docker_postgres_mem_lim` | `1500M` |
| `docker_postgres_mem_swp` | `2000M` |
| `docker_postgres_min_wal_size` | `2GB` |
| `docker_postgres_pg_admin_pass` | `~` |
| `docker_postgres_pg_admin_user` | `~` |
| `docker_postgres_pg_fallback_host` | `''` |
| `docker_postgres_pg_fallback_port` | `5432` |
| `docker_postgres_pg_fallback_src` | `''` |
| `docker_postgres_pg_replicator_pass` | `''` |
| `docker_postgres_pg_replicator_user` | `''` |
| `docker_postgres_port` | `5432` |
| `docker_postgres_replica_restore` | `<derived>` |
| `docker_postgres_mode` | `~` |
| `docker_postgres_utility_image_name` | `busybox` |
| `docker_postgres_utility_image_tag` | `1.37.0` |
| `docker_postgres_utility_image_full` | `<derived>` |
| `docker_postgres_walg_binary_url` | `''` |
| `docker_postgres_walg_enabled` | `<derived>` |
| `docker_postgres_walg_backup_s3_endpoint` | `''` |
| `docker_postgres_walg_backup_s3_region` | `''` |
| `docker_postgres_walg_backup_s3_bucket` | `''` |
| `docker_postgres_walg_backup_s3_prefix` | `''` |
| `docker_postgres_walg_backup_s3_access_key` | `''` |
| `docker_postgres_walg_backup_s3_secret_key` | `''` |
| `docker_postgres_walg_recover_s3_endpoint` | `''` |
| `docker_postgres_walg_recover_s3_region` | `''` |
| `docker_postgres_walg_recover_s3_bucket` | `''` |
| `docker_postgres_walg_recover_s3_prefix` | `''` |
| `docker_postgres_walg_recover_s3_access_key` | `''` |
| `docker_postgres_walg_recover_s3_secret_key` | `''` |
| `docker_postgres_walg_recover_origin_base` | `''` |
| `docker_postgres_walg_recover_origin_owner` | `''` |
| `docker_postgres_walg_recover_origin_users` | `[]` |
| `docker_postgres_walg_recover_target_base` | `''` |
| `docker_postgres_walg_recover_target_user` | `''` |
| `docker_postgres_walg_recover_target_pass` | `''` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.docker_postgres
      vars:
        docker_postgres_pg_admin_pass: <value>
        docker_postgres_pg_admin_user: <value>
        docker_postgres_mode: <value>
```

## Operations
### Tunneling

```sh
ssh -N -L 2345:127.0.0.1:<port> <postgres-host>
```

### Basic Health

```sh
sudo docker exec <container> psql -p <port> -U admin -d postgres -x -c "
SELECT
  now() AS ts,
  pg_postmaster_start_time() AS started_at,
  now() - pg_postmaster_start_time() AS uptime;
"
```

Check container start time and memory limits:

```sh
sudo docker inspect <container> --format 'StartedAt={{.State.StartedAt}} Memory={{.HostConfig.Memory}} MemorySwap={{.HostConfig.MemorySwap}} ShmSize={{.HostConfig.ShmSize}}'
```

Check activity:

```sh
sudo docker exec <container> psql -p <port> -U admin -d postgres -x -c "
SELECT pid, usename, datname, state, wait_event_type, wait_event, now() - query_start AS age, query
FROM pg_stat_activity
WHERE state <> 'idle'
ORDER BY query_start;
"
```

### Role and Database Checks

```sh
sudo docker exec <container> psql -p <port> -U admin -d postgres -c "\du"
sudo docker exec <container> psql -p <port> -U admin -d postgres -c "\l"
sudo docker exec <container> psql -p <port> -U admin -d postgres -c "SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database ORDER BY pg_database_size(datname) DESC;"
```

### Maintenance

```sh
sudo docker exec <container> vacuumdb -p <port> -U admin --all --analyze
sudo docker exec <container> reindexdb -p <port> -U admin --all
```

Keep deployment-specific database names, users, backup locations, and restore targets outside this shared role documentation.

### WAL-G Physical Backup and Recovery

Create a physical PostgreSQL cluster backup with a standalone WAL-G container that mounts the configured data volume:

```sh
sudo /opt/toolbox/bin/dotenv /opt/postgres/env /opt/postgres/bin/walg_backup
```

Recover the local PostgreSQL Docker data volume from the default `WALG_RECOVER_S3_PREFIX`:

```sh
sudo /opt/toolbox/bin/dotenv /opt/postgres/env /opt/postgres/bin/walg_recover
```

Recover from another WAL-G prefix:

```sh
sudo /opt/toolbox/bin/dotenv /opt/postgres/env /opt/postgres/bin/walg_recover s3://<bucket>/<prefix> LATEST
```

`walg_recover` is destructive at the PostgreSQL cluster level. It prints a 10-second countdown, snapshots `WALG_DATA_VOLUME` into `WALG_SNAPSHOT_DIR`, clears the volume, fetches the requested WAL-G backup, writes a temporary PostgreSQL recovery command for the selected source prefix, starts a temporary `WALG_RECOVER_CONTAINER` from `WALG_IMAGE` with the recovered volume mounted, prints recovery progress every `WALG_RECOVER_PROGRESS_SECONDS` seconds while waiting, removes the temporary recovery command after PostgreSQL leaves recovery, and removes the temporary recovery container unless `WALG_RECOVER_KEEP_CONTAINER=true`. Recovery progress includes container state, PostgreSQL readiness, `pg_is_in_recovery()`, recovered data size in KiB, WAL restore log size in bytes, and replay LSN when PostgreSQL is queryable. When `WALG_RECOVER_ORIGIN_BASE`, `WALG_RECOVER_ORIGIN_OWNER`, `WALG_RECOVER_ORIGIN_USERS`, and `WALG_RECOVER_TARGET_*` are set, the script also reconciles the recovered database and role names after recovery.

Stop any PostgreSQL process or container using `WALG_DATA_VOLUME` before running `walg_recover`.

## PostgreSQL Replica

### Replica Checks

```sh
sudo docker exec <container> psql -p <port> -U admin -c "SELECT pg_is_in_recovery();"
sudo docker exec <container> psql -p <port> -U admin -c "SELECT status, sender_host, sender_port, conninfo, latest_end_lsn, latest_end_time FROM pg_stat_wal_receiver;"
sudo docker exec <container> psql -p <port> -U admin -c "SELECT pg_last_wal_receive_lsn() AS receive_lsn, pg_last_wal_replay_lsn() AS replay_lsn, pg_wal_lsn_diff(pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn()) AS replay_lag_bytes, EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()))::int AS replay_lag_seconds;"
sudo docker exec <container> psql -p <port> -U admin -c "SHOW hot_standby;"
sudo docker logs <container> --since 5m 2>&1 | grep -iE 'fatal|error|panic' || echo "No issues found in last 5 minutes"
```

### Leader Checks

```sh
sudo docker exec <container> psql -p <port> -U admin -c "SELECT slot_name, active, active_pid, wal_status, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal FROM pg_replication_slots;"
sudo docker exec <container> psql -p <port> -U admin -c "SELECT application_name, client_addr, state, sync_state, pg_wal_lsn_diff(sent_lsn, replay_lsn) AS replay_lag_bytes, write_lag, flush_lag, replay_lag FROM pg_stat_replication;"
```

### Manual Restore Pattern

Replace placeholders before running.

```sh
sudo docker stop <container>
sudo docker run --rm -v <data-volume>:<data-root> <utility-image> find <data-dir> -mindepth 1 -delete
sudo docker run --rm -e PGPASSWORD='<REPLICATOR_PASSWORD>' -v <data-volume>:<data-root> <postgres-image> pg_basebackup -vPR -X stream -c fast -h <leader-host> -p <leader-port> -U replicator -D <data-dir> -C -S <slot-name>
sudo docker start <container>
```
