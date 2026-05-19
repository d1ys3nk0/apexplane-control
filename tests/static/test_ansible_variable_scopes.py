from __future__ import annotations

import os
from pathlib import Path

from ansible_variable_scopes import run


REPO_ROOT = Path(os.environ.get("ANSIBLE_LINT_REPO_ROOT", Path(__file__).resolve().parents[2])).resolve()


def test_repository_variable_scopes_pass() -> None:
    assert run(repo_root=REPO_ROOT) == []
