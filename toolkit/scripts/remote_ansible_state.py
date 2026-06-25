#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import fcntl
import json
import re
import sys
from pathlib import Path
from typing import Any, TextIO


REMOTE_STATE_UTC = dt.timezone.utc  # noqa: UP017 - remote targets can still run Python 3.10.


def state_paths(namespace: str) -> tuple[Path, Path]:
    if not re.fullmatch(r"ansible-[a-z0-9_-]+", namespace):
        raise SystemExit(
            "Invalid namespace: expected ansible- followed by lowercase letters, digits, underscores, or hyphens"
        )
    return Path("/var/lib") / namespace / "state.json", Path("/run/lock") / f"{namespace}-state.lock"


def read_state(state_path: Path) -> dict[str, Any]:
    if not state_path.exists():
        return {}
    try:
        state = json.loads(state_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Invalid remote Ansible state JSON in {state_path}: {exc}") from exc
    if not isinstance(state, dict):
        raise SystemExit(f"Invalid remote Ansible state JSON in {state_path}: root must be an object")
    for key in ("migrate_tag", "locked_at", "locked_by"):
        value = state.get(key)
        if value is not None and not isinstance(value, str):
            raise SystemExit(f"Invalid remote Ansible state key {key}: expected string")
    migrate_tags = state.get("migrate_tags")
    if migrate_tags is not None and (
        not isinstance(migrate_tags, list) or not all(isinstance(tag, str) for tag in migrate_tags)
    ):
        raise SystemExit("Invalid remote Ansible state key migrate_tags: expected list of strings")
    return state


def write_state(state_path: Path, state: dict[str, Any]) -> None:
    state_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = state_path.with_suffix(f"{state_path.suffix}.tmp")
    tmp_path.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    tmp_path.replace(state_path)
    state_path.chmod(0o600)


def with_lock(lock_path: Path) -> TextIO:
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    lock_file = lock_path.open("w", encoding="utf-8")
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
    return lock_file


def emit(state: dict[str, Any]) -> None:
    payload = {key: state.get(key, "") for key in ("migrate_tag", "locked_at", "locked_by")}
    if "migrate_tags" in state:
        payload["migrate_tags"] = state["migrate_tags"]
    sys.stdout.write(json.dumps(payload, sort_keys=True) + "\n")


def acquire(state_path: Path, lock_path: Path, locked_by: str) -> None:
    with with_lock(lock_path):
        state = read_state(state_path)
        locked_at = state.get("locked_at", "")
        current_locked_by = state.get("locked_by", "")
        if locked_at:
            raise SystemExit(f"Remote Ansible state is locked since {locked_at} by {current_locked_by}")
        state["locked_at"] = dt.datetime.now(REMOTE_STATE_UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")
        state["locked_by"] = locked_by
        write_state(state_path, state)
        emit(state)


def release(state_path: Path, lock_path: Path, locked_by: str) -> None:
    with with_lock(lock_path):
        state = read_state(state_path)
        if state.get("locked_by", "") == locked_by:
            state.pop("locked_at", None)
            state.pop("locked_by", None)
            write_state(state_path, state)
        emit(state)


def unlock(state_path: Path, lock_path: Path) -> None:
    with with_lock(lock_path):
        state = read_state(state_path)
        state.pop("locked_at", None)
        state.pop("locked_by", None)
        write_state(state_path, state)
        emit(state)


def mark(state_path: Path, lock_path: Path, migrate_tag: str) -> None:
    with with_lock(lock_path):
        state = read_state(state_path)
        current = state.get("migrate_tag", "")
        if not isinstance(current, str):
            raise SystemExit("Invalid remote Ansible state key migrate_tag: expected string")
        migrate_tags = state.get("migrate_tags", [])
        if not isinstance(migrate_tags, list) or not all(isinstance(tag, str) for tag in migrate_tags):
            raise SystemExit("Invalid remote Ansible state key migrate_tags: expected list of strings")
        next_tags = sorted({*migrate_tags, migrate_tag})
        state["migrate_tags"] = next_tags
        state["migrate_tag"] = max([current, *next_tags])
        write_state(state_path, state)
        emit(state)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--namespace", required=True)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("get")
    acquire_parser = subparsers.add_parser("acquire")
    acquire_parser.add_argument("--locked-by", required=True)
    release_parser = subparsers.add_parser("release")
    release_parser.add_argument("--locked-by", required=True)
    subparsers.add_parser("unlock")
    mark_parser = subparsers.add_parser("mark")
    mark_parser.add_argument("--migrate-tag", required=True)
    args = parser.parse_args()
    state_path, lock_path = state_paths(args.namespace)

    if args.command == "get":
        emit(read_state(state_path))
    elif args.command == "acquire":
        acquire(state_path, lock_path, args.locked_by)
    elif args.command == "release":
        release(state_path, lock_path, args.locked_by)
    elif args.command == "unlock":
        unlock(state_path, lock_path)
    elif args.command == "mark":
        mark(state_path, lock_path, args.migrate_tag)
    else:
        raise SystemExit(f"Unsupported command: {args.command}")


if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        sys.exit(1)
