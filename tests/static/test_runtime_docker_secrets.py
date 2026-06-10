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


def test_runtime_unit_docker_secret_names_are_timetagged_and_hashed() -> None:
    tasks_text = _runtime_tasks_text()
    script_text = (TOOLBOX_DIR / "files" / "scripts" / "docker_secret_manager.sh").read_text(encoding="utf-8")

    assert (
        "runtime_unit_secret_prefix: '{{ item.app }}-{{ runtime_cluster_realm }}-{{ item.env }}-{{ item.unit }}'"
        in tasks_text
    )
    assert 'name="${prefix}-${timetag}-${hash}"' in script_text
    assert "date -u +%y%m%d%H%M%S" in script_text
    assert "sha256sum" in script_text
    assert "substr($1, 1, 12)" in script_text
    assert "^[0-9]{12}$" in script_text
    assert "^[0-9a-f]{12}$" in script_text


def test_runtime_unit_docker_secret_payload_is_canonical_dotenv() -> None:
    tasks_text = _runtime_tasks_text()
    template_text = (RUNTIME_DIR / "templates" / "runtime_secret.env.j2").read_text(encoding="utf-8")

    assert "runtime_secret.env.j2" in tasks_text
    assert "to_json(sort_keys=true)" not in tasks_text
    assert "item.secrets.keys() | sort" in template_text
    assert '{{ runtime_secret_key }}="' in template_text
    assert "replace('\\\\', '\\\\\\\\')" in template_text
    assert "replace('\"', '\\\\\"')" in template_text
    assert "replace('$', '\\\\$')" in template_text
    assert "replace('`', '\\\\`')" in template_text
    assert template_text.endswith("{% endfor %}\n")


def test_runtime_unit_docker_secret_tasks_use_nolog() -> None:
    for task_name in (
        "Render temporary runtime unit secret dotenv file",
        "Render runtime unit secret dotenv file",
        "Upsert runtime unit Docker secret",
    ):
        assert _runtime_task_by_name(task_name).get("no_log") == "{{ runtime_nolog }}"


def test_runtime_unit_docker_secret_creation_does_not_force_recreate_stable_names() -> None:
    tasks_text = _runtime_tasks_text()

    assert "community.docker.docker_secret" not in tasks_text
    assert "docker secret ls" not in tasks_text
    assert "runtime_unit_secret_hash" not in tasks_text
    assert "runtime_docker_secret_manager_path" in tasks_text
    assert "force: false" in tasks_text


def test_runtime_unit_secret_dotenv_file_lifecycle_is_explicit() -> None:
    tasks_text = _runtime_tasks_text()

    assert (
        "runtime_unit_secret_persistent_dotenv_path: '/home/{{ item.app }}/secrets/{{ runtime_cluster_realm }}_{{ item.env }}_{{ item.unit }}.env'"
        in tasks_text
    )
    assert "Create temporary runtime unit secret dotenv file" in tasks_text
    assert "Render temporary runtime unit secret dotenv file" in tasks_text
    assert "Remove temporary runtime unit secret dotenv file" in tasks_text
    assert "when: not runtime_secrets_dotenv | bool" in tasks_text
    assert "Check runtime unit secret persistent dotenv file" in tasks_text
    assert "not runtime_secrets_dotenv | bool or runtime_unit_secret_persistent_dotenv.stat.exists" in tasks_text


def test_runtime_validates_unit_docker_secret_definitions() -> None:
    docker_text = (RUNTIME_DIR / "tasks" / "docker.yml").read_text(encoding="utf-8")
    validate_text = (RUNTIME_DIR / "tasks" / "validate.yml").read_text(encoding="utf-8")
    vars_text = (RUNTIME_DIR / "vars" / "main.yml").read_text(encoding="utf-8")

    assert "runtime_unit_secret_items" in vars_text
    assert "runtime_secrets_dotenv is boolean" in validate_text
    assert "Validate runtime unit Docker secret definitions" in validate_text
    assert "Validate runtime Docker secret manager is installed" in validate_text
    assert "Validate runtime Docker secret manager is installed" not in docker_text
    assert "Each runtime unit Docker secret must define app, env, unit, and secrets mapping." in validate_text


def test_runtime_validates_unit_docker_secret_variables() -> None:
    validate_text = (RUNTIME_DIR / "tasks" / "validate.yml").read_text(encoding="utf-8")

    assert "Validate runtime unit Docker secret variables" in validate_text
    assert "select('match', '^[A-Za-z_][A-Za-z0-9_]*$')" in validate_text
    assert "item.secrets.values() | select('mapping') | list | length == 0" in validate_text
    assert "item.secrets.values() | select('sequence') | reject('string') | list | length == 0" in validate_text
