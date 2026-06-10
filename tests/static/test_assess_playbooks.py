from __future__ import annotations

import os
from pathlib import Path

import yaml


REPO_ROOT = Path(os.environ.get("ANSIBLE_LINT_REPO_ROOT", Path(__file__).resolve().parents[2])).resolve()


def load_yaml(path: Path) -> object:
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def test_setup_playbooks_have_matching_assess_playbooks() -> None:
    playbooks_dir = REPO_ROOT / "playbooks"
    if not playbooks_dir.is_dir():
        return

    errors: list[str] = []
    for setup_path in sorted(playbooks_dir.glob("*/setup.yml")):
        assess_path = setup_path.with_name("assess.yml")
        if not assess_path.is_file():
            errors.append(f"{assess_path.relative_to(REPO_ROOT)} is missing")

    assert errors == []
