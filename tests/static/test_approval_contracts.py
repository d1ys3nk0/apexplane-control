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


def task_when_rejects_invalid_typed_approval(task: Mapping[str, object]) -> bool:
    when_values = task_when_values(task)
    return any(
        "user_input" in when_value and "default" in when_value and "!= ''" in when_value for when_value in when_values
    ) and any(
        "user_input" in when_value and "default" in when_value and "lower != 'yes'" in when_value
        for when_value in when_values
    )


def role_defaults(role_name: str) -> Mapping[str, object]:
    defaults = load_yaml(REPO_ROOT / "roles" / role_name / "defaults" / "main.yml")
    return cast("Mapping[str, object]", defaults) if isinstance(defaults, Mapping) else {}


def role_vars(role_name: str) -> Mapping[str, object]:
    vars_path = REPO_ROOT / "roles" / role_name / "vars" / "main.yml"
    if not vars_path.exists():
        return {}
    variables = load_yaml(vars_path)
    return cast("Mapping[str, object]", variables) if isinstance(variables, Mapping) else {}


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
        variables = role_vars(role_name)
        tasks = role_tasks(role_name)
        vars_text = "\n".join(str(value) for value in variables.values())

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
            and task_when_rejects_invalid_typed_approval(task)
            and task_when_contains(task, f"not ({yes_mode} | bool)")
            for task in tasks
        ), f"{role_name} must reject non-empty destructive approval values other than yes"
        assert yes_mode in vars_text
        assert "user_input" in vars_text
        assert "lower" in vars_text
        assert "== 'yes'" in vars_text
