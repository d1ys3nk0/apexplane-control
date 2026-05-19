from __future__ import annotations

import re
from typing import TYPE_CHECKING


if TYPE_CHECKING:
    from pathlib import Path


POSTGRES_TASK_RE = re.compile(r"\b(?:setup_)?postgres(?:ql)?\.yml\b")


def _rel_path(path: Path, repo_root: Path) -> str:
    return str(path.relative_to(repo_root))


def _main_includes_postgresql(main_path: Path) -> bool:
    return "include_tasks: setup_postgresql.yml" in main_path.read_text(encoding="utf-8")


def _is_postgresql_role(role_dir: Path) -> bool:
    tasks_dir = role_dir / "tasks"
    main_path = tasks_dir / "main.yml"
    return (
        (tasks_dir / "setup_postgresql.yml").exists()
        or (tasks_dir / "postgresql.yml").exists()
        or (tasks_dir / "postgres.yml").exists()
        or (main_path.is_file() and POSTGRES_TASK_RE.search(main_path.read_text(encoding="utf-8")) is not None)
    )


def run(*, repo_root: Path, **_kwargs: object) -> list[str]:
    errors: list[str] = []
    roles_dir = repo_root / "roles"
    if not roles_dir.is_dir():
        return []

    for role_dir in sorted(path for path in roles_dir.iterdir() if path.is_dir()):
        if not _is_postgresql_role(role_dir):
            continue
        tasks_dir = role_dir / "tasks"
        main_path = tasks_dir / "main.yml"
        postgresql_path = tasks_dir / "setup_postgresql.yml"
        legacy_postgres_path = tasks_dir / "postgres.yml"
        legacy_postgresql_path = tasks_dir / "postgresql.yml"

        if legacy_postgres_path.exists():
            errors.append(f"{_rel_path(legacy_postgres_path, repo_root)}: use tasks/setup_postgresql.yml")

        if legacy_postgresql_path.exists():
            errors.append(f"{_rel_path(legacy_postgresql_path, repo_root)}: use tasks/setup_postgresql.yml")

        if not postgresql_path.is_file():
            errors.append(f"{_rel_path(postgresql_path, repo_root)}: expected PostgreSQL task file")

        if not main_path.is_file():
            errors.append(f"{_rel_path(main_path, repo_root)}: expected role main task file")
        elif not _main_includes_postgresql(main_path):
            errors.append(f"{_rel_path(main_path, repo_root)}: must include tasks/setup_postgresql.yml")

    return errors
