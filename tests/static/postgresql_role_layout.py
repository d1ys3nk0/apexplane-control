from __future__ import annotations

import re
from typing import TYPE_CHECKING


if TYPE_CHECKING:
    from pathlib import Path


POSTGRES_TASK_RE = re.compile(r"\b(?:(?:setup_)?postgres(?:ql)?|postgres_(?:env|provision))\.yml\b")


def _rel_path(path: Path, repo_root: Path) -> str:
    return str(path.relative_to(repo_root))


def _main_includes_postgresql(main_path: Path) -> bool:
    main_text = main_path.read_text(encoding="utf-8")
    return (
        "include_tasks: setup_postgresql.yml" in main_text
        or "include_tasks: postgres.yml" in main_text
        or ("include_tasks: postgres_env.yml" in main_text and "include_tasks: postgres_provision.yml" in main_text)
    )


def _is_postgresql_role(role_dir: Path) -> bool:
    tasks_dir = role_dir / "tasks"
    main_path = tasks_dir / "main.yml"
    return (
        (tasks_dir / "setup_postgresql.yml").exists()
        or (tasks_dir / "postgresql.yml").exists()
        or (tasks_dir / "postgres.yml").exists()
        or (tasks_dir / "postgres_env.yml").exists()
        or (tasks_dir / "postgres_provision.yml").exists()
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
        postgres_path = tasks_dir / "postgres.yml"
        postgres_env_path = tasks_dir / "postgres_env.yml"
        postgres_provision_path = tasks_dir / "postgres_provision.yml"
        legacy_postgresql_path = tasks_dir / "postgresql.yml"

        if legacy_postgresql_path.exists():
            errors.append(
                f"{_rel_path(legacy_postgresql_path, repo_root)}: use tasks/postgres.yml, split postgres_*.yml, or tasks/setup_postgresql.yml"
            )

        has_split_postgres = postgres_env_path.is_file() and postgres_provision_path.is_file()
        if not postgresql_path.is_file() and not postgres_path.is_file() and not has_split_postgres:
            errors.append(
                f"{_rel_path(postgresql_path, repo_root)}, {_rel_path(postgres_path, repo_root)}, or split postgres_*.yml: expected PostgreSQL task file"
            )

        if not main_path.is_file():
            errors.append(f"{_rel_path(main_path, repo_root)}: expected role main task file")
        elif not _main_includes_postgresql(main_path):
            errors.append(
                f"{_rel_path(main_path, repo_root)}: must include tasks/postgres.yml, split postgres_*.yml, or tasks/setup_postgresql.yml"
            )

    return errors
