from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MAX_SINGLE_LINE_LENGTH = 120
YAML_SUFFIXES = {".yml", ".yaml"}
IGNORED_DIRS = {
    ".ansible",
    ".git",
    ".mypy_cache",
    ".pytest_cache",
    ".ruff_cache",
    ".tox",
    ".venv",
    "__pycache__",
}


def _yaml_files() -> list[Path]:
    return sorted(
        path
        for path in ROOT.rglob("*")
        if path.is_file()
        and path.suffix in YAML_SUFFIXES
        and not any(part in IGNORED_DIRS for part in path.relative_to(ROOT).parts)
    )


def test_short_folded_yaml_scalars_are_single_line() -> None:
    violations: list[str] = []

    for path in _yaml_files():
        lines = path.read_text(encoding="utf-8").splitlines()
        index = 0
        while index < len(lines):
            line = lines[index]
            prefix = line.removesuffix(" >-")
            if prefix == line or not line.strip().endswith(": >-"):
                index += 1
                continue

            indent = len(line) - len(line.lstrip(" "))
            body: list[str] = []
            block_index = index + 1
            while block_index < len(lines):
                block_line = lines[block_index]
                if block_line.strip() and len(block_line) - len(block_line.lstrip(" ")) <= indent:
                    break
                body.append(block_line.strip())
                block_index += 1

            collapsed = " ".join(part for part in body if part)
            single_line = f"{prefix} {collapsed}"
            if len(single_line) <= MAX_SINGLE_LINE_LENGTH:
                violations.append(f"{path.relative_to(ROOT)}:{index + 1}: {single_line}")
            index = block_index

    assert not violations, "Use a single-line scalar for folded YAML values up to 120 chars:\n" + "\n".join(violations)
