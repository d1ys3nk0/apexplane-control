from __future__ import annotations

import os
import re
import shutil
import subprocess
from pathlib import Path

import yaml


REPO_ROOT = Path(os.environ.get("ANSIBLE_LINT_REPO_ROOT", Path(__file__).resolve().parents[2])).resolve()
TOOLBOX_SCRIPTS_DIR = REPO_ROOT / "roles" / "toolbox" / "files" / "scripts"
CERTBOT_DIR = REPO_ROOT / "roles" / "certbot"
HAPROXY_ALB_DIR = REPO_ROOT / "roles" / "haproxy_alb"


def test_certbot_wrapper_and_hook_templates_are_valid_bash() -> None:
    bash = shutil.which("bash")
    assert bash is not None

    for script_path in [
        CERTBOT_DIR / "templates" / "certbot" / "certonly.sh.j2",
        CERTBOT_DIR / "templates" / "certbot" / "haproxy-deploy.sh.j2",
    ]:
        subprocess.run([bash, "-n", str(script_path)], check=True)  # noqa: S603


def test_certbot_sensitive_tasks_use_nolog() -> None:
    nicru_tasks = yaml.safe_load((CERTBOT_DIR / "tasks" / "setup_nicru.yml").read_text(encoding="utf-8"))
    validate_tasks = yaml.safe_load((CERTBOT_DIR / "tasks" / "validate.yml").read_text(encoding="utf-8"))

    credential_task = next(task for task in nicru_tasks if task["name"] == "Install NIC.ru Certbot credentials")
    assert credential_task["no_log"] == "{{ certbot_nolog }}"

    nicru_validate_task = next(
        task for task in validate_tasks if task["name"] == "Assert NIC.ru required variables are set when enabled"
    )
    assert nicru_validate_task["no_log"] == "{{ certbot_nolog }}"


def test_toolbox_command_helpers_keep_cmd_as_the_entrypoint() -> None:
    toolbox_files = [
        REPO_ROOT / "roles" / "toolbox" / "files" / "lib" / "helpers.sh",
        *sorted(script_path for script_path in TOOLBOX_SCRIPTS_DIR.iterdir() if script_path.is_file()),
    ]

    for path in toolbox_files:
        text = path.read_text(encoding="utf-8")
        assert not re.search(r"\b_[a-z0-9_]+_cmd\b", text), (
            f"{path.relative_to(REPO_ROOT)} must use `_cmd _operation`, not `_operation_cmd`"
        )
