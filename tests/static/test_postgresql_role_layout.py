from __future__ import annotations

from pathlib import Path

from postgresql_role_layout import run


REPO_ROOT = Path(__file__).resolve().parents[2]


def test_repository_postgresql_role_layout_passes() -> None:
    assert run(repo_root=REPO_ROOT) == []
