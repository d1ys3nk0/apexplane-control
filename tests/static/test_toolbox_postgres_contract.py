from __future__ import annotations

import os
import re
from pathlib import Path


REPO_ROOT = Path(os.environ.get("ANSIBLE_LINT_REPO_ROOT", Path(__file__).resolve().parents[2])).resolve()
TOOLBOX_POSTGRES_PATHS = [
    REPO_ROOT / "roles" / "toolbox" / "files" / "lib" / "helpers.sh",
    *(REPO_ROOT / "roles" / "toolbox" / "files" / "scripts").glob("pg_*.sh"),
]
TOOLBOX_DOCKER_COMMAND_PATHS = [
    REPO_ROOT / "roles" / "toolbox" / "templates" / "bash_toolbox.sh.j2",
    *(REPO_ROOT / "roles" / "toolbox" / "files" / "scripts").glob("*.sh"),
]


def test_postgresql_toolbox_docker_runs_clear_image_entrypoint() -> None:
    helpers_text = (REPO_ROOT / "roles" / "toolbox" / "files" / "lib" / "helpers.sh").read_text(encoding="utf-8")
    docker_pg_image_pattern = re.compile(r"\b_docker run\b.*?\"\$\{PG_IMAGE\}\"", re.DOTALL)
    match = docker_pg_image_pattern.search(helpers_text)

    assert match is not None
    assert "--entrypoint ''" in match.group(0)


def test_postgresql_toolbox_scripts_use_shared_docker_helper() -> None:
    errors = []
    docker_run_pattern = re.compile(r"\bdocker run\b")
    scripts_dir = REPO_ROOT / "roles" / "toolbox" / "files" / "scripts"

    for path in sorted(scripts_dir.glob("pg_*.sh")):
        text = path.read_text(encoding="utf-8")
        for match in docker_run_pattern.finditer(text):
            line_number = text[: match.start()].count("\n") + 1
            rel_path = path.relative_to(REPO_ROOT)
            errors.append(f"{rel_path}:{line_number}: use _docker_postgres instead of raw docker run")

    assert not errors, "\n".join(errors)


def test_postgresql_toolbox_docker_helper_uses_sudo() -> None:
    helpers_text = (REPO_ROOT / "roles" / "toolbox" / "files" / "lib" / "helpers.sh").read_text(encoding="utf-8")

    assert 'sudo docker "$@"' in helpers_text
    assert "_docker run" in helpers_text
    assert "    docker run" not in helpers_text


def test_toolbox_docker_commands_use_sudo() -> None:
    errors = []
    bare_docker_pattern = re.compile(
        r"(?m)(?:^\s*|[|;&]\s*)docker (?:ps|rm|inspect|info|node|service|stats|exec|logs|system|secret|run)\b"
    )

    for path in sorted(TOOLBOX_DOCKER_COMMAND_PATHS):
        text = path.read_text(encoding="utf-8")
        for match in bare_docker_pattern.finditer(text):
            line_number = text[: match.start()].count("\n") + 1
            rel_path = path.relative_to(REPO_ROOT)
            errors.append(f"{rel_path}:{line_number}: Docker CLI commands must use sudo")

    assert not errors, "\n".join(errors)
