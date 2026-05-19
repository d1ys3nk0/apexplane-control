#!/usr/bin/env python3
"""Check ApexPlane Control contracts in a consuming repository."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import TYPE_CHECKING


if TYPE_CHECKING:
    from collections.abc import Iterable


TOOLKIT_ROOT = Path(__file__).resolve().parent

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
    ".taskfile/platform-ycl.yml": (
        r"(?m)^tasks:$",
        r"(?m)^\s+prd:",
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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Check ApexPlane Control contracts in the current repository.")
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path.cwd(),
        help="target repository root; defaults to the current working directory",
    )

    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("structure-check", help="check target repository structure and regex contracts")
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
        if check_structure(repo_root):
            write_line(f"All {len(STRUCTURE_PATHS)} structure path(s) passed.")
            return 0
        return 1

    raise SystemExit(f"Unknown command: {args.command}")


if __name__ == "__main__":
    raise SystemExit(main())
