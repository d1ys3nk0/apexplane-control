from __future__ import annotations

import os
from pathlib import Path
from typing import cast

import yaml


REPO_ROOT = Path(os.environ.get("ANSIBLE_LINT_REPO_ROOT", Path(__file__).resolve().parents[2])).resolve()


def load_yaml(path: Path) -> object:
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def test_assessment_owns_host_audit_inputs() -> None:
    defaults = load_yaml(REPO_ROOT / "roles" / "assessment" / "defaults" / "main.yml")
    assert isinstance(defaults, dict)
    defaults_data = cast("dict[str, object]", defaults)

    assert defaults_data["assessment_audit_enabled"] is False
    assert defaults_data["assessment_audit_toolbox_script"] == "/opt/toolbox/bin/audit_host"


def test_audit_host_script_is_always_installed_by_toolbox() -> None:
    role_vars = load_yaml(REPO_ROOT / "roles" / "toolbox" / "vars" / "main.yml")
    assert isinstance(role_vars, dict)
    role_vars_data = cast("dict[str, object]", role_vars)
    always_scripts = cast("list[object]", role_vars_data["toolbox_always_scripts"])

    assert {"name": "audit_host", "src": "audit_host.sh"} in always_scripts
