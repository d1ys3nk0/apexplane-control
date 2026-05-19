from __future__ import annotations

from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[2]


def test_main_task_includes_use_setup_prefix() -> None:
    errors: list[str] = []

    for main_path in sorted((REPO_ROOT / "roles").glob("*/tasks/main.yml")):
        tasks = yaml.safe_load(main_path.read_text(encoding="utf-8")) or []
        for task in tasks:
            include_file = task.get("ansible.builtin.include_tasks") if isinstance(task, dict) else None
            if (
                not isinstance(include_file, str)
                or include_file in {"validate.yml", "{{ role_path }}/tasks/validate.yml"}
                or include_file.startswith("setup_")
            ):
                continue
            errors.append(f"{main_path.relative_to(REPO_ROOT)}: include {include_file} must use setup_*.yml")

    assert errors == []
