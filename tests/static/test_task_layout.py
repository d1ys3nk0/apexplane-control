from __future__ import annotations

from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[2]


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
                or include_file.startswith("setup")
            ):
                continue
            errors.append(
                f"{main_path.relative_to(REPO_ROOT)}: include {include_file} must use setup_*.yml or an allowed lifecycle file"
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
