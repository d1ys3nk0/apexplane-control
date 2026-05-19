from __future__ import annotations

from collections.abc import Iterator, Mapping
from pathlib import Path
from typing import cast

import yaml


REPO_ROOT = Path(__file__).resolve().parents[2]


def _load_taskfile() -> Mapping[str, object]:
    taskfile = yaml.safe_load((REPO_ROOT / "Taskfile.yml").read_text(encoding="utf-8"))
    return cast("Mapping[str, object]", taskfile)


def _task_references(value: object) -> Iterator[str]:
    if isinstance(value, list):
        for item in value:
            yield from _task_references(item)
        return
    if not isinstance(value, Mapping):
        return

    value = cast("Mapping[str, object]", value)
    task_ref = value.get("task")
    if isinstance(task_ref, str):
        yield task_ref

    for nested in value.values():
        yield from _task_references(nested)


def test_taskfile_internal_task_references_exist() -> None:
    taskfile = _load_taskfile()
    tasks = taskfile.get("tasks")
    assert isinstance(tasks, Mapping)

    task_names = set(tasks)
    missing = sorted(ref for ref in _task_references(tasks) if ref not in task_names)

    assert missing == []


def test_collection_build_excludes_shared_docs_and_scripts() -> None:
    galaxy = yaml.safe_load((REPO_ROOT / "galaxy.yml").read_text(encoding="utf-8"))
    build_ignore = galaxy.get("build_ignore")

    assert isinstance(build_ignore, list)
    assert {"docs/shared", "scripts", "tests"}.issubset(set(build_ignore))
