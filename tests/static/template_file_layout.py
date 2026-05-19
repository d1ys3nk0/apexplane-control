from __future__ import annotations

import re
import shutil
import subprocess
from pathlib import Path


MIN_ROLE_PAYLOAD_PARTS = 4
JINJA_EXPR_RE = re.compile(r"{{\s*(.*?)\s*}}", re.DOTALL)
JINJA_BLOCK_RE = re.compile(r"(?<!\$){[%#]")
GO_TEMPLATE_PREFIXES = ("if ", "else", "end", "with ", "range ", "json ", "printf ", "index ")


def _tracked_files(repo_root: Path) -> list[Path]:
    git = shutil.which("git")
    if git is None:
        raise RuntimeError("git executable was not found")

    result = subprocess.run(  # noqa: S603
        [git, "ls-files", "-z"],
        check=True,
        cwd=repo_root,
        stdout=subprocess.PIPE,
        text=False,
    )
    return [Path(item.decode()) for item in result.stdout.split(b"\0") if item]


def _all_files(repo_root: Path) -> list[Path]:
    return sorted(path.relative_to(repo_root) for path in repo_root.rglob("*") if path.is_file())


def _candidate_files(repo_root: Path) -> list[Path]:
    if (repo_root / ".git").exists():
        return _tracked_files(repo_root)
    return _all_files(repo_root)


def role_payload_dir(path: Path, dirname: str) -> bool:
    return len(path.parts) >= MIN_ROLE_PAYLOAD_PARTS and path.parts[0] == "roles" and dirname in path.parts


def file_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="ignore")


def has_jinja(text: str) -> bool:
    if JINJA_BLOCK_RE.search(text):
        return True

    for match in JINJA_EXPR_RE.finditer(text):
        expression = match.group(1).strip()
        if expression and not expression.startswith(("$", ".", *GO_TEMPLATE_PREFIXES)):
            return True
    return False


def check_file(*, repo_root: Path, path: Path) -> list[str]:
    full_path = repo_root / path
    if not full_path.is_file():
        return []

    in_templates = role_payload_dir(path, "templates")
    in_files = role_payload_dir(path, "files")
    if not in_templates and not in_files:
        return []

    text = file_text(full_path)
    jinja = False if in_files and path.suffix == ".json" else has_jinja(text)
    shebang = text.startswith("#!/")
    errors: list[str] = []

    if in_templates:
        if jinja and not path.name.endswith(".j2"):
            errors.append("Jinja template files under templates/ must end with .j2")
        if not jinja:
            errors.append("static files must live under files/, not templates/")

    if in_files:
        if jinja:
            errors.append("Jinja template files must live under templates/, not files/")
        if path.name.endswith(".j2"):
            errors.append("static files under files/ must not end with .j2")

    if shebang:
        expected_suffix = ".sh.j2" if jinja else ".sh"
        if not path.name.endswith(expected_suffix):
            errors.append(f"files with shebangs must end with {expected_suffix}")

    return [f"{path}: {error}" for error in errors]


def run(*, repo_root: Path, **_kwargs: object) -> list[str]:
    return [error for path in _candidate_files(repo_root) for error in check_file(repo_root=repo_root, path=path)]
