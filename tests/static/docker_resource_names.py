from __future__ import annotations

import re
from typing import TYPE_CHECKING


if TYPE_CHECKING:
    from pathlib import Path


RESOURCE_PATTERNS = (
    re.compile(r"^\s+name:\s+(?P<name>[a-z0-9][a-z0-9_-]*_[a-z0-9_-]*)\s*$"),
    re.compile(r"^\s+-\s+(?P<name>[a-z0-9][a-z0-9_-]*_[a-z0-9_-]*):/"),
    re.compile(r"^\s+source:\s+(?P<name>[a-z0-9][a-z0-9_-]*_[a-z0-9_-]*)\s*$"),
    re.compile(
        r"^\s*[a-z0-9_]+_(?:container_name|data_volume|network):\s+(?P<name>[a-z0-9][a-z0-9_-]*_[a-z0-9_-]*)\s*$"
    ),
    re.compile(r"default\('(?P<name>[a-z0-9][a-z0-9_-]*_[a-z0-9_-]*)"),
    re.compile(r"-v\s+(?P<name>[a-z0-9][a-z0-9_-]*_[a-z0-9_-]*):"),
)
NON_DOCKER_ROLE_DATA_DIRS = {("docker_grafana", "files", "dashboards")}


def _candidate_files(repo_root: Path) -> list[Path]:
    return sorted(
        path
        for role_dir in (repo_root / "roles").glob("docker*")
        for path in role_dir.rglob("*")
        if path.is_file()
        and path.suffix in {".yml", ".yaml", ".j2"}
        and (role_dir.name, *path.relative_to(role_dir).parts[:-1]) not in NON_DOCKER_ROLE_DATA_DIRS
    )


def run(repo_root: Path) -> list[str]:
    errors: list[str] = []

    for path in _candidate_files(repo_root):
        relative_path = path.relative_to(repo_root)
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            for pattern in RESOURCE_PATTERNS:
                match = pattern.search(line)
                if match:
                    name = match.group("name")
                    errors.append(
                        f"{relative_path}:{line_number}: Docker resource name {name} must use hyphens, not underscores"
                    )
                    break

    return errors
