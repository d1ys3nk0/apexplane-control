from __future__ import annotations

from pathlib import Path

from ansible_role_variable_contracts import run


REPO_ROOT = Path(__file__).resolve().parents[2]


def test_repository_role_variable_contracts_pass() -> None:
    assert run(repo_root=REPO_ROOT) == []
