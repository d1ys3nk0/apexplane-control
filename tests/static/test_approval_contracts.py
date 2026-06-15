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


def task_when_values(task: Mapping[str, object]) -> list[str]:
    when = task.get("when")
    if isinstance(when, str):
        return [when]
    if isinstance(when, list):
        return [item for item in when if isinstance(item, str)]
    return []


def task_when_contains(task: Mapping[str, object], *expected_values: str) -> bool:
    when_values = task_when_values(task)
    return all(any(expected_value in when_value for when_value in when_values) for expected_value in expected_values)


def role_defaults(role_name: str) -> Mapping[str, object]:
    defaults = load_yaml(REPO_ROOT / "roles" / role_name / "defaults" / "main.yml")
    return cast("Mapping[str, object]", defaults) if isinstance(defaults, Mapping) else {}


def role_tasks(role_name: str) -> list[Mapping[str, object]]:
    task_dir = REPO_ROOT / "roles" / role_name / "tasks"
    return [task for task_file in sorted(task_dir.glob("*.yml")) for task in iter_tasks(load_yaml(task_file))]


def test_destructive_approval_flows_accept_yes_preapproval() -> None:
    approval_roles = {
        "crontab": "crontab",
        "iam": "iam",
    }

    for role_name, variable_prefix in approval_roles.items():
        yes_mode = f"{variable_prefix}_yes_mode"
        interactive_mode = f"{variable_prefix}_interactive_mode"
        defaults = role_defaults(role_name)
        tasks = role_tasks(role_name)

        assert yes_mode in defaults
        assert any(
            "ansible.builtin.fail" in task
            and task_when_contains(task, f"not ({interactive_mode} | bool)", f"not ({yes_mode} | bool)")
            for task in tasks
        ), f"{role_name} must fail non-interactive destructive changes unless YES is set"
        assert any(
            "ansible.builtin.pause" in task
            and isinstance(task.get("register"), str)
            and task_when_contains(task, f"{interactive_mode} | bool", f"not ({yes_mode} | bool)")
            for task in tasks
        ), f"{role_name} must prompt for destructive changes only when YES is not set"
        assert any(
            "ansible.builtin.fail" in task
            and task_when_contains(task, ".user_input != 'yes'", f"not ({yes_mode} | bool)")
            for task in tasks
        ), f"{role_name} must reject destructive changes without typed approval"
