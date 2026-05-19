from __future__ import annotations

import os
from pathlib import Path

from docker_resource_names import run


REPO_ROOT = Path(os.environ.get("ANSIBLE_LINT_REPO_ROOT", Path(__file__).resolve().parents[2])).resolve()


def test_repository_docker_resource_names_pass() -> None:
    assert run(repo_root=REPO_ROOT) == []
