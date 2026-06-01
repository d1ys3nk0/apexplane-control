from __future__ import annotations

import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
LOCAL_SCRIPT_PATHS = [
    REPO_ROOT / "Taskfile.yml",
    REPO_ROOT / "toolkit" / "Taskfile.yml",
    *sorted((REPO_ROOT / "toolkit" / "runtime" / "bin").glob("*")),
    *sorted((REPO_ROOT / "toolkit" / "runtime" / "scripts").glob("*.sh")),
]
BARE_PYTHON_RE = re.compile(r"(?<![A-Za-z0-9_./-])python(?:3)?(?:\s|$)")


def test_local_scripts_run_python_through_uv() -> None:
    errors: list[str] = []
    for path in LOCAL_SCRIPT_PATHS:
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            if BARE_PYTHON_RE.search(line) and "uv run python" not in line:
                errors.append(f"{path.relative_to(REPO_ROOT)}:{line_number}: use uv run python")

    assert errors == []
