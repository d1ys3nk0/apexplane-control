#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=../lib/helpers.sh
source "${SCRIPT_DIR}/../lib/helpers.sh"

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
            _info "usage: docker-cleanup [--dry-run] [--restart]"
            _info "remove Docker containers in dead state; --restart clears stale daemon records after backing up broken metadata"
            return 0
            ;;
        *)
            _error "docker-cleanup: unknown argument: $arg"
            ;;
        esac
    done

    if ! command -v docker >/dev/null 2>&1; then
        _error "docker-cleanup: docker command not found"
    fi

    mapfile -t dead_ids < <(docker ps -a --no-trunc --filter status=dead --format '{{.ID}}')
    if [ "${#dead_ids[@]}" -eq 0 ]; then
        _info "docker-cleanup: no dead containers found"
        return 0
    fi

    _info "docker-cleanup: found ${#dead_ids[@]} dead container(s)"
    _cmd docker ps -a --filter status=dead --format 'table {{.ID}}\t{{.Names}}\t{{.Status}}'

    if [ "$dry_run" -eq 1 ]; then
        _info "docker-cleanup: dry run; no containers removed"
        return 0
    fi

    _cmd docker rm "${dead_ids[@]}" || true

    mapfile -t remaining_ids < <(docker ps -a --no-trunc --filter status=dead --format '{{.ID}}')
    if [ "${#remaining_ids[@]}" -eq 0 ]; then
        _info "docker-cleanup: dead containers removed"
        return 0
    fi

    for id in "${remaining_ids[@]}"; do
        if docker inspect "$id" >/dev/null 2>&1; then
            _info "docker-cleanup: container $id is still inspectable after docker rm failed"
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
            _info "docker-cleanup: refusing stale cleanup for $id because metadata validation failed"
        fi
    done

    if [ "${#stale_ids[@]}" -eq 0 ]; then
        _error "docker-cleanup: no validated stale dead metadata to move"
    fi

    backup_dir="/var/lib/docker/dead-containers-backup-$(date +%Y%m%d%H%M%S)"
    _cmd sudo mkdir "$backup_dir"
    for id in "${stale_ids[@]}"; do
        _cmd sudo mv "/var/lib/docker/containers/$id" "$backup_dir/"
    done
    _info "docker-cleanup: moved ${#stale_ids[@]} stale container directories to $backup_dir"

    if [ "$restart_docker" -ne 1 ]; then
        _info "docker-cleanup: Docker may still list stale records until the daemon restarts"
        _info "docker-cleanup: run docker-cleanup --restart to restart Docker after the backup step"
        return 0
    fi

    _cmd sudo systemctl restart docker
    _cmd sudo systemctl is-active docker

    mapfile -t remaining_ids < <(docker ps -a --no-trunc --filter status=dead --format '{{.ID}}')
    if [ "${#remaining_ids[@]}" -eq 0 ]; then
        _info "docker-cleanup: no dead containers remain"
        return 0
    fi

    _info "docker-cleanup: dead containers still remain after Docker restart"
    _cmd docker ps -a --filter status=dead --format 'table {{.ID}}\t{{.Names}}\t{{.Status}}' >&2
    return 1
}

main "$@"
