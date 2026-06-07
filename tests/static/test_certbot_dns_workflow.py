from __future__ import annotations

import os
import re
import shutil
import subprocess
from pathlib import Path

import yaml


REPO_ROOT = Path(os.environ.get("ANSIBLE_LINT_REPO_ROOT", Path(__file__).resolve().parents[2])).resolve()
TOOLBOX_SCRIPTS_DIR = REPO_ROOT / "roles" / "toolbox" / "files" / "scripts"
HAPROXY_ALB_DIR = REPO_ROOT / "roles" / "haproxy_alb"


def test_toolbox_haproxy_scripts_include_manual_certbot_dns_workflow() -> None:
    role_vars = yaml.safe_load((REPO_ROOT / "roles" / "toolbox" / "vars" / "main.yml").read_text(encoding="utf-8"))
    role_tasks = (REPO_ROOT / "roles" / "toolbox" / "tasks" / "main.yml").read_text(encoding="utf-8")

    assert {script["name"] for script in role_vars["toolbox_haproxy_scripts"]} == {
        "certbot_dns_auth",
        "certbot_dns_cleanup",
        "certbot_dns_issue",
        "haproxy_report",
    }
    assert "certbot_dns_auth.sh" in {script["src"] for script in role_vars["toolbox_haproxy_scripts"]}
    assert "loop: '{{ toolbox_haproxy_scripts }}'" in role_tasks
    assert "when: toolbox_haproxy_enabled | bool" in role_tasks


def test_toolbox_scripts_are_valid_bash() -> None:
    bash = shutil.which("bash")
    assert bash is not None

    for script_path in sorted(script_path for script_path in TOOLBOX_SCRIPTS_DIR.iterdir() if script_path.is_file()):
        subprocess.run([bash, "-n", str(script_path)], check=True)  # noqa: S603


def test_toolbox_scripts_use_shared_helpers_for_operator_logging() -> None:
    forbidden_patterns = (
        r"^\s*_log\b",
        r"\bstep_cmd\b",
        r"^\s*run\(\)",
        r"^\s*(info|warn|error|die|usage_error|cmd|cmd_output|require_vars|require_command|require_positive_integer|is_true|toolbox_[a-z_]+)\b",
    )

    for script_path in sorted(script_path for script_path in TOOLBOX_SCRIPTS_DIR.iterdir() if script_path.is_file()):
        script = script_path.read_text(encoding="utf-8")
        assert 'source "${SCRIPT_DIR}/../lib/helpers.sh"' in script
        for pattern in forbidden_patterns:
            assert not re.search(pattern, script, re.MULTILINE), (
                f"{script_path.relative_to(REPO_ROOT)} must use underscore-prefixed toolbox helpers"
            )
        assert "_cmd vi " not in script


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


def test_haproxy_alb_no_longer_manages_manual_dns_certbot() -> None:
    role_text = "\n".join(path.read_text(encoding="utf-8") for path in HAPROXY_ALB_DIR.rglob("*") if path.is_file())
    defaults = (HAPROXY_ALB_DIR / "defaults" / "main.yml").read_text(encoding="utf-8")

    assert not (HAPROXY_ALB_DIR / "tasks" / "certbot_dns.yml").exists()
    assert not (HAPROXY_ALB_DIR / "files" / "certbot" / "dns_auth.sh").exists()
    assert not (HAPROXY_ALB_DIR / "files" / "certbot" / "dns_cleanup.sh").exists()
    assert "manual-auth-hook" not in role_text
    assert "manual-cleanup-hook" not in role_text
    assert "--preferred-challenges=dns" not in role_text
    assert "haproxy_alb_certbot_dns_" not in defaults


def test_haproxy_alb_wildcard_certs_are_existing_pem_contract() -> None:
    setup_certbot = (HAPROXY_ALB_DIR / "tasks" / "setup_certbot.yml").read_text(encoding="utf-8")

    assert "haproxy_alb_manual_ssl_cert_items" in setup_certbot
    assert "haproxy_alb_automatic_ssl_cert_items" in setup_certbot
    assert "Wildcard HAProxy certificates must be generated manually before running haproxy_alb." in setup_certbot
    assert 'openssl x509 -in "{{ item.path }}" -noout -ext subjectAltName' in setup_certbot
    assert "loop: '{{ haproxy_alb_automatic_ssl_cert_items | default([]) }}'" in setup_certbot
    assert "certbot_dns.yml" not in setup_certbot


def test_haproxy_alb_http_certbot_failures_are_ignored_after_reporting_failure() -> None:
    tasks = yaml.safe_load((HAPROXY_ALB_DIR / "tasks" / "setup_certbot.yml").read_text(encoding="utf-8"))
    certbot_task = next(
        task for task in tasks if task["name"] == "Obtain non-wildcard Let's Encrypt certificates using http challenge"
    )

    assert certbot_task["ignore_errors"] is True
    assert "failed_when" not in certbot_task


def test_haproxy_alb_installs_only_existing_automatic_certbot_lineages() -> None:
    setup_certbot = (HAPROXY_ALB_DIR / "tasks" / "setup_certbot.yml").read_text(encoding="utf-8")

    assert "SKIPPED_MISSING_LINEAGE" in setup_certbot
    assert "loop: '{{ haproxy_alb_installed_ssl_cert_items | default([]) }}'" in setup_certbot
