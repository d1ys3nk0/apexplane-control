from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
TOOLKIT_ROOT = REPO_ROOT / "toolkit"
RUNTIME_ROOT = TOOLKIT_ROOT / "runtime"


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
    shutil.copy(RUNTIME_ROOT / "bin" / script_name, bin_dir / script_name)
    shutil.copy(RUNTIME_ROOT / "scripts/remote_ansible_state.py", scripts_dir / "remote_ansible_state.py")


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
    printf '%s\n' "${target%,} | CHANGED | rc=0 >>"
    if [ "${REMOTE_MIGRATE_TAGS+x}" = "x" ]; then
        printf '{"locked_at": "", "locked_by": "", "migrate_tag": "%s", "migrate_tags": %s}\n' \
            "${REMOTE_MIGRATE_TAG:-}" "${REMOTE_MIGRATE_TAGS}"
    else
        printf '{"locked_at": "", "locked_by": "", "migrate_tag": "%s"}\n' "${REMOTE_MIGRATE_TAG:-}"
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


def test_toolkit_taskfile_exposes_runtime_tasks() -> None:
    taskfile = (TOOLKIT_ROOT / "Taskfile.yml").read_text(encoding="utf-8")

    for task_name in ("run:", "migrate:", "bootstrap:", "vault:check:", "vault:fix:", "structure:check:"):
        assert f"  {task_name}" in taskfile

    assert "runtime/bin/run" in taskfile
    assert "runtime/bin/migrate" in taskfile
    assert "runtime/scripts/bootstrap.sh" in taskfile
    assert "runtime/scripts/ansible-vlint.sh" in taskfile
    assert "check_repo_sync.py' structure-check" in taskfile


def test_runtime_run_resolves_remote_state_from_installed_runtime(tmp_path: Path) -> None:
    write_runtime_fixture(tmp_path, "run")
    write_fake_uv(tmp_path)
    write_target_repo_fixture(tmp_path)

    result = subprocess.run(  # noqa: S603
        [BASH, "bin/run", "prd", "ycl", "app", "setup"],
        cwd=tmp_path,
        env=runtime_env(tmp_path),
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    remote_state_calls = (tmp_path / "tmp/remote_state_calls").read_text(encoding="utf-8")
    assert str(tmp_path / "scripts/remote_ansible_state.py") in remote_state_calls
    assert " --namespace " in remote_state_calls
    assert " acquire " in remote_state_calls
    assert r":task\ apc:run:" in remote_state_calls
    assert " release " in remote_state_calls
    assert (tmp_path / "log/prd-app-setup.log").is_file()
    assert not (tmp_path / "log/prd-app.log").exists()
    assert list((tmp_path / "log").glob("prd-app-*-setup.log"))


def test_runtime_migrate_resolves_remote_state_from_installed_runtime(tmp_path: Path) -> None:
    write_runtime_fixture(tmp_path, "migrate")
    write_fake_uv(tmp_path)
    write_target_repo_fixture(tmp_path)
    migration_path = tmp_path / "playbooks/app/_260601120000_runtime_test.yml"
    migration_path.write_text("---\n\n- hosts: all\n", encoding="utf-8")

    result = subprocess.run(  # noqa: S603
        [BASH, "bin/migrate", "apply", "prd", "ycl", "app"],
        cwd=tmp_path,
        env=runtime_env(tmp_path),
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    remote_state_calls = (tmp_path / "tmp/remote_state_calls").read_text(encoding="utf-8")
    assert str(tmp_path / "scripts/remote_ansible_state.py") in remote_state_calls
    assert " acquire " in remote_state_calls
    assert r":task\ apc:migrate:" in remote_state_calls
    assert " mark --migrate-tag 260601120000" in remote_state_calls
    assert " release " in remote_state_calls
    assert (tmp_path / "log/prd-app-migrate.log").is_file()
    assert not (tmp_path / "log/prd-app-migration.log").exists()
    assert list((tmp_path / "log").glob("prd-app-*-migrate.log"))


def test_runtime_migrate_dry_mode_skips_applied_migrations(tmp_path: Path) -> None:
    write_runtime_fixture(tmp_path, "migrate")
    write_fake_uv(tmp_path)
    write_target_repo_fixture(tmp_path)
    migration_path = tmp_path / "playbooks/app/_260601120000_runtime_test.yml"
    migration_path.write_text("---\n\n- hosts: all\n", encoding="utf-8")
    env = runtime_env(tmp_path)
    env["DRY"] = "1"
    env["REMOTE_MIGRATE_TAGS"] = '["260601120000"]'

    result = subprocess.run(  # noqa: S603
        [BASH, "bin/migrate", "apply", "prd", "ycl", "app"],
        cwd=tmp_path,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    remote_state_calls = (tmp_path / "tmp/remote_state_calls").read_text(encoding="utf-8")
    assert " get\n" in remote_state_calls
    assert " acquire " not in remote_state_calls
    assert " mark " not in remote_state_calls
    assert not (tmp_path / "log/prd-app-migrate.log").exists()


def test_runtime_migrate_dry_mode_skips_legacy_applied_migrations(tmp_path: Path) -> None:
    write_runtime_fixture(tmp_path, "migrate")
    write_fake_uv(tmp_path)
    write_target_repo_fixture(tmp_path)
    migration_path = tmp_path / "playbooks/app/_260601120000_runtime_test.yml"
    migration_path.write_text("---\n\n- hosts: all\n", encoding="utf-8")
    env = runtime_env(tmp_path)
    env["DRY"] = "1"
    env["REMOTE_MIGRATE_TAG"] = "260601120000"

    result = subprocess.run(  # noqa: S603
        [BASH, "bin/migrate", "apply", "prd", "ycl", "app"],
        cwd=tmp_path,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    remote_state_calls = (tmp_path / "tmp/remote_state_calls").read_text(encoding="utf-8")
    assert " get\n" in remote_state_calls
    assert " acquire " not in remote_state_calls
    assert " mark " not in remote_state_calls
    assert not (tmp_path / "log/prd-app-migrate.log").exists()


def test_runtime_migrate_dry_mode_runs_missing_older_migration_with_newer_tag_applied(tmp_path: Path) -> None:
    write_runtime_fixture(tmp_path, "migrate")
    write_fake_uv(tmp_path)
    write_target_repo_fixture(tmp_path)
    older_migration_path = tmp_path / "playbooks/app/_260601120000_runtime_test.yml"
    newer_migration_path = tmp_path / "playbooks/app/_260701120000_runtime_test.yml"
    older_migration_path.write_text("---\n\n- hosts: all\n", encoding="utf-8")
    newer_migration_path.write_text("---\n\n- hosts: all\n", encoding="utf-8")
    env = runtime_env(tmp_path)
    env["DRY"] = "1"
    env["REMOTE_MIGRATE_TAGS"] = '["260701120000"]'

    result = subprocess.run(  # noqa: S603
        [BASH, "bin/migrate", "apply", "prd", "ycl", "app"],
        cwd=tmp_path,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert "> Running migration _260601120000_runtime_test.yml" in result.stdout
    assert "> Running migration _260701120000_runtime_test.yml" not in result.stdout
    assert "--check" in result.stdout


def test_runtime_migrate_apply_materializes_legacy_applied_migrations(tmp_path: Path) -> None:
    write_runtime_fixture(tmp_path, "migrate")
    write_fake_uv(tmp_path)
    write_target_repo_fixture(tmp_path)
    older_migration_path = tmp_path / "playbooks/app/_260601120000_runtime_test.yml"
    newer_migration_path = tmp_path / "playbooks/app/_260701120000_runtime_test.yml"
    older_migration_path.write_text("---\n\n- hosts: all\n", encoding="utf-8")
    newer_migration_path.write_text("---\n\n- hosts: all\n", encoding="utf-8")
    env = runtime_env(tmp_path)
    env["REMOTE_MIGRATE_TAG"] = "260701120000"

    result = subprocess.run(  # noqa: S603
        [BASH, "bin/migrate", "apply", "prd", "ycl", "app"],
        cwd=tmp_path,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    remote_state_calls = (tmp_path / "tmp/remote_state_calls").read_text(encoding="utf-8")
    assert " mark --migrate-tag 260601120000" in remote_state_calls
    assert " mark --migrate-tag 260701120000" in remote_state_calls
    assert "> Running migration _260601120000_runtime_test.yml" not in result.stdout
    assert "> Running migration _260701120000_runtime_test.yml" not in result.stdout
    assert not (tmp_path / "log/prd-app-migrate.log").exists()


def test_runtime_migrate_clean_uses_exact_applied_migration_tags(tmp_path: Path) -> None:
    write_runtime_fixture(tmp_path, "migrate")
    write_fake_uv(tmp_path)
    write_target_repo_fixture(tmp_path)
    older_migration_path = tmp_path / "playbooks/app/_260601120000_runtime_test.yml"
    newer_migration_path = tmp_path / "playbooks/app/_260701120000_runtime_test.yml"
    older_migration_path.write_text("---\n\n- hosts: all\n", encoding="utf-8")
    newer_migration_path.write_text("---\n\n- hosts: all\n", encoding="utf-8")
    env = runtime_env(tmp_path)
    env["REMOTE_MIGRATE_TAGS"] = '["260701120000"]'

    result = subprocess.run(  # noqa: S603
        [BASH, "bin/migrate", "clean", "prd", "ycl", "app"],
        cwd=tmp_path,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert older_migration_path.is_file()
    assert not newer_migration_path.exists()


def test_runtime_migrate_dry_mode_runs_pending_migrations_in_check_mode(tmp_path: Path) -> None:
    write_runtime_fixture(tmp_path, "migrate")
    write_fake_uv(tmp_path)
    write_target_repo_fixture(tmp_path)
    migration_path = tmp_path / "playbooks/app/_260601120000_runtime_test.yml"
    migration_path.write_text("---\n\n- hosts: all\n", encoding="utf-8")
    env = runtime_env(tmp_path)
    env["DRY"] = "1"

    result = subprocess.run(  # noqa: S603
        [BASH, "bin/migrate", "apply", "prd", "ycl", "app"],
        cwd=tmp_path,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    remote_state_calls = (tmp_path / "tmp/remote_state_calls").read_text(encoding="utf-8")
    assert " get\n" in remote_state_calls
    assert " acquire " not in remote_state_calls
    assert " mark " not in remote_state_calls
    assert "--check" in result.stdout
    assert (tmp_path / "log/prd-app-migrate.log").is_file()


def test_bootstrap_uses_target_working_directory_for_inventory() -> None:
    bootstrap_script = (RUNTIME_ROOT / "scripts/bootstrap.sh").read_text(encoding="utf-8")

    assert 'PROJECT_ROOT="${PWD}"' in bootstrap_script
    assert 'prompt "SSH User" "root"' in bootstrap_script
    assert 'prompt "SSH User After" "iac"' in bootstrap_script
    assert 'prompt "New Hostname" "${REALM}-${PLATFORM}-${CLUSTER}01"' in bootstrap_script
