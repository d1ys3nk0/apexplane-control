from __future__ import annotations

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
TOOLKIT_SCRIPTS_DIR = REPO_ROOT / "toolkit" / "scripts"
UNIT_TESTS_DIR = REPO_ROOT / "tests" / "unit"


def test_toolkit_python_scripts_have_unit_tests() -> None:
    missing = []
    for script_path in sorted(TOOLKIT_SCRIPTS_DIR.glob("*.py")):
        test_path = UNIT_TESTS_DIR / f"test_{script_path.stem}.py"
        if not test_path.is_file():
            missing.append(f"{script_path.relative_to(REPO_ROOT)} -> {test_path.relative_to(REPO_ROOT)}")

    assert missing == []
