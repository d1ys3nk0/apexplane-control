from __future__ import annotations

import os
from collections.abc import Mapping
from pathlib import Path
from typing import cast

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


def test_assess_playbooks_use_assessment_role() -> None:
    playbooks_dir = REPO_ROOT / "playbooks"
    if not playbooks_dir.is_dir():
        return

    errors: list[str] = []
    for assess_path in sorted(playbooks_dir.glob("*/assess.yml")):
        data = load_yaml(assess_path)
        if not isinstance(data, list) or not data:
            errors.append(f"{assess_path.relative_to(REPO_ROOT)} must contain a play")
            continue

        play = data[0]
        if not isinstance(play, Mapping):
            errors.append(f"{assess_path.relative_to(REPO_ROOT)} must contain a mapping play")
            continue

        play_map = cast("Mapping[object, object]", play)
        roles = play_map.get("roles")
        if not isinstance(roles, list):
            errors.append(f"{assess_path.relative_to(REPO_ROOT)} must define roles")
            continue

        role_names = []
        for role in roles:
            if isinstance(role, str):
                role_names.append(role)
            elif isinstance(role, dict):
                role_map = cast("dict[object, object]", role)
                role_names.append(str(role_map.get("role", "")))

        if "assessment" not in role_names:
            errors.append(f"{assess_path.relative_to(REPO_ROOT)} must use role assessment")

    assert errors == []
