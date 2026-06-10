from __future__ import annotations

import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
LOCAL_SCRIPT_PATHS = [
    REPO_ROOT / "Taskfile.yml",
    REPO_ROOT / "toolkit" / "Taskfile.yml",
    *sorted((REPO_ROOT / "toolkit" / "bin").glob("*")),
    *sorted((REPO_ROOT / "toolkit" / "scripts").glob("*.sh")),
]
BARE_PYTHON_RE = re.compile(r"(?<![A-Za-z0-9_./-])python(?:3)?(?:\s|$)")
