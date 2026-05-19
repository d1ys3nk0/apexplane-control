# PostgreSQL

## Tunneling

```sh
ssh -N -L 2345:127.0.0.1:5432 <postgres-host>
```

## Basic Health

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

## Role and Database Checks

```sh
sudo docker exec postgres psql -U admin -d postgres -c "\du"
sudo docker exec postgres psql -U admin -d postgres -c "\l"
sudo docker exec postgres psql -U admin -d postgres -c "SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database ORDER BY pg_database_size(datname) DESC;"
```

## Maintenance

```sh
sudo docker exec postgres vacuumdb -U admin --all --analyze
sudo docker exec postgres reindexdb -U admin --all
```

Use project runbooks for project-specific database names, users, backup locations, and restore targets.
