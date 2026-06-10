from __future__ import annotations

import re
from pathlib import Path
from typing import TYPE_CHECKING, cast

import yaml


if TYPE_CHECKING:
    from collections.abc import Iterator


REPO_ROOT = Path(__file__).resolve().parents[2]
FEATURE_DOMAIN_TASK_FILE_RE = re.compile(r"^[a-z][a-z0-9]*\.yml$")
TASK_LEVEL_KEYS = {
    "action",
    "always",
    "args",
    "block",
    "collections",
    "connection",
    "delay",
    "environment",
    "name",
    "poll",
    "remote_user",
    "rescue",
    "retries",
    "timeout",
    "vars",
}
TASK_CONTROL_KEYS = {
    "become",
    "become_user",
    "changed_when",
    "check_mode",
    "delegate_facts",
    "delegate_to",
    "diff",
    "failed_when",
    "ignore_errors",
    "ignore_unreachable",
    "loop",
    "loop_control",
    "no_log",
    "notify",
    "register",
    "run_once",
    "tags",
    "throttle",
    "until",
    "when",
}


def _iter_tasks(value: object) -> Iterator[dict[object, object]]:
    if isinstance(value, list):
        for item in value:
            yield from _iter_tasks(item)
        return
    if not isinstance(value, dict):
        return

    task = cast("dict[object, object]", value)
    yield task
    for nested_key in ("block", "rescue", "always"):
        yield from _iter_tasks(task.get(nested_key))


def test_main_task_includes_use_setup_prefix() -> None:
    errors: list[str] = []
    allowed_lifecycle_files = {"dr.yml", "validate.yml", "verify.yml", "{{ role_path }}/tasks/validate.yml"}

    for main_path in sorted((REPO_ROOT / "roles").glob("*/tasks/main.yml")):
        tasks = yaml.safe_load(main_path.read_text(encoding="utf-8")) or []
        for task in tasks:
            include_file = task.get("ansible.builtin.include_tasks") if isinstance(task, dict) else None
            if (
                not isinstance(include_file, str)
                or include_file in allowed_lifecycle_files
                or FEATURE_DOMAIN_TASK_FILE_RE.fullmatch(include_file) is not None
                or include_file.startswith("setup")
            ):
                continue
            errors.append(
                f"{main_path.relative_to(REPO_ROOT)}: include {include_file} must use setup_*.yml or <domain>.yml"
            )

    assert errors == []


def test_subdomain_task_files_are_included_by_domain_entrypoints() -> None:
    errors: list[str] = []
    lifecycle_files = {"dr.yml", "validate.yml", "verify.yml", "{{ role_path }}/tasks/validate.yml"}

    for main_path in sorted((REPO_ROOT / "roles").glob("*/tasks/main.yml")):
        tasks = yaml.safe_load(main_path.read_text(encoding="utf-8")) or []
        for task in tasks:
            include_file = task.get("ansible.builtin.include_tasks") if isinstance(task, dict) else None
            if not isinstance(include_file, str) or include_file in lifecycle_files or include_file.startswith("setup"):
                continue
            if FEATURE_DOMAIN_TASK_FILE_RE.fullmatch(include_file) is not None:
                continue
            errors.append(
                f"{main_path.relative_to(REPO_ROOT)}: include {include_file} must be included by its <domain>.yml entrypoint"
            )

    for task_path in sorted((REPO_ROOT / "roles").glob("*/tasks/[a-z]*_[a-z]*.yml")):
        if task_path.name.startswith("setup_"):
            continue
        domain = task_path.name.removesuffix(".yml").split("_", 1)[0]
        domain_path = task_path.with_name(f"{domain}.yml")
        if not domain_path.is_file():
            errors.append(f"{task_path.relative_to(REPO_ROOT)}: expected sibling {domain_path.name} domain entrypoint")
            continue
        domain_text = domain_path.read_text(encoding="utf-8")
        if f"include_tasks: {task_path.name}" not in domain_text:
            errors.append(
                f"{task_path.relative_to(REPO_ROOT)}: expected {domain_path.relative_to(REPO_ROOT)} to include it"
            )

    assert errors == []


def test_main_task_verification_includes_use_verify_entrypoint() -> None:
    errors: list[str] = []
    verification_terms = ("health", "readiness", "ready", "verify")

    for main_path in sorted((REPO_ROOT / "roles").glob("*/tasks/main.yml")):
        tasks = yaml.safe_load(main_path.read_text(encoding="utf-8")) or []
        for task in tasks:
            if not isinstance(task, dict):
                continue
            include_file = task.get("ansible.builtin.include_tasks")
            task_name = task.get("name", "")
            if not isinstance(include_file, str) or include_file == "verify.yml":
                continue
            include_text = f"{task_name} {include_file}".lower()
            if not any(term in include_text for term in verification_terms):
                continue
            errors.append(
                f"{main_path.relative_to(REPO_ROOT)}: verification include {include_file} must use verify.yml"
            )

    assert errors == []


def test_roles_use_single_validate_task_file() -> None:
    errors = [
        f"{path.relative_to(REPO_ROOT)}: merge validation into tasks/validate.yml"
        for path in sorted((REPO_ROOT / "roles").glob("*/tasks/validate_*.yml"))
    ]

    assert errors == []


def test_task_control_keys_are_not_nested_in_module_arguments() -> None:
    errors: list[str] = []
    task_keywords = TASK_LEVEL_KEYS | TASK_CONTROL_KEYS

    for path in sorted((REPO_ROOT / "roles").glob("**/tasks/*.yml")):
        tasks = yaml.safe_load(path.read_text(encoding="utf-8")) or []
        for task in _iter_tasks(tasks):
            for key, value in task.items():
                if key in task_keywords or not isinstance(value, dict):
                    continue
                nested_control_keys = sorted(TASK_CONTROL_KEYS & set(value))
                if not nested_control_keys:
                    continue
                task_name = task.get("name", "<unnamed>")
                nested_keys = ", ".join(nested_control_keys)
                errors.append(f"{path.relative_to(REPO_ROOT)}: {task_name}: move {nested_keys} out of {key}")

    assert errors == []
