#!/usr/bin/env python3
"""Check ApexPlane Control contracts in a consuming repository."""

from __future__ import annotations

import re
from collections import Counter, defaultdict
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import cast

import yaml


TOOLKIT_ROOT = Path(__file__).resolve().parent
GV_VARIABLE_PATTERN = re.compile(r"\bgv_[A-Za-z0-9_]+\b")
GV_VARIABLE_DEFINITION_PATTERN = re.compile(r"^(?P<name>gv_[A-Za-z0-9_]+):")
ROLE_BLOCK_RE = re.compile(r"^# Role: (?P<role_name>[A-Za-z0-9_]+)$")
TOP_LEVEL_VAR_RE = re.compile(r"^(?P<name>[A-Za-z_][A-Za-z0-9_]*):")
YAML_KEY_RE = re.compile(r"^(?P<indent>\s*)(?P<name>[A-Za-z_][A-Za-z0-9_]*):")
MINIMUM_GV_REFERENCE_COUNT = 1
SCANNED_GV_DIRS = ("inventories", "playbooks", "roles", "tests", "variables")
SCANNED_GV_SUFFIXES = {".j2", ".py", ".yaml", ".yml"}
EXCLUDED_PARTS = {
    ".cache",
    ".ansible",
    ".git",
    ".mypy_cache",
    ".pytest_cache",
    ".ruff_cache",
    ".tox",
    ".venv",
    "__pycache__",
    "log",
    "tmp",
}


@dataclass(frozen=True)
class RoleDefaults:
    path: Path
    values: Mapping[str, object]


@dataclass(frozen=True)
class RoleVariableOverride:
    path: Path
    line_number: int
    variable_name: str
    variable_value: object
    role_name: str
    role_block: str | None
    defaults: RoleDefaults


def uncommented_lines(path: Path) -> list[str]:
    return [line.split("#", maxsplit=1)[0] for line in path.read_text(encoding="utf-8").splitlines()]


def load_yaml_mapping(path: Path) -> Mapping[str, object]:
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    if data is None:
        return {}
    if not isinstance(data, Mapping):
        return {}
    return cast("Mapping[str, object]", data)


def role_defaults_dirs(repo_root: Path) -> tuple[Path, ...]:
    return (
        repo_root / "roles",
        repo_root / ".ansible/collections/ansible_collections/apexplane/control/roles",
        repo_root.parent / "apexplane-control/roles",
    )


def load_role_defaults(repo_root: Path) -> dict[str, RoleDefaults]:
    defaults: dict[str, RoleDefaults] = {}
    for roles_dir in role_defaults_dirs(repo_root):
        if not roles_dir.is_dir():
            continue
        for role_dir in sorted(path for path in roles_dir.iterdir() if path.is_dir()):
            defaults_path = role_dir / "defaults/main.yml"
            if role_dir.name in defaults or not defaults_path.is_file():
                continue
            defaults[role_dir.name] = RoleDefaults(path=defaults_path, values=load_yaml_mapping(defaults_path))
    return defaults


def line_numbers(path: Path) -> dict[str, int]:
    numbers: dict[str, int] = {}
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        match = TOP_LEVEL_VAR_RE.match(line)
        if match is not None:
            numbers[match.group("name")] = line_number
    return numbers


def role_blocks(path: Path) -> dict[int, str]:
    blocks: dict[int, str] = {}
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        match = ROLE_BLOCK_RE.match(line)
        if match is not None:
            blocks[line_number] = match.group("role_name")
    return blocks


def role_block_for_line(blocks: dict[int, str], line_number: int) -> str | None:
    previous_blocks = [block_line for block_line in blocks if block_line < line_number]
    if not previous_blocks:
        return None
    return blocks[max(previous_blocks)]


def find_role_name(variable_name: str, role_names: list[str]) -> str | None:
    return next((role_name for role_name in role_names if variable_name.startswith(f"{role_name}_")), None)


def display_path(repo_root: Path, path: Path) -> Path:
    try:
        return path.relative_to(repo_root)
    except ValueError:
        return path.relative_to(repo_root.parent)


def role_variable_overrides(repo_root: Path) -> list[RoleVariableOverride]:
    role_defaults = load_role_defaults(repo_root)
    role_names = list(role_defaults)
    role_names.sort(key=len, reverse=True)
    overrides: list[RoleVariableOverride] = []

    for variables_path in sorted((repo_root / "variables").rglob("*.yml")):
        if variables_path.name == "_vault.yml":
            continue
        variables = load_yaml_mapping(variables_path)
        variable_line_numbers = line_numbers(variables_path)
        variable_role_blocks = role_blocks(variables_path)

        for variable_name, variable_value in variables.items():
            role_name = find_role_name(variable_name, role_names)
            if role_name is None:
                continue

            line_number = variable_line_numbers.get(variable_name, 1)
            overrides.append(
                RoleVariableOverride(
                    path=variables_path,
                    line_number=line_number,
                    variable_name=variable_name,
                    variable_value=variable_value,
                    role_name=role_name,
                    role_block=role_block_for_line(variable_role_blocks, line_number),
                    defaults=role_defaults[role_name],
                )
            )

    return overrides


def playbook_role_variable_definitions(repo_root: Path) -> list[tuple[Path, int, str]]:
    role_variable_names = {
        variable_name for defaults in load_role_defaults(repo_root).values() for variable_name in defaults.values
    }
    definitions: list[tuple[Path, int, str]] = []

    for playbook_path in sorted((repo_root / "playbooks").rglob("*.yml")):
        for line_number, line in enumerate(playbook_path.read_text(encoding="utf-8").splitlines(), start=1):
            match = YAML_KEY_RE.match(line.split("#", maxsplit=1)[0])
            if match is not None and match.group("name") in role_variable_names:
                definitions.append((playbook_path, line_number, match.group("name")))

    return definitions


def check_global_variables(repo_root: Path) -> list[str]:
    definitions: dict[str, str] = {}
    counts: Counter[str] = Counter()
    locations: defaultdict[str, list[str]] = defaultdict(list)

    for path in sorted((repo_root / "variables").rglob("*.yml")):
        for line_number, line in enumerate(uncommented_lines(path), start=1):
            match = GV_VARIABLE_DEFINITION_PATTERN.match(line)
            if match is not None and path.name != "_global.yml":
                return [
                    f"{path.relative_to(repo_root)}:{line_number}: {match.group('name')} must be defined in _global.yml"
                ]

    for scanned_dir in SCANNED_GV_DIRS:
        for path in sorted((repo_root / scanned_dir).rglob("*")):
            relative_path = path.relative_to(repo_root)
            if (
                not path.is_file()
                or path.suffix not in SCANNED_GV_SUFFIXES
                or set(relative_path.parts) & EXCLUDED_PARTS
            ):
                continue

            for line_number, line in enumerate(uncommented_lines(path), start=1):
                definition_match = GV_VARIABLE_DEFINITION_PATTERN.match(line)
                defined_variable_name: str | None = None
                if definition_match is not None:
                    defined_variable_name = definition_match.group("name")
                    definitions[defined_variable_name] = f"{relative_path}:{line_number}"

                for match in GV_VARIABLE_PATTERN.finditer(line):
                    variable_name = match.group(0)
                    if variable_name == defined_variable_name:
                        continue
                    counts[variable_name] += 1
                    locations[variable_name].append(f"{relative_path}:{line_number}")

    errors = [
        f"{variable_name}: {', '.join(locations[variable_name])}"
        for variable_name in sorted(counts)
        if variable_name not in definitions
    ]
    errors.extend(
        f"{variable_name}: defined at {definitions[variable_name]}; referenced at {', '.join(locations[variable_name]) or 'none'}"
        for variable_name in sorted(definitions)
        if counts[variable_name] < MINIMUM_GV_REFERENCE_COUNT
    )
    return errors


def check_role_variable_overrides(repo_root: Path) -> list[str]:
    errors: list[str] = []

    for override in role_variable_overrides(repo_root):
        relative_path = override.path.relative_to(repo_root)
        defaults_location = display_path(repo_root, override.defaults.path)
        if override.variable_name not in override.defaults.values:
            errors.append(
                f"{relative_path}:{override.line_number}: {override.variable_name} is not declared in {defaults_location}"
            )
        if override.role_block != override.role_name:
            errors.append(
                f"{relative_path}:{override.line_number}: {override.variable_name} must be under # Role: {override.role_name}"
            )
        if override.path.name == "_global.yml":
            errors.append(
                f"{relative_path}:{override.line_number}: {override.variable_name} must not be defined in _global.yml"
            )

    for variables_path in sorted((repo_root / "variables").rglob("*.yml")):
        if variables_path.name == "_vault.yml":
            continue
        block_counts = Counter(role_blocks(variables_path).values())
        relative_path = variables_path.relative_to(repo_root)
        errors.extend(
            f"{relative_path}: # Role: {role_name} appears {count} times"
            for role_name, count in sorted(block_counts.items())
            if count > 1
        )

    errors.extend(
        f"{path.relative_to(repo_root)}:{line_number}: {variable_name} must be defined in variables/**, not playbooks/**"
        for path, line_number, variable_name in playbook_role_variable_definitions(repo_root)
    )
    return errors
