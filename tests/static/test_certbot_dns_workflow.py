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


def test_certbot_role_owns_dns_nicru_workflow() -> None:
    defaults = yaml.safe_load((CERTBOT_DIR / "defaults" / "main.yml").read_text(encoding="utf-8"))
    tasks = "\n".join(path.read_text(encoding="utf-8") for path in (CERTBOT_DIR / "tasks").glob("*.yml"))
    templates = "\n".join(
        path.read_text(encoding="utf-8") for path in (CERTBOT_DIR / "templates").rglob("*") if path.is_file()
    )

    assert defaults["certbot_dns_nicru_enabled"] is False
    assert defaults["certbot_haproxy_deploy_hook_enabled"] is False
    assert defaults["certbot_dns_nicru_package_version"] == "1.0.3"
    assert "certbot-dns-nicru=={{ certbot_dns_nicru_package_version }}" in (
        CERTBOT_DIR / "vars" / "main.yml"
    ).read_text(encoding="utf-8")
    assert "certbot_dns_nicru_credentials_path" in tasks
    assert "--authenticator" in templates
    assert "dns-nicru" in templates
    assert "--dns-nicru-credentials" in templates
    assert "haproxy -c -f /etc/haproxy/haproxy.cfg -f /etc/haproxy/conf.d" in templates
    assert "systemctl reload haproxy" in templates
    assert "systemctl is-active haproxy" in templates


def test_certbot_dns_nicru_package_is_optional() -> None:
    vars_text = (CERTBOT_DIR / "vars" / "main.yml").read_text(encoding="utf-8")
    install_tasks = yaml.safe_load((CERTBOT_DIR / "tasks" / "setup_install.yml").read_text(encoding="utf-8"))
    pip_task = next(task for task in install_tasks if task["name"] == "Install Certbot virtualenv packages")

    assert "certbot_virtualenv_packages" in vars_text
    assert "certbot_dns_nicru_enabled | bool" in vars_text
    assert pip_task["ansible.builtin.pip"]["name"] == "{{ certbot_virtualenv_packages }}"


def test_certbot_standalone_contract_does_not_enable_haproxy_hook_by_default() -> None:
    defaults = yaml.safe_load((CERTBOT_DIR / "defaults" / "main.yml").read_text(encoding="utf-8"))
    main_tasks = yaml.safe_load((CERTBOT_DIR / "tasks" / "main.yml").read_text(encoding="utf-8"))
    vars_text = (CERTBOT_DIR / "vars" / "main.yml").read_text(encoding="utf-8")
    readme = (CERTBOT_DIR / "README.md").read_text(encoding="utf-8")

    assert defaults["certbot_haproxy_deploy_hook_enabled"] is False
    assert any(
        task["name"] == "Configure HAProxy deploy hook" and "certbot_haproxy_deploy_hook_enabled | bool" in task["when"]
        for task in main_tasks
    )
    assert "if certbot_haproxy_deploy_hook_enabled | bool else []" in vars_text
    assert "`certbot_haproxy_deploy_hook_enabled` | `false`" in readme


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


def test_certbot_http01_dns_validation_runs_immediately_before_issue() -> None:
    tasks = yaml.safe_load((CERTBOT_DIR / "tasks" / "setup_http.yml").read_text(encoding="utf-8"))
    task_names = [task["name"] for task in tasks]
    dns_wait_index = task_names.index("Wait for HTTP-01 certificate domains to resolve using public DNS")
    issue_index = task_names.index("Obtain Let's Encrypt certificates using HTTP-01 challenge")
    dns_wait_task = tasks[dns_wait_index]
    issue_task = tasks[issue_index]

    assert dns_wait_index + 1 == issue_index
    assert dns_wait_task["loop"] == "{{ certbot_http_cert_items }}"
    assert dns_wait_task["when"] == issue_task["when"]
    assert "certbot_http_dns_wait_retries" in str(dns_wait_task)
    assert "certbot_http_dns_wait_delay" in str(dns_wait_task)
    assert "certbot_http_dns_validation" not in (HAPROXY_ALB_DIR / "vars" / "main.yml").read_text(encoding="utf-8")
    assert "haproxy_alb_dns_validation" not in (HAPROXY_ALB_DIR / "defaults" / "main.yml").read_text(encoding="utf-8")


def test_haproxy_alb_no_longer_manages_certbot() -> None:
    role_text = "\n".join(path.read_text(encoding="utf-8") for path in HAPROXY_ALB_DIR.rglob("*") if path.is_file())
    defaults = (HAPROXY_ALB_DIR / "defaults" / "main.yml").read_text(encoding="utf-8")
    main_tasks = (HAPROXY_ALB_DIR / "tasks" / "main.yml").read_text(encoding="utf-8")

    assert not (HAPROXY_ALB_DIR / "tasks" / "setup_certbot.yml").exists()
    assert not (HAPROXY_ALB_DIR / "files" / "certbot").exists()
    assert "ansible.builtin.pip" not in role_text
    assert "certbot certonly" not in role_text
    assert "manual-auth-hook" not in role_text
    assert "manual-cleanup-hook" not in role_text
    assert "--preferred-challenges=dns" not in role_text
    assert "haproxy_alb_certbot_" not in defaults
    assert "setup_certs.yml" in main_tasks


def test_haproxy_alb_certs_are_existing_pem_contract() -> None:
    setup_certs = (HAPROXY_ALB_DIR / "tasks" / "setup_certs.yml").read_text(encoding="utf-8")

    assert "haproxy_alb_ssl_cert_items" in setup_certs
    assert 'openssl x509 -in "{{ item.path }}" -noout -ext subjectAltName' in setup_certs
    assert "loop: '{{ haproxy_alb_installed_ssl_cert_items | default([]) }}'" in setup_certs
    assert "certbot" not in setup_certs.lower()
    assert "SKIPPED_MISSING_LINEAGE" not in setup_certs


def test_toolbox_haproxy_scripts_do_not_include_certbot_dns_workflow() -> None:
    role_vars = yaml.safe_load((REPO_ROOT / "roles" / "toolbox" / "vars" / "main.yml").read_text(encoding="utf-8"))
    role_tasks = (REPO_ROOT / "roles" / "toolbox" / "tasks" / "main.yml").read_text(encoding="utf-8")

    assert {script["name"] for script in role_vars["toolbox_haproxy_scripts"]} == {"haproxy_report"}
    assert not (TOOLBOX_SCRIPTS_DIR / "certbot_dns_auth.sh").exists()
    assert not (TOOLBOX_SCRIPTS_DIR / "certbot_dns_cleanup.sh").exists()
    assert not (TOOLBOX_SCRIPTS_DIR / "certbot_dns_issue.sh").exists()
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
