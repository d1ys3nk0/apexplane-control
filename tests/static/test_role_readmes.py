from __future__ import annotations

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
ROLES_DIR = REPO_ROOT / "roles"


def test_roles_have_readmes() -> None:
    errors: list[str] = []

    for role_dir in sorted(path for path in ROLES_DIR.iterdir() if path.is_dir()):
        readme = role_dir / "README.md"
        if not readme.is_file():
            errors.append(f"{role_dir.relative_to(REPO_ROOT)}: missing README.md")
            continue

        text = readme.read_text(encoding="utf-8")
        required_parts = [
            f"# {role_dir.name}",
            "## Features",
            "## Configuration",
            "## Usage",
        ]
        missing = [part for part in required_parts if part not in text]
        if missing:
            errors.append(f"{readme.relative_to(REPO_ROOT)}: missing {', '.join(missing)}")

    assert errors == []
