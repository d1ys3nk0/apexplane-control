from __future__ import annotations

import os
import shutil
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
TOOLKIT_ROOT = REPO_ROOT / "toolkit"
BIN_ROOT = TOOLKIT_ROOT / "bin"
SCRIPTS_ROOT = TOOLKIT_ROOT / "scripts"


def bash_executable() -> str:
    bash = shutil.which("bash")
    if bash is None:
        msg = "bash executable not found"
        raise RuntimeError(msg)
    return bash


BASH = bash_executable()


def write_runtime_fixture(tmp_path: Path, script_name: str) -> None:
    bin_dir = tmp_path / "bin"
    scripts_dir = tmp_path / "scripts"
    bin_dir.mkdir(parents=True)
    scripts_dir.mkdir(parents=True)
    shutil.copy(BIN_ROOT / script_name, bin_dir / script_name)
    shutil.copy(SCRIPTS_ROOT / "remote_ansible_state.py", scripts_dir / "remote_ansible_state.py")


def write_fake_uv(tmp_path: Path) -> None:
    fake_uv = tmp_path / "bin/uv"
    fake_uv.write_text(
        """#!/usr/bin/env bash
set -euo pipefail

append_log() {
    if [ -n "${ANSIBLE_LOG_PATH:-}" ]; then
        printf '%s\n' "$1" >> "${ANSIBLE_LOG_PATH}"
    fi
}

args="$*"
if [ "${1:-}" = "run" ] && [ "${2:-}" = "python" ]; then
    shift 2
    exec python "$@"
fi

if [[ "${args}" == *"remote_ansible_state.py"* ]]; then
    mkdir -p tmp
    printf '%s\n' "${args}" >> tmp/remote_state_calls
    target="$3"
    if [ "${REMOTE_MIGRATE_TAGS+x}" = "x" ]; then
        state="$(printf '{"locked_at": "", "locked_by": "", "migrate_tag": "%s", "migrate_tags": %s}' \
            "${REMOTE_MIGRATE_TAG:-}" "${REMOTE_MIGRATE_TAGS}")"
    else
        state="$(printf '{"locked_at": "", "locked_by": "", "migrate_tag": "%s"}' "${REMOTE_MIGRATE_TAG:-}")"
    fi
    if [ "${REMOTE_STATE_OUTPUT:-compact}" = "json" ]; then
        printf '%s\n' "${target%,} | CHANGED => {"
        printf '    "changed": true,\n'
        printf '    "stdout": %s,\n' "$(python -c 'import json, sys; print(json.dumps(sys.argv[1] + "\\n"))' "${state}")"
        printf '    "stdout_lines": [%s]\n' "$(python -c 'import json, sys; print(json.dumps(sys.argv[1]))' "${state}")"
        printf '%s\n' "}"
    else
        printf '%s\n' "${target%,} | CHANGED | rc=0 >>"
        printf '%s\n' "${state}"
    fi
    exit 0
fi

if [[ "${args}" == *"--list-hosts"* ]]; then
    printf '%s\n' '  hosts (1):'
    printf '%s\n' '    prd-ycl-app01'
    exit 0
fi

if [[ "${args}" == *"--syntax-check"* ]]; then
    append_log 'syntax ok'
    exit 0
fi

append_log 'changed: [prd-ycl-app01] => {"changed": true}'
printf '%s\n' 'ok: [prd-ycl-app01]'
""",
        encoding="utf-8",
    )
    fake_uv.chmod(0o755)


def write_target_repo_fixture(tmp_path: Path) -> None:
    (tmp_path / "variables/prd").mkdir(parents=True)
    inventory_path = tmp_path / "inventories/app/prd.yml"
    inventory_path.parent.mkdir(parents=True)
    inventory_path.write_text(
        """---

all:
  children:
    prd:
      children:
        prd_ycl:
          children:
            prd_ycl_app:
              hosts:
                prd-ycl-app01: {}
""",
        encoding="utf-8",
    )
    playbook_path = tmp_path / "playbooks/app/setup.yml"
    playbook_path.parent.mkdir(parents=True)
    playbook_path.write_text("---\n\n- hosts: all\n", encoding="utf-8")


def runtime_env(tmp_path: Path) -> dict[str, str]:
    env = os.environ.copy()
    env["PATH"] = f"{tmp_path / 'bin'}{os.pathsep}{env['PATH']}"
    env["ANSIBLE_SSH_USER"] = "operator"
    env["DRY"] = "0"
    return env
