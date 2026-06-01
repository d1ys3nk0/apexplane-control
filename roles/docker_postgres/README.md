# docker_postgres

This role runs PostgreSQL in a standalone Docker container with optional WAL-G and DR operations.

## Features
- Run standalone PostgreSQL DR action.
- Create host directories.
- Install PostgreSQL config.
- Install templated PostgreSQL configs.
- Install PostgreSQL WAL-G executables.
- Build custom PostgreSQL image with WAL-G support.
- Create Docker volume.
- Restore PostgreSQL replica from active leader.
- Start PostgreSQL container.
- Promote PostgreSQL leader during DR.
- Configure WAL-G.
- Additional focused setup tasks for the same role-owned desired state.

## Configuration
Set these required inputs before applying the role: `docker_postgres_pg_admin_pass`, `docker_postgres_pg_admin_user`, `docker_postgres_mode`.

| Variable | Default |
| --- | --- |
| `docker_postgres_image_name` | `postgres` |
| `docker_postgres_image_tag` | `'18'` |
| `docker_postgres_image_full` | `<derived>` |
| `docker_postgres_walg_version` | `''` |
| `docker_postgres_walg_enabled` | `<derived>` |
| `docker_postgres_runtime_image_full` | `<derived>` |
| `docker_postgres_connections` | `100` |
| `docker_postgres_container_name` | `postgres` |
| `docker_postgres_data_volume` | `postgres-data` |
| `docker_postgres_ci_mode` | `<derived>` |
| `docker_postgres_debug_mode` | `<derived>` |
| `docker_postgres_nolog` | `<derived>` |
| `docker_postgres_dr_action` | `none` |
| `docker_postgres_dr_mode` | `false` |
| `docker_postgres_max_wal_size` | `8GB` |
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
| `docker_postgres_backup_s3_endpoint` | `''` |
| `docker_postgres_backup_s3_region` | `''` |
| `docker_postgres_backup_s3_access_key` | `''` |
| `docker_postgres_backup_s3_secret_key` | `''` |
| `docker_postgres_backup_s3_prefix` | `''` |

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
ssh -N -L 2345:127.0.0.1:5432 <postgres-host>
```

### Basic Health

```sh
sudo docker exec postgres psql -U admin -d postgres -x -c "
SELECT
  now() AS ts,
  pg_postmaster_start_time() AS started_at,
  now() - pg_postmaster_start_time() AS uptime;
"
```

Check container start time and memory limits:

```sh
sudo docker inspect postgres --format 'StartedAt={{.State.StartedAt}} Memory={{.HostConfig.Memory}} MemorySwap={{.HostConfig.MemorySwap}} ShmSize={{.HostConfig.ShmSize}}'
```

Check activity:

```sh
sudo docker exec postgres psql -U admin -d postgres -x -c "
SELECT pid, usename, datname, state, wait_event_type, wait_event, now() - query_start AS age, query
FROM pg_stat_activity
WHERE state <> 'idle'
ORDER BY query_start;
"
```

### Role and Database Checks

```sh
sudo docker exec postgres psql -U admin -d postgres -c "\du"
sudo docker exec postgres psql -U admin -d postgres -c "\l"
sudo docker exec postgres psql -U admin -d postgres -c "SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database ORDER BY pg_database_size(datname) DESC;"
```

### Maintenance

```sh
sudo docker exec postgres vacuumdb -U admin --all --analyze
sudo docker exec postgres reindexdb -U admin --all
```

Keep deployment-specific database names, users, backup locations, and restore targets outside this shared role documentation.

### WAL-G Physical Backup and Recovery

Create a physical PostgreSQL cluster backup from the local Docker PostgreSQL container:

```sh
sudo /opt/toolbox/bin/dotenv /opt/postgres/postgres.env /opt/postgres/bin/walg_backup
```

Recover the local PostgreSQL Docker data volume from the default `WALG_RECOVER_S3_PREFIX`:

```sh
sudo /opt/toolbox/bin/dotenv /opt/postgres/postgres.env /opt/postgres/bin/walg_recover
```

Recover from another WAL-G prefix:

```sh
sudo /opt/toolbox/bin/dotenv /opt/postgres/postgres.env /opt/postgres/bin/walg_recover s3://<bucket>/<prefix> LATEST
```

`walg_recover` is destructive at the PostgreSQL cluster level. It prints a 10-second countdown, stops the local `WALG_CONTAINER`, snapshots `WALG_DATA_VOLUME` into `WALG_SNAPSHOT_DIR`, clears the volume, fetches the requested WAL-G backup, writes a temporary PostgreSQL recovery command for the selected source prefix, starts PostgreSQL, waits for recovery, and removes the temporary recovery command after PostgreSQL leaves recovery.

## PostgreSQL Replica

### Replica Checks

```sh
sudo docker exec postgres psql -U admin -c "SELECT pg_is_in_recovery();"
sudo docker exec postgres psql -U admin -c "SELECT status, sender_host, sender_port, conninfo, latest_end_lsn, latest_end_time FROM pg_stat_wal_receiver;"
sudo docker exec postgres psql -U admin -c "SELECT pg_last_wal_receive_lsn() AS receive_lsn, pg_last_wal_replay_lsn() AS replay_lsn, pg_wal_lsn_diff(pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn()) AS replay_lag_bytes, EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()))::int AS replay_lag_seconds;"
sudo docker exec postgres psql -U admin -c "SHOW hot_standby;"
sudo docker logs postgres --since 5m 2>&1 | grep -iE 'fatal|error|panic' || echo "No issues found in last 5 minutes"
```

### Leader Checks

```sh
sudo docker exec postgres psql -U admin -c "SELECT slot_name, active, active_pid, wal_status, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal FROM pg_replication_slots;"
sudo docker exec postgres psql -U admin -c "SELECT application_name, client_addr, state, sync_state, pg_wal_lsn_diff(sent_lsn, replay_lsn) AS replay_lag_bytes, write_lag, flush_lag, replay_lag FROM pg_stat_replication;"
```

### Manual Restore Pattern

Replace placeholders before running.

```sh
sudo docker stop postgres
sudo docker run --rm -v postgres-data:/var/lib/postgresql/data busybox:latest find /var/lib/postgresql/data -mindepth 1 -delete
sudo docker run --rm -e PGPASSWORD='<REPLICATOR_PASSWORD>' -v postgres-data:/var/lib/postgresql/data postgres:14-alpine pg_basebackup -vPR -X stream -c fast -h <leader-host> -p 5432 -U replicator -D /var/lib/postgresql/data -C -S <slot-name>
sudo docker start postgres
```
