from __future__ import annotations

from apc_target_static import target_repo_root


def test_setup_playbooks_have_matching_assess_playbooks() -> None:
    repo_root = target_repo_root()
    playbooks_dir = repo_root / "playbooks"
    if not playbooks_dir.is_dir():
        return

    errors: list[str] = []
    for setup_path in sorted(playbooks_dir.glob("*/setup.yml")):
        assess_path = setup_path.with_name("assess.yml")
        if not assess_path.is_file():
            errors.append(f"{assess_path.relative_to(repo_root)} is missing")

    assert errors == []
