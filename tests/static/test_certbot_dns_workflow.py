from __future__ import annotations

import os
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
