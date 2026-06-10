from __future__ import annotations

from pathlib import Path
from typing import cast

import yaml


REPO_ROOT = Path(__file__).resolve().parents[2]
RUNTIME_DIR = REPO_ROOT / "roles" / "runtime"
TOOLBOX_DIR = REPO_ROOT / "roles" / "toolbox"


def _load_tasks(path: Path) -> list[dict[str, object]]:
    tasks = yaml.safe_load(path.read_text(encoding="utf-8"))
    return tasks if isinstance(tasks, list) else []


def _iter_tasks(value: object) -> list[dict[str, object]]:
    if isinstance(value, list):
        return [nested for item in value for nested in _iter_tasks(item)]
    if not isinstance(value, dict):
        return []

    task = cast("dict[str, object]", value)
    return [task, *[nested for key in ("block", "rescue", "always") for nested in _iter_tasks(task.get(key))]]


def _runtime_task_paths() -> list[Path]:
    return sorted((RUNTIME_DIR / "tasks").glob("*.yml"))


def _runtime_tasks_text() -> str:
    return "\n".join(path.read_text(encoding="utf-8") for path in _runtime_task_paths())


def _runtime_task_by_name(name: str) -> dict[str, object]:
    return next(
        task for path in _runtime_task_paths() for task in _iter_tasks(_load_tasks(path)) if task.get("name") == name
    )


def test_runtime_secret_dotenv_defaults_are_disabled() -> None:
    defaults = yaml.safe_load((RUNTIME_DIR / "defaults" / "main.yml").read_text(encoding="utf-8"))

    assert defaults["runtime_secrets_dotenv"] is False
    assert defaults["runtime_docker_secret_manager_path"] == "/opt/toolbox/bin/docker_secret_manager"  # noqa: S105


def test_runtime_unit_docker_secret_tasks_use_nolog() -> None:
    for task_name in (
        "Render temporary runtime unit secret dotenv file",
        "Render runtime unit secret dotenv file",
        "Upsert runtime unit Docker secret",
    ):
        assert _runtime_task_by_name(task_name).get("no_log") == "{{ runtime_nolog }}"
