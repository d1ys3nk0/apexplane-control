#!/usr/bin/env bash

set -euo pipefail

main() {
    local restart_docker=0
    local dry_run=0
    local arg
    local dead_ids=()
    local remaining_ids=()
    local stale_ids=()
    local id
    local backup_dir=""

    for arg in "$@"; do
        case "$arg" in
        --restart)
            restart_docker=1
            ;;
        --dry-run)
            dry_run=1
            ;;
        -h | --help)
            echo "usage: docker-cleanup [--dry-run] [--restart]" >&2
            echo "remove Docker containers in dead state; --restart clears stale daemon records after backing up broken metadata" >&2
            return 0
            ;;
        *)
            echo "docker-cleanup: unknown argument: $arg" >&2
            echo "usage: docker-cleanup [--dry-run] [--restart]" >&2
            return 2
            ;;
        esac
    done

    if ! command -v docker >/dev/null 2>&1; then
        echo "docker-cleanup: docker command not found" >&2
        return 127
    fi

    mapfile -t dead_ids < <(docker ps -a --no-trunc --filter status=dead --format '{{.ID}}')
    if [ "${#dead_ids[@]}" -eq 0 ]; then
        echo "docker-cleanup: no dead containers found"
        return 0
    fi

    echo "docker-cleanup: found ${#dead_ids[@]} dead container(s)"
    docker ps -a --filter status=dead --format 'table {{.ID}}\t{{.Names}}\t{{.Status}}'

    if [ "$dry_run" -eq 1 ]; then
        echo "docker-cleanup: dry run; no containers removed"
        return 0
    fi

    docker rm "${dead_ids[@]}" || true

    mapfile -t remaining_ids < <(docker ps -a --no-trunc --filter status=dead --format '{{.ID}}')
    if [ "${#remaining_ids[@]}" -eq 0 ]; then
        echo "docker-cleanup: dead containers removed"
        return 0
    fi

    for id in "${remaining_ids[@]}"; do
        if docker inspect "$id" >/dev/null 2>&1; then
            echo "docker-cleanup: container $id is still inspectable after docker rm failed" >&2
            continue
        fi

        if sudo python3 - "$id" <<'PY' >/dev/null 2>&1; then
import json
import sys
from pathlib import Path

container_id = sys.argv[1]
config_path = Path("/var/lib/docker/containers") / container_id / "config.v2.json"
with config_path.open() as config_file:
    config = json.load(config_file)
state = config.get("State", {})
if config.get("ID") != container_id or state.get("Dead") is not True or state.get("Running") is not False:
    raise SystemExit(1)
PY
            stale_ids+=("$id")
        else
            echo "docker-cleanup: refusing stale cleanup for $id because metadata validation failed" >&2
        fi
    done

    if [ "${#stale_ids[@]}" -eq 0 ]; then
        echo "docker-cleanup: no validated stale dead metadata to move" >&2
        return 1
    fi

    backup_dir="/var/lib/docker/dead-containers-backup-$(date +%Y%m%d%H%M%S)"
    sudo mkdir "$backup_dir"
    for id in "${stale_ids[@]}"; do
        sudo mv "/var/lib/docker/containers/$id" "$backup_dir/"
    done
    echo "docker-cleanup: moved ${#stale_ids[@]} stale container directories to $backup_dir"

    if [ "$restart_docker" -ne 1 ]; then
        echo "docker-cleanup: Docker may still list stale records until the daemon restarts"
        echo "docker-cleanup: run docker-cleanup --restart to restart Docker after the backup step"
        return 0
    fi

    sudo systemctl restart docker
    sudo systemctl is-active docker

    mapfile -t remaining_ids < <(docker ps -a --no-trunc --filter status=dead --format '{{.ID}}')
    if [ "${#remaining_ids[@]}" -eq 0 ]; then
        echo "docker-cleanup: no dead containers remain"
        return 0
    fi

    echo "docker-cleanup: dead containers still remain after Docker restart" >&2
    docker ps -a --filter status=dead --format 'table {{.ID}}\t{{.Names}}\t{{.Status}}' >&2
    return 1
}

main "$@"
