from __future__ import annotations

import os
from pathlib import Path

import yaml


REPO_ROOT = Path(os.environ.get("ANSIBLE_LINT_REPO_ROOT", Path(__file__).resolve().parents[2])).resolve()


def test_audit_host_script_is_always_installed_by_toolbox() -> None:
    role_vars = yaml.safe_load((REPO_ROOT / "roles" / "toolbox" / "vars" / "main.yml").read_text(encoding="utf-8"))

    assert {"name": "audit_host", "src": "audit_host.sh"} in role_vars["toolbox_always_scripts"]
