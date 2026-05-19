from __future__ import annotations

import re
from collections.abc import Mapping
from typing import TYPE_CHECKING, cast

import yaml


if TYPE_CHECKING:
    from pathlib import Path


ROLE_COMMENT_RE = re.compile(r"^# Role: (?P<name>[a-z][a-z0-9_]*[a-z0-9])$")
YAML_SUFFIXES = {".yml", ".yaml"}
SKIPPED_VARIABLE_FILES = {"_global.yml", "_shared.yml", "_vault.yml"}


def _rel_path(path: Path, repo_root: Path) -> str:
    return str(path.relative_to(repo_root))


def _load_yaml(path: Path) -> object | None:
    try:
        return yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError:
        return None


def _cluster_name_for_variable_file(path: Path, variables_dir: Path) -> str | None:
    if path.name in SKIPPED_VARIABLE_FILES:
        return None

    rel_path = path.relative_to(variables_dir)
    if len(rel_path.parts) not in {1, 2}:
        return None

    return path.stem


def _setup_role_names(setup_path: Path) -> set[str]:
    data = _load_yaml(setup_path)
    if not isinstance(data, list):
        return set()

    role_names: set[str] = set()
    for play in data:
        if not isinstance(play, Mapping):
            continue

        roles = cast("Mapping[object, object]", play).get("roles")
        if not isinstance(roles, list):
            continue

        for role in roles:
            if isinstance(role, str):
                role_names.add(role)
            elif isinstance(role, Mapping):
                role_name = cast("Mapping[object, object]", role).get("role")
                if isinstance(role_name, str):
                    role_names.add(role_name)

    return role_names


def _role_blocks(path: Path) -> list[tuple[int, str]]:
    blocks: list[tuple[int, str]] = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        match = ROLE_COMMENT_RE.fullmatch(line)
        if match is not None:
            blocks.append((line_number, match.group("name")))
    return blocks


def run(*, repo_root: Path, **_kwargs: object) -> list[str]:
    variables_dir = repo_root / "variables"
    playbooks_dir = repo_root / "playbooks"
    if not variables_dir.is_dir() or not playbooks_dir.is_dir():
        return []

    errors: list[str] = []
    setup_roles_by_cluster: dict[str, set[str]] = {}
    for path in sorted(variables_dir.rglob("*")):
        if not path.is_file() or path.suffix not in YAML_SUFFIXES:
            continue

        cluster_name = _cluster_name_for_variable_file(path, variables_dir)
        if cluster_name is None:
            continue

        setup_path = playbooks_dir / cluster_name / "setup.yml"
        if not setup_path.is_file():
            continue

        setup_roles = setup_roles_by_cluster.setdefault(cluster_name, _setup_role_names(setup_path))
        for line_number, role_name in _role_blocks(path):
            if role_name in setup_roles:
                continue

            errors.append(
                f"{_rel_path(path, repo_root)}:{line_number}: role variable block {role_name} "
                f"is not used by {_rel_path(setup_path, repo_root)}"
            )

    return errors
