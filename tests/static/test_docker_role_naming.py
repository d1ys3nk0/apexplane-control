from __future__ import annotations

from collections.abc import Iterator, Mapping
from pathlib import Path
from typing import cast

import yaml


REPO_ROOT = Path(__file__).resolve().parents[2]


def load_yaml(path: Path) -> object:
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def iter_tasks(value: object) -> Iterator[Mapping[str, object]]:
    if isinstance(value, list):
        for item in value:
            yield from iter_tasks(item)
        return
    if not isinstance(value, Mapping):
        return

    task = cast("Mapping[str, object]", value)
    yield task
    for nested_key in ("block", "rescue", "always"):
        yield from iter_tasks(task.get(nested_key))


def rel(path: Path) -> str:
    return str(path.relative_to(REPO_ROOT))


def role_dirs() -> Iterator[Path]:
    roles_dir = REPO_ROOT / "roles"
    yield from sorted(path for path in roles_dir.iterdir() if path.is_dir())


def role_task_paths(role_dir: Path) -> Iterator[Path]:
    tasks_dir = role_dir / "tasks"
    if tasks_dir.is_dir():
        yield from sorted(tasks_dir.glob("*.yml"))
