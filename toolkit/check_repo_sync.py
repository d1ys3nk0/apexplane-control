#!/usr/bin/env python3
"""Check ApexPlane Control contracts in a consuming repository."""

from __future__ import annotations

import argparse
import re
import sys
from collections import Counter, defaultdict
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING, cast

import yaml


if TYPE_CHECKING:
    from collections.abc import Iterable


TOOLKIT_ROOT = Path(__file__).resolve().parent
GV_VARIABLE_PATTERN = re.compile(r"\bgv_[A-Za-z0-9_]+\b")
GV_VARIABLE_DEFINITION_PATTERN = re.compile(r"^(?P<name>gv_[A-Za-z0-9_]+):")
HOST_NAME_PATTERN = re.compile(
    r"^(?P<realm>[a-z0-9]+)-(?P<platform>[a-z0-9]+)-(?P<cluster>[a-z0-9]+)(?P<index>[0-9]{2})$"
)
ROLE_BLOCK_RE = re.compile(r"^# Role: (?P<role_name>[A-Za-z0-9_]+)$")
TOP_LEVEL_VAR_RE = re.compile(r"^(?P<name>[A-Za-z_][A-Za-z0-9_]*):")
YAML_KEY_RE = re.compile(r"^(?P<indent>\s*)(?P<name>[A-Za-z_][A-Za-z0-9_]*):")
MINIMUM_GV_REFERENCE_COUNT = 1
MAX_SINGLE_LINE_LENGTH = 120
SCANNED_GV_DIRS = ("inventories", "playbooks", "roles", "tests", "variables")
SCANNED_GV_SUFFIXES = {".j2", ".py", ".yaml", ".yml"}
YAML_SUFFIXES = {".yml", ".yaml"}
EXCLUDED_PARTS = {
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

STRUCTURE_PATHS = {
    "Taskfile.yml": (
        r"(?m)^includes:$",
        r"(?m)^\s+root:$",
        r"(?m)^\s+gitlab:$",
        r"(?m)^\s+apc:$",
        r"(?m)^\s+taskfile: \.ansible/collections/ansible_collections/apexplane/control/toolkit/Taskfile\.yml$",
        r"(?m)^\s+optional: true$",
    ),
    ".taskfile/gitlab.yml": (
        r"(?m)^  GIT_TRUNK: main$",
        r"(?m)^  GIT_BRANCH:$",
        r"(?m)^tasks:$",
        r"(?m)^\s+ci:$",
    ),
    ".taskfile/root.yml": (
        r"(?m)^tasks:$",
        r"(?m)^\s+conf:$",
        r"(?m)^\s+check:$",
        r"(?m)^\s+install:$",
        r"(?m)^\s+- task: apc:structure:check$",
    ),
    ".editorconfig": (r"(?m)^root = true$",),
    ".gitignore": (
        r"(?m)^\.venv/$",
        r"(?m)^\.ansible/$",
    ),
    ".gitlab-ci/verify.yml": (
        r"(?m)^\.verify:base:$",
        r"(?m)^\s+stage: verify$",
    ),
    ".pre-commit-config.yaml": (
        r"(?m)^\s+entry: task apc:vault:check --$",
        r"(?m)^\s+entry: task apc:vault:fix --$",
    ),
    "ansible.cfg": (r"(?m)^collections_path = \.ansible/collections(?:[:\n]|$)",),
    "docs/development/local.md": (),
    "docs/reference/ansible-conventions.md": (),
    "docs/reference/inventory.md": (),
    "docs/reference/migrations.md": (),
    "docs/reference/ssh.md": (),
    "docs/reference/topology.md": (),
    "docs/runbooks/bootstrap.md": (),
    "docs/runbooks/panic.md": (),
    "pyproject.toml": (
        r'(?m)^requires-python = ">=3\.13"$',
        r"(?m)^\[tool\.ruff\]$",
    ),
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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Check ApexPlane Control contracts in the current repository.")
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path.cwd(),
        help="target repository root; defaults to the current working directory",
    )

    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("structure-check", help="check target repository structure and shared conventions")
    subparsers.add_parser("list", help="print configured structure paths")

    return parser.parse_args()


def write_line(message: str = "") -> None:
    sys.stdout.write(f"{message}\n")


def missing_patterns(text: str, patterns: Iterable[str]) -> list[str]:
    return [pattern for pattern in patterns if re.search(pattern, text) is None]


def check_structure(repo_root: Path) -> bool:
    ok = True
    for relative_path, patterns in STRUCTURE_PATHS.items():
        path = repo_root / relative_path
        try:
            text = path.read_text(encoding="utf-8")
        except FileNotFoundError:
            write_line(f"{relative_path}: missing")
            ok = False
            continue
        except UnicodeDecodeError as error:
            write_line(f"{relative_path}: cannot decode as UTF-8: {error}")
            ok = False
            continue

        failed_patterns = missing_patterns(text, patterns)
        if failed_patterns:
            write_line(f"{relative_path}: missing {len(failed_patterns)} regex check(s)")
            for pattern in failed_patterns:
                write_line(f"  {pattern}")
            ok = False

    return ok


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


def walk_inventory_groups(node: object) -> list[tuple[str, object]]:
    if not isinstance(node, dict):
        return []
    node_data = cast("dict[str, object]", node)
    children = node_data.get("children")
    if not isinstance(children, dict):
        return []

    groups: list[tuple[str, object]] = []
    for name, child in children.items():
        if isinstance(name, str):
            groups.append((name, child))
        groups.extend(walk_inventory_groups(child))
    return groups


def yaml_files(repo_root: Path) -> list[Path]:
    return sorted(
        path
        for path in repo_root.rglob("*")
        if path.is_file()
        and path.suffix in YAML_SUFFIXES
        and not any(part in EXCLUDED_PARTS for part in path.relative_to(repo_root).parts)
    )


def check_ansible_requirements(repo_root: Path) -> list[str]:
    taskfile = (repo_root / ".taskfile/root.yml").read_text(encoding="utf-8")
    sample = (repo_root / "requirements.sample.yml").read_text(encoding="utf-8")
    gitignore = (repo_root / ".gitignore").read_text(encoding="utf-8")
    errors: list[str] = []

    checks = {
        ".gitignore must ignore requirements.yml": "\nrequirements.yml\n" in f"\n{gitignore}",
        "requirements.local.yml must not exist": not (repo_root / "requirements.local.yml").exists(),
        ".taskfile/root.yml must support APEXPLANE_CONTROL_PATH": "APEXPLANE_CONTROL_PATH" in taskfile,
        ".taskfile/root.yml must preserve existing requirements.yml": "if [ -f requirements.yml ]; then" in taskfile,
        ".taskfile/root.yml must copy requirements.sample.yml to requirements.yml": (
            "requirements.sample.yml requirements.yml" in taskfile
        ),
        ".taskfile/root.yml must install requirements.yml": "ansible-galaxy collection install -r requirements.yml"
        in taskfile,
        ".taskfile/root.yml must not reference requirements.local.yml": "requirements.local.yml" not in taskfile,
        "requirements.sample.yml must use apexplane-control": (
            "https://github.com/d1ys3nk0/apexplane-control.git" in sample
        ),
    }
    errors.extend(message for message, passed in checks.items() if not passed)

    env_sample = repo_root / ".env.sample"
    if env_sample.is_file():
        sample_text = env_sample.read_text(encoding="utf-8")
        checks = {
            ".gitignore must ignore .env": "\n.env\n" in f"\n{gitignore}",
            ".taskfile/root.yml must create .env from .env.sample": "test -f .env || cp .env.sample .env" in taskfile,
            ".env.sample must require explicit ANSIBLE_SSH_USER": "ANSIBLE_SSH_USER=" in sample_text
            and "ANSIBLE_SSH_USER=cicd" not in sample_text,
        }
        errors.extend(message for message, passed in checks.items() if not passed)

    return errors


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


def check_inventory(repo_root: Path) -> list[str]:
    errors: list[str] = []

    for inventory_path in sorted((repo_root / "inventories").glob("*/*.yml")):
        expected_cluster = inventory_path.parent.name
        expected_realm = inventory_path.stem
        inventory = yaml.safe_load(inventory_path.read_text(encoding="utf-8"))
        if not isinstance(inventory, dict):
            errors.append(f"{inventory_path.relative_to(repo_root)} inventory must be a mapping")
            continue

        all_node = inventory.get("all", {})
        if not isinstance(all_node, dict):
            errors.append(f"{inventory_path.relative_to(repo_root)} all group must be a mapping")
            continue

        realm_children = all_node.get("children", {})
        if not isinstance(realm_children, dict) or set(realm_children) != {expected_realm}:
            errors.append(f"{inventory_path.relative_to(repo_root)} realm groups {sorted(realm_children)}")
            continue

        realm_node = realm_children[expected_realm]
        if not isinstance(realm_node, dict):
            errors.append(f"{inventory_path.relative_to(repo_root)} realm group {expected_realm} is not a mapping")
            continue
        platform_children = realm_node.get("children", {})
        if not isinstance(platform_children, dict):
            errors.append(f"{inventory_path.relative_to(repo_root)} realm children must be a mapping")
            continue

        for platform_group, platform_node in platform_children.items():
            if not isinstance(platform_node, dict):
                errors.append(f"{inventory_path.relative_to(repo_root)} group {platform_group} is not a mapping")
                continue

            expected_platform_prefix = f"{expected_realm}_"
            if not platform_group.startswith(expected_platform_prefix):
                errors.append(f"{inventory_path.relative_to(repo_root)} platform group {platform_group}")
                continue

            platform = platform_group.removeprefix(expected_platform_prefix)
            cluster_children = platform_node.get("children", {})
            if not isinstance(cluster_children, dict):
                errors.append(f"{inventory_path.relative_to(repo_root)} platform children must be a mapping")
                continue

            for cluster_group, cluster_node in cluster_children.items():
                if not isinstance(cluster_node, dict):
                    errors.append(f"{inventory_path.relative_to(repo_root)} group {cluster_group} is not a mapping")
                    continue

                expected_cluster_group = f"{expected_realm}_{platform}_{expected_cluster}"
                if cluster_group != expected_cluster_group:
                    errors.append(f"{inventory_path.relative_to(repo_root)} cluster group {cluster_group}")

                hosts = cluster_node.get("hosts", {})
                if not isinstance(hosts, dict):
                    errors.append(f"{inventory_path.relative_to(repo_root)} hosts must be a mapping")
                    continue
                for host_name in hosts:
                    match = HOST_NAME_PATTERN.fullmatch(host_name)
                    if not match:
                        errors.append(f"{inventory_path.relative_to(repo_root)} host {host_name}")
                        continue
                    if match.group("realm") != expected_realm:
                        errors.append(f"{inventory_path.relative_to(repo_root)} host realm {host_name}")
                    if match.group("platform") != platform:
                        errors.append(f"{inventory_path.relative_to(repo_root)} host platform {host_name}")
                    if match.group("cluster") != expected_cluster:
                        errors.append(f"{inventory_path.relative_to(repo_root)} host cluster {host_name}")

        for group_name, group in walk_inventory_groups(inventory):
            if not isinstance(group, dict):
                continue
            group_data = cast("dict[str, object]", group)
            vars_node = group_data.get("vars")
            if not isinstance(vars_node, dict):
                continue
            vars_data = cast("dict[str, object]", vars_node)
            if "iv_jmp_user" in vars_data:
                errors.append(f"{inventory_path.relative_to(repo_root)} group {group_name} must not define iv_jmp_user")

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
        if (
            override.variable_name in override.defaults.values
            and override.variable_value == override.defaults.values[override.variable_name]
        ):
            errors.append(
                f"{relative_path}:{override.line_number}: {override.variable_name} duplicates the default from {defaults_location}"
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


def check_yaml_scalar_style(repo_root: Path) -> list[str]:
    violations: list[str] = []

    for path in yaml_files(repo_root):
        lines = path.read_text(encoding="utf-8").splitlines()
        index = 0
        while index < len(lines):
            line = lines[index]
            prefix = line.removesuffix(" >-")
            if prefix == line or not line.strip().endswith(": >-"):
                index += 1
                continue

            indent = len(line) - len(line.lstrip(" "))
            body: list[str] = []
            block_index = index + 1
            while block_index < len(lines):
                block_line = lines[block_index]
                if block_line.strip() and len(block_line) - len(block_line.lstrip(" ")) <= indent:
                    break
                body.append(block_line.strip())
                block_index += 1

            collapsed = " ".join(part for part in body if part)
            single_line = f"{prefix} {collapsed}"
            if len(single_line) <= MAX_SINGLE_LINE_LENGTH:
                violations.append(f"{path.relative_to(repo_root)}:{index + 1}: {single_line}")
            index = block_index

    return violations


def check_shared_conventions(repo_root: Path) -> bool:
    checks = {
        "ansible requirements": check_ansible_requirements,
        "global variables": check_global_variables,
        "inventory": check_inventory,
        "role variable overrides": check_role_variable_overrides,
        "YAML scalar style": check_yaml_scalar_style,
    }
    ok = True
    for label, check in checks.items():
        errors = check(repo_root)
        if errors:
            write_line(f"{label}: {len(errors)} error(s)")
            for error in errors:
                write_line(f"  {error}")
            ok = False
    return ok


def print_config() -> None:
    write_line("Structure paths:")
    for path, patterns in STRUCTURE_PATHS.items():
        suffix = f" ({len(patterns)} regex check(s))" if patterns else ""
        write_line(f"  {path}{suffix}")


def main() -> int:
    args = parse_args()
    repo_root = args.repo_root.resolve()

    if args.command == "list":
        print_config()
        return 0
    if args.command == "structure-check":
        if check_structure(repo_root) and check_shared_conventions(repo_root):
            write_line(f"All {len(STRUCTURE_PATHS)} structure path(s) and shared convention checks passed.")
            return 0
        return 1

    raise SystemExit(f"Unknown command: {args.command}")


if __name__ == "__main__":
    raise SystemExit(main())
