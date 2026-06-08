from __future__ import annotations

import os
from pathlib import Path

import yaml


REPO_ROOT = Path(os.environ.get("ANSIBLE_LINT_REPO_ROOT", Path(__file__).resolve().parents[2])).resolve()


def test_audit_host_script_is_always_installed_by_toolbox() -> None:
    role_vars = yaml.safe_load((REPO_ROOT / "roles" / "toolbox" / "vars" / "main.yml").read_text(encoding="utf-8"))

    assert {"name": "audit_host", "src": "audit_host.sh"} in role_vars["toolbox_always_scripts"]


def test_audit_role_invokes_toolbox_audit_script() -> None:
    audit_tasks = (REPO_ROOT / "roles" / "audit" / "tasks" / "setup_common.yml").read_text(encoding="utf-8")

    assert "/opt/toolbox/bin/audit_host" in audit_tasks
    assert "AUDIT_SYSCTL_PARAMS_JSON" in audit_tasks
    assert "AUDIT_CRITICAL_SYSTEMD_UNITS" in audit_tasks


def test_audit_role_installs_dedicated_quiet_cron_job() -> None:
    audit_tasks = (REPO_ROOT / "roles" / "audit" / "tasks" / "setup_common.yml").read_text(encoding="utf-8")

    assert "dest: /etc/cron.d/audit-host" in audit_tasks
    assert "CRON_TZ=UTC" in audit_tasks
    assert "{{ audit_cron_minute }} {{ audit_cron_hour }} * * * root" in audit_tasks
    assert "/opt/toolbox/bin/audit_host --quiet > {{ audit_cron_log_path }}" in audit_tasks
    assert "when: audit_cron_enabled | bool" in audit_tasks
