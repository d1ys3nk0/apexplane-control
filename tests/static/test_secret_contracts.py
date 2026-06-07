from __future__ import annotations

import re
from collections.abc import Iterator, Mapping
from pathlib import Path
from typing import cast

import yaml


REPO_ROOT = Path(__file__).resolve().parents[2]
SECRET_NAME_RE = re.compile(r"(?:^|_)(?:pass|password|token|secret|access_key|private_key|masterkey)(?:_|$)")
SECRET_ENV_RE = re.compile(r"(?:PASS|PASSWORD|TOKEN|SECRET|ACCESS_KEY|PRIVATE_KEY|MASTERKEY)")


def _load_yaml(path: Path) -> object:
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def _iter_tasks(value: object) -> Iterator[Mapping[str, object]]:
    if isinstance(value, list):
        for item in value:
            yield from _iter_tasks(item)
        return
    if not isinstance(value, Mapping):
        return

    task = cast("Mapping[str, object]", value)
    yield task
    for nested_key in ("block", "rescue", "always"):
        yield from _iter_tasks(task.get(nested_key))


def _role_defaults(role: str) -> Mapping[str, object]:
    defaults = _load_yaml(REPO_ROOT / "roles" / role / "defaults" / "main.yml")
    return cast("Mapping[str, object]", defaults) if isinstance(defaults, Mapping) else {}


def _role_vars(role: str) -> Mapping[str, object]:
    vars_path = REPO_ROOT / "roles" / role / "vars" / "main.yml"
    if not vars_path.is_file():
        return {}
    role_vars = _load_yaml(vars_path)
    return cast("Mapping[str, object]", role_vars) if isinstance(role_vars, Mapping) else {}


def test_secret_variable_roles_define_nolog_variable() -> None:
    errors: list[str] = []

    for defaults_path in sorted((REPO_ROOT / "roles").glob("*/defaults/main.yml")):
        role = defaults_path.parents[1].name
        defaults = _role_defaults(role)
        role_vars = _role_vars(role)
        has_secret_input = any(isinstance(name, str) and SECRET_NAME_RE.search(name) for name in defaults)
        if has_secret_input and f"{role}_nolog" not in defaults and f"{role}_nolog" not in role_vars:
            errors.append(
                f"{defaults_path.relative_to(REPO_ROOT)}: define {role}_nolog for secret-bearing role in defaults/main.yml or vars/main.yml"
            )

    assert errors == []


def test_container_secret_env_values_are_not_hardcoded() -> None:
    errors: list[str] = []
    module_names = ("community.docker.docker_container", "community.docker.docker_swarm_service")

    for task_path in sorted((REPO_ROOT / "roles").glob("**/tasks/*.yml")):
        for task in _iter_tasks(_load_yaml(task_path)):
            for module_name in module_names:
                module = task.get(module_name)
                if not isinstance(module, Mapping):
                    continue
                module = cast("Mapping[str, object]", module)
                env = module.get("env")
                if not isinstance(env, Mapping):
                    continue
                for key, value in cast("Mapping[str, object]", env).items():
                    key_text = str(key)
                    if key_text.endswith("PASSWORDCHANGEREQUIRED") or SECRET_ENV_RE.search(key_text) is None:
                        continue
                    if isinstance(value, str) and value and "{{" not in value:
                        task_name = task.get("name", "<unnamed>")
                        errors.append(
                            f"{task_path.relative_to(REPO_ROOT)}: {task_name}: {key_text} must use a role variable"
                        )

    assert errors == []


def test_known_secret_tasks_use_role_nolog() -> None:
    expected = {
        ("docker_elastic", "tasks/main.yml", "Start elastic container"),
        ("docker_elastic", "tasks/setup_extra_instance.yml", "Start extra elastic container"),
        ("docker_minio", "tasks/main.yml", "Start MinIO container"),
        ("docker_rabbit", "tasks/main.yml", "Start rabbit container"),
        ("docker_sonarqube", "tasks/main.yml", "Start PostgreSQL container"),
        ("docker_sonarqube", "tasks/main.yml", "Start SonarQube container"),
        ("docker_swarm_gramax", "tasks/main.yml", "Gramax is started in swarm cluster"),
        ("gitlab", "tasks/main.yml", "Update config"),
        ("iam", "tasks/setup_provision_user.yml", "Create provision account"),
        ("iam", "tasks/setup_root_user.yml", "Ensure root user has correct settings and password"),
    }
    errors: list[str] = []

    for role, relative_path, task_name in sorted(expected):
        path = REPO_ROOT / "roles" / role / relative_path
        task = next((item for item in _iter_tasks(_load_yaml(path)) if item.get("name") == task_name), {})
        if task.get("no_log") != f"{{{{ {role}_nolog }}}}":
            errors.append(f"{path.relative_to(REPO_ROOT)}: {task_name}: use no_log: '{{{{ {role}_nolog }}}}'")

    assert errors == []
