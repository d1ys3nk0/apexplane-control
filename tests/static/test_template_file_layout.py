from __future__ import annotations

import os
from pathlib import Path

from template_file_layout import run


REPO_ROOT = Path(os.environ.get("ANSIBLE_LINT_REPO_ROOT", Path(__file__).resolve().parents[2])).resolve()


def test_repository_template_file_layout_passes() -> None:
    assert run(repo_root=REPO_ROOT) == []
