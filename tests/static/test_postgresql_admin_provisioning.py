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
