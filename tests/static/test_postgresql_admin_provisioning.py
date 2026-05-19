from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml


REPO_ROOT = Path(__file__).resolve().parents[2]
POSTGRESQL_MODULES = {
    "community.postgresql.postgresql_db",
    "community.postgresql.postgresql_privs",
    "community.postgresql.postgresql_user",
}
REQUIRED_ADMIN_CREDENTIAL_ROLES = {"docker_postgres"}


def _load_tasks(path: Path) -> list[dict[str, Any]]:
    if not path.is_file():
        return []
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    if data is None:
        return []
    assert isinstance(data, list)
    return data


def _load_mapping(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    if data is None:
        return {}
    assert isinstance(data, dict)
    return data


def _text(value: object) -> str:
    if isinstance(value, list):
        return "\n".join(str(item) for item in value)
    return str(value)


def _has_postgresql_module(task: dict[str, Any]) -> bool:
    return any(module in task for module in POSTGRESQL_MODULES)


def _task_has_admin_gate(task: dict[str, Any], role_name: str) -> bool:
    when = _text(task.get("when", ""))
    return f"{role_name}_pg_provision_enabled | bool" in when or (
        f"{role_name}_pg_admin_user | string | length > 0" in when
        and f"{role_name}_pg_admin_pass | string | length > 0" in when
    )


def test_postgresql_admin_credentials_default_to_empty_string() -> None:
    errors: list[str] = []

    for defaults_path in sorted((REPO_ROOT / "roles").glob("*/defaults/main.yml")):
        role_name = defaults_path.parents[1].name
        if role_name in REQUIRED_ADMIN_CREDENTIAL_ROLES:
            continue
        defaults = _load_mapping(defaults_path)
        errors.extend(
            f"{defaults_path.relative_to(REPO_ROOT)}: {key} must default to empty string"
            for key in sorted(defaults)
            if key.endswith(("_pg_admin_user", "_pg_admin_pass")) and defaults[key] != ""
        )

    assert errors == []


def test_docker_postgres_admin_credentials_are_required() -> None:
    defaults_path = REPO_ROOT / "roles/docker_postgres/defaults/main.yml"
    validate_path = REPO_ROOT / "roles/docker_postgres/tasks/validate.yml"
    defaults = _load_mapping(defaults_path)
    validate_text = validate_path.read_text(encoding="utf-8")

    assert defaults["docker_postgres_pg_admin_user"] is None
    assert defaults["docker_postgres_pg_admin_pass"] is None
    assert "docker_postgres_pg_admin_user is not none" in validate_text
    assert "docker_postgres_pg_admin_user | string | length > 0" in validate_text
    assert "docker_postgres_pg_admin_pass is not none" in validate_text
    assert "docker_postgres_pg_admin_pass | string | length > 0" in validate_text


def test_postgresql_resource_tasks_are_gated_by_admin_credentials() -> None:
    errors: list[str] = []

    for role_dir in sorted(path for path in (REPO_ROOT / "roles").iterdir() if path.is_dir()):
        role_name = role_dir.name
        if role_name in REQUIRED_ADMIN_CREDENTIAL_ROLES:
            continue
        vars_text = (
            (role_dir / "vars/main.yml").read_text(encoding="utf-8") if (role_dir / "vars/main.yml").is_file() else ""
        )
        main_tasks = _load_tasks(role_dir / "tasks/main.yml")
        gated_postgresql_includes = {
            task["ansible.builtin.include_tasks"]
            for task in main_tasks
            if task.get("ansible.builtin.include_tasks") == "setup_postgresql.yml"
            and f"{role_name}_pg_provision_enabled | bool" in _text(task.get("when", ""))
        }

        if gated_postgresql_includes and (
            f"{role_name}_pg_admin_user | string | length > 0" not in vars_text
            or f"{role_name}_pg_admin_pass | string | length > 0" not in vars_text
        ):
            errors.append(
                f"{(role_dir / 'vars/main.yml').relative_to(REPO_ROOT)}: define {role_name}_pg_provision_enabled from pg_admin_user and pg_admin_pass"
            )

        for tasks_path in sorted((role_dir / "tasks").glob("*.yml")):
            for task in _load_tasks(tasks_path):
                if not _has_postgresql_module(task):
                    continue
                if tasks_path.name in gated_postgresql_includes:
                    continue
                if not _task_has_admin_gate(task, role_name):
                    errors.append(
                        f"{tasks_path.relative_to(REPO_ROOT)}: gate {task.get('name', '<unnamed>')} on non-empty pg_admin_user and pg_admin_pass"
                    )

    assert errors == []
