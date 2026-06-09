from __future__ import annotations

import re
from pathlib import Path
from typing import cast

import yaml


REPO_ROOT = Path(__file__).resolve().parents[2]
RUNTIME_DIR = REPO_ROOT / "roles" / "runtime"


def _load_tasks(path: Path) -> list[dict[str, object]]:
    tasks = yaml.safe_load(path.read_text(encoding="utf-8"))
    return tasks if isinstance(tasks, list) else []


def _runtime_task_paths() -> list[Path]:
    return sorted((RUNTIME_DIR / "tasks").glob("*.yml"))


def _runtime_tasks_text() -> str:
    return "\n".join(path.read_text(encoding="utf-8") for path in _runtime_task_paths())


def _runtime_task_by_name(name: str) -> dict[str, object]:
    return next(task for path in _runtime_task_paths() for task in _load_tasks(path) if task.get("name") == name)


def test_runtime_unit_docker_secret_names_are_timetagged_and_hashed() -> None:
    tasks_text = _runtime_tasks_text()

    assert (
        "runtime_unit_secret_prefix: '{{ item.app }}-{{ runtime_cluster_realm }}-{{ item.env }}-{{ item.unit }}'"
        in tasks_text
    )
    assert (
        "runtime_unit_secret_name: '{{ runtime_unit_secret_prefix }}-{{ runtime_unit_secret_timetag.stdout }}-{{ runtime_unit_secret_hash }}'"
        in tasks_text
    )
    assert "date -u +%y%m%d%H%M%S" in tasks_text
    assert "hash('sha256'))[:12]" in tasks_text
    assert re.search(r"\[0-9\]\{12\}.*\[0-9a-f\]\{12\}", tasks_text) is not None


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
        "List runtime unit Docker secrets",
        "Capture runtime unit Docker secret timetag",
        "Create runtime unit Docker secrets",
    ):
        assert _runtime_task_by_name(task_name).get("no_log") == "{{ runtime_nolog }}"


def test_runtime_unit_docker_secret_creation_does_not_force_recreate_stable_names() -> None:
    create_task = _runtime_task_by_name("Create runtime unit Docker secrets")
    module = cast("dict[str, object]", create_task["community.docker.docker_secret"])

    assert module["name"] == "{{ runtime_unit_secret_name }}"
    assert "force" not in module


def test_runtime_validates_unit_docker_secret_definitions() -> None:
    validate_text = (RUNTIME_DIR / "tasks" / "validate.yml").read_text(encoding="utf-8")
    vars_text = (RUNTIME_DIR / "vars" / "main.yml").read_text(encoding="utf-8")

    assert "runtime_unit_secret_items" in vars_text
    assert "Validate runtime unit Docker secret definitions" in validate_text
    assert "Each runtime unit Docker secret must define app, env, unit, and secrets mapping." in validate_text


def test_runtime_validates_unit_docker_secret_variables() -> None:
    validate_text = (RUNTIME_DIR / "tasks" / "validate.yml").read_text(encoding="utf-8")

    assert "Validate runtime unit Docker secret variables" in validate_text
    assert "select('match', '^[A-Za-z_][A-Za-z0-9_]*$')" in validate_text
    assert "item.secrets.values() | select('mapping') | list | length == 0" in validate_text
    assert "item.secrets.values() | select('sequence') | reject('string') | list | length == 0" in validate_text
