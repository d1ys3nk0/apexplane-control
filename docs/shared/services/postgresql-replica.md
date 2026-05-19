# PostgreSQL Replica

## Replica Checks

```sh
sudo docker exec postgres psql -U admin -c "SELECT pg_is_in_recovery();"
sudo docker exec postgres psql -U admin -c "SELECT status, sender_host, sender_port, conninfo, latest_end_lsn, latest_end_time FROM pg_stat_wal_receiver;"
sudo docker exec postgres psql -U admin -c "SELECT pg_last_wal_receive_lsn() AS receive_lsn, pg_last_wal_replay_lsn() AS replay_lsn, pg_wal_lsn_diff(pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn()) AS replay_lag_bytes, EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()))::int AS replay_lag_seconds;"
sudo docker exec postgres psql -U admin -c "SHOW hot_standby;"
sudo docker logs postgres --since 5m 2>&1 | grep -iE 'fatal|error|panic' || echo "No issues found in last 5 minutes"
```

## Leader Checks

```sh
sudo docker exec postgres psql -U admin -c "SELECT slot_name, active, active_pid, wal_status, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal FROM pg_replication_slots;"
sudo docker exec postgres psql -U admin -c "SELECT application_name, client_addr, state, sync_state, pg_wal_lsn_diff(sent_lsn, replay_lsn) AS replay_lag_bytes, write_lag, flush_lag, replay_lag FROM pg_stat_replication;"
```

## Manual Restore Pattern

Replace placeholders before running.

```sh
sudo docker stop postgres
sudo docker run --rm -v postgres-data:/var/lib/postgresql/data busybox:latest find /var/lib/postgresql/data -mindepth 1 -delete
sudo docker run --rm -e PGPASSWORD='<REPLICATOR_PASSWORD>' -v postgres-data:/var/lib/postgresql/data postgres:14-alpine pg_basebackup -vPR -X stream -c fast -h <leader-host> -p 5432 -U replicator -D /var/lib/postgresql/data -C -S <slot-name>
sudo docker start postgres
```
