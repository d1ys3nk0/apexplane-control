from __future__ import annotations

from pathlib import Path

from compatibility_shim_policy import run


REPO_ROOT = Path(__file__).resolve().parents[2]


def test_repository_compatibility_shim_policy_passes() -> None:
    assert run(REPO_ROOT) == []
