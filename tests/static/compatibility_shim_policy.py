from __future__ import annotations

import re
from typing import TYPE_CHECKING, cast

import yaml


if TYPE_CHECKING:
    from collections.abc import Iterator
    from pathlib import Path


MIGRATION_PLAYBOOK_PARTS_COUNT = 3
SCAN_DIRS = ("playbooks", "roles", "variables")
YAML_SUFFIXES = {".yml", ".yaml"}
MIGRATION_PLAYBOOK_RE = re.compile(r"^_[0-9]{12}_[a-z0-9_]+\.yml$")
SHIM_MARKER_RE = re.compile(r"(?:^|_)(?:legacy|deprecated|compat|compatibility|old)(?:_|$)")
ALIAS_KEY_RE = re.compile(
    r"(?:legacy|deprecated|compat|compatibility|backward_compat).*aliases?"
    r"|aliases?.*(?:legacy|deprecated|compat|compatibility|backward_compat)"
)
JINJA_BLOCK_RE = re.compile(r"{{(?P<expression>.*?)}}", re.DOTALL)
QUOTED_STRING_RE = re.compile(r"""'(?:\\.|[^'])*'|"(?:\\.|[^"])*" """.strip())
VAR_NAME_RE = re.compile(r"(?<![.\w])(?P<name>[A-Za-z_][A-Za-z0-9_]*)\b")


def _rel_path(path: Path, repo_root: Path) -> str:
    return path.relative_to(repo_root).as_posix()


def _load_yaml(path: Path) -> object | None:
    try:
        return yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError:
        return None


def _is_migration_playbook(path: Path, repo_root: Path) -> bool:
    try:
        relative = path.relative_to(repo_root)
    except ValueError:
        return False

    return (
        len(relative.parts) == MIGRATION_PLAYBOOK_PARTS_COUNT
        and relative.parts[0] == "playbooks"
        and MIGRATION_PLAYBOOK_RE.fullmatch(path.name) is not None
    )


def _iter_yaml_files(repo_root: Path) -> Iterator[Path]:
    for dirname in SCAN_DIRS:
        directory = repo_root / dirname
        if not directory.is_dir():
            continue

        for path in sorted(directory.rglob("*")):
            if path.suffix in YAML_SUFFIXES and not _is_migration_playbook(path, repo_root):
                yield path


def _iter_keys_and_values(value: object) -> Iterator[tuple[str | None, object]]:
    if isinstance(value, dict):
        for raw_key, raw_value in cast("dict[object, object]", value).items():
            key = raw_key if isinstance(raw_key, str) else None
            yield key, raw_value
            yield from _iter_keys_and_values(raw_value)
    elif isinstance(value, list):
        for item in value:
            yield from _iter_keys_and_values(item)


def _shim_variable_names(expression: str) -> list[str]:
    without_strings = QUOTED_STRING_RE.sub("", expression)
    return sorted(
        {
            match.group("name")
            for match in VAR_NAME_RE.finditer(without_strings)
            if SHIM_MARKER_RE.search(match.group("name"))
        }
    )


def _compatibility_expression_references(value: str) -> list[str]:
    references: set[str] = set()
    for block in JINJA_BLOCK_RE.finditer(value):
        expression = block.group("expression")
        shim_names = _shim_variable_names(expression)
        if not shim_names:
            continue
        if "| default" in expression or " is defined" in expression or " is not defined" in expression:
            references.update(shim_names)

    return sorted(references)


def run(repo_root: Path) -> list[str]:
    errors: list[str] = []

    for path in _iter_yaml_files(repo_root):
        data = _load_yaml(path)
        if data is None:
            continue

        rel_path = _rel_path(path, repo_root)
        for key, value in _iter_keys_and_values(data):
            if key is not None and ALIAS_KEY_RE.search(key):
                errors.append(f"{rel_path}: compatibility alias key is not allowed: {key}")

            if not isinstance(value, str):
                continue

            references = _compatibility_expression_references(value)
            if references:
                errors.append(f"{rel_path}: compatibility fallback expression is not allowed: {', '.join(references)}")

    return errors
