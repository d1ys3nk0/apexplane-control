from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml


REPO_ROOT = Path(__file__).resolve().parents[2]
POSTGRESQL_MODULES = {
    "community.postgresql.postgresql_db",
    "community.postgresql.postgresql_privs",
    "community.postgresql.postgresql_user",
}
REQUIRED_ADMIN_CREDENTIAL_ROLES = {"docker_postgres"}


def _load_tasks(path: Path) -> list[dict[str, Any]]:
    if not path.is_file():
        return []
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    if data is None:
        return []
    assert isinstance(data, list)
    return data


def _load_mapping(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    if data is None:
        return {}
    assert isinstance(data, dict)
    return data


def _text(value: object) -> str:
    if isinstance(value, list):
        return "\n".join(str(item) for item in value)
    return str(value)


def _has_postgresql_module(task: dict[str, Any]) -> bool:
    return any(module in task for module in POSTGRESQL_MODULES)


def _task_has_admin_gate(task: dict[str, Any], role_name: str) -> bool:
    when = _text(task.get("when", ""))
    return f"{role_name}_pg_provision_enabled | bool" in when or (
        f"{role_name}_pg_admin_user | string | length > 0" in when
        and f"{role_name}_pg_admin_pass | string | length > 0" in when
    )


def test_postgresql_admin_credentials_default_to_empty_string() -> None:
    errors: list[str] = []

    for defaults_path in sorted((REPO_ROOT / "roles").glob("*/defaults/main.yml")):
        role_name = defaults_path.parents[1].name
        if role_name in REQUIRED_ADMIN_CREDENTIAL_ROLES:
            continue
        defaults = _load_mapping(defaults_path)
        errors.extend(
            f"{defaults_path.relative_to(REPO_ROOT)}: {key} must default to empty string"
            for key in sorted(defaults)
            if key.endswith(("_pg_admin_user", "_pg_admin_pass")) and defaults[key] != ""
        )

    assert errors == []


def test_docker_postgres_admin_credentials_are_required() -> None:
    defaults_path = REPO_ROOT / "roles/docker_postgres/defaults/main.yml"
    validate_path = REPO_ROOT / "roles/docker_postgres/tasks/validate.yml"
    defaults = _load_mapping(defaults_path)
    validate_text = validate_path.read_text(encoding="utf-8")

    assert defaults["docker_postgres_pg_admin_user"] is None
    assert defaults["docker_postgres_pg_admin_pass"] is None
    assert "docker_postgres_pg_admin_user is not none" in validate_text
    assert "docker_postgres_pg_admin_user | string | length > 0" in validate_text
    assert "docker_postgres_pg_admin_pass is not none" in validate_text
    assert "docker_postgres_pg_admin_pass | string | length > 0" in validate_text
    assert "docker_postgres_walg_binary_url is match('^https?://.*/wal-g-pg[-_].*')" in validate_text


def test_docker_postgres_walg_backup_and_recovery_contracts() -> None:
    backup_text = (REPO_ROOT / "roles/docker_postgres/files/scripts/walg_backup.sh").read_text(encoding="utf-8")
    recover_text = (REPO_ROOT / "roles/docker_postgres/files/scripts/walg_recover.sh").read_text(encoding="utf-8")
    env_text = (REPO_ROOT / "roles/docker_postgres/templates/postgres.env.j2").read_text(encoding="utf-8")
    recover_main = recover_text.split("main() {", maxsplit=1)[1].split("\n}", maxsplit=1)[0]

    assert "Usage: walg_backup s3:key-or-prefix|s3://bucket/key-or-prefix|/mounted/walg/repo" in backup_text
    assert (
        "Usage: walg_recover [--time <timestamp>] s3:key-or-prefix|s3://bucket/key-or-prefix|/mounted/walg/repo"
        in recover_text
    )
    assert "Expected exactly one backup path argument" in backup_text
    assert "Recovery source argument is required" in recover_text
    assert 'WALG_BACKUP_PATH="$1"' in backup_text
    assert 'WALG_RECOVER_PATH="${WALG_RECOVER_SOURCE}"' in recover_text
    assert 'WALG_BACKUP_PATH="{{ docker_postgres_walg_backup_path }}"' not in env_text
    assert 'WALG_RECOVER_PATH="{{ docker_postgres_walg_recover_path }}"' not in env_text
    assert "WALG_RECOVER_S3_PREFIX" not in recover_text
    assert "WALG_FILE_PREFIX" in recover_text
    assert "WALG_S3_PREFIX=${WALG_RECOVER_STORAGE_PATH}" in recover_text
    assert "recovery_target_time" in recover_text
    assert "recovery_target_action = %spromote%s" in recover_text
    assert 'test -f "$1/PG_VERSION" && test -f "$1/global/pg_control"' in recover_text
    assert (
        'test -f "$1/postgresql.auto.conf" && test -f "$1/recovery.signal" && test -f "$1/walg_restore.log"'
        in recover_text
    )
    assert '[ "${container_state}" = "running" ] || [ "${container_state}" = "restarting" ]' in recover_text
    assert "WALG_RECOVER_STOP_WAIT_SECONDS" in recover_text
    assert "wait_for_postgres_container_stopped" in recover_text
    assert recover_main.index("validate_recovered_data_files") < recover_main.index("install_restore_command")
    assert recover_main.index("validate_recovery_config_files") < recover_main.index("start_postgres_container")
    assert recover_main.index("validate_recover_path_access") < recover_main.index("wait_before_recovery")


def test_docker_postgres_walg_follower_archives_to_backup_path() -> None:
    defaults_text = (REPO_ROOT / "roles/docker_postgres/defaults/main.yml").read_text(encoding="utf-8")
    vars_text = (REPO_ROOT / "roles/docker_postgres/vars/main.yml").read_text(encoding="utf-8")
    env_text = (REPO_ROOT / "roles/docker_postgres/templates/postgres.env.j2").read_text(encoding="utf-8")
    setup_text = (REPO_ROOT / "roles/docker_postgres/tasks/setup_walg.yml").read_text(encoding="utf-8")
    backup_text = (REPO_ROOT / "roles/docker_postgres/files/scripts/walg_backup.sh").read_text(encoding="utf-8")
    leader_text = (REPO_ROOT / "roles/docker_postgres/templates/postgresql.leader.conf.j2").read_text(encoding="utf-8")
    follower_text = (REPO_ROOT / "roles/docker_postgres/templates/postgresql.follower.conf.j2").read_text(
        encoding="utf-8"
    )

    assert "docker_postgres_walg_backup_s3_prefix" not in defaults_text
    assert "docker_postgres_walg_recover_s3_prefix" not in defaults_text
    assert "docker_postgres_walg_backup_path: ''" in defaults_text
    assert "docker_postgres_walg_recover_path: ''" in defaults_text
    assert "inventory_hostname in docker_postgres_walg_backup_hostnames" in vars_text
    assert "docker_postgres_walg_backup_path_is_s3_relative" in vars_text
    assert "docker_postgres_walg_backup_path_is_local" in vars_text
    assert "docker_postgres_walg_recover_path_is_s3_relative" in vars_text
    assert "docker_postgres_walg_recover_path_is_local" in vars_text
    assert "docker_postgres_walg_local_paths" in vars_text
    assert "WALG_BACKUP_PATH" in backup_text
    assert "WALG_BACKUP_S3_PREFIX" not in backup_text
    assert "WALG_FILE_PREFIX" in backup_text
    assert "WALG_S3_PREFIX=${WALG_BACKUP_STORAGE_PATH}" in backup_text
    assert "{% if docker_postgres_walg_backup_enabled | bool %}" in env_text
    assert "docker_postgres_walg_backup_s3_enabled | bool" in setup_text
    assert "WALG_FILE_PREFIX" in setup_text
    assert "docker_postgres_walg_backup_local_enabled" in setup_text
    assert "docker_postgres_walg_container_volumes" in setup_text
    assert "Local WAL-G repository path {{ item.item }} must exist" in setup_text
    assert (
        'AWS_ACCESS_KEY_ID: "{{ docker_postgres_walg_backup_s3_access_key '
        "if docker_postgres_walg_backup_s3_enabled | bool else '' }}\""
    ) in setup_text
    assert "{% if docker_postgres_walg_backup_enabled | bool %}" in leader_text
    assert "{% if docker_postgres_walg_backup_enabled | bool %}" in follower_text
    assert "archive_mode = always" in follower_text
    assert (
        "archive_command = '/usr/local/bin/wal-g wal-push \"%p\" >> /var/log/postgresql/walg_archive.log 2>&1'"
    ) in follower_text


def test_runtime_postgresql_provisioning_is_gated_by_admin_credentials() -> None:
    vars_text = (REPO_ROOT / "roles/runtime/vars/main.yml").read_text(encoding="utf-8")
    validate_text = (REPO_ROOT / "roles/runtime/tasks/validate.yml").read_text(encoding="utf-8")
    provision_text = (REPO_ROOT / "roles/runtime/tasks/postgres_provision.yml").read_text(encoding="utf-8")

    assert "runtime_pg_provision_enabled" in vars_text
    assert "item.user | string | length > 0" in validate_text
    assert "item.pass | string | length > 0" in validate_text
    assert "runtime_pg_base_items" in validate_text
    assert "provision is not defined" not in validate_text
    assert "runtime_pg_provision_items" not in vars_text
    assert "runtime_pg_provision_requested" not in vars_text
    assert "selectattr('provision'" not in vars_text
    assert "runtime_pg_base_items" in provision_text
    assert "runtime_pg_provision_enabled | bool" in provision_text


def test_backups_postgresql_env_contract() -> None:
    backups_defaults = (REPO_ROOT / "roles/backups/defaults/main.yml").read_text(encoding="utf-8")
    backups_vars = (REPO_ROOT / "roles/backups/vars/main.yml").read_text(encoding="utf-8")
    backups_validate = (REPO_ROOT / "roles/backups/tasks/validate.yml").read_text(encoding="utf-8")
    backups_tasks = (REPO_ROOT / "roles/backups/tasks/postgres.yml").read_text(encoding="utf-8")
    backups_env = (REPO_ROOT / "roles/backups/templates/postgres.env.j2").read_text(encoding="utf-8")
    runtime_defaults = (REPO_ROOT / "roles/runtime/defaults/main.yml").read_text(encoding="utf-8")
    runtime_validate = (REPO_ROOT / "roles/runtime/tasks/validate.yml").read_text(encoding="utf-8")
    runtime_provision = (REPO_ROOT / "roles/runtime/tasks/postgres_provision.yml").read_text(encoding="utf-8")
    zitadel_defaults = (REPO_ROOT / "roles/docker_swarm_zitadel/defaults/main.yml").read_text(encoding="utf-8")
    zitadel_validate = (REPO_ROOT / "roles/docker_swarm_zitadel/tasks/validate.yml").read_text(encoding="utf-8")
    zitadel_provision = (REPO_ROOT / "roles/docker_swarm_zitadel/tasks/postgresql.yml").read_text(encoding="utf-8")

    assert "backups_postgres_recover_concurrency: '{{ backups_postgres_backup_concurrency }}'" in backups_defaults
    assert "backups_postgres_recover_secret: '{{ backups_postgres_backup_secret }}'" in backups_defaults
    assert "backups_postgres_recover_s3_endpoint: '{{ backups_postgres_backup_s3_endpoint }}'" in backups_defaults
    assert "backups_postgres_recover_s3_region: '{{ backups_postgres_backup_s3_region }}'" in backups_defaults
    assert "backups_postgres_recover_s3_bucket: '{{ backups_postgres_backup_s3_bucket }}'" in backups_defaults
    assert "backups_postgres_recover_s3_access_key: '{{ backups_postgres_backup_s3_access_key }}'" in backups_defaults
    assert "backups_postgres_recover_s3_secret_key: '{{ backups_postgres_backup_s3_secret_key }}'" in backups_defaults
    assert "backups_postgres_backup_s3_enabled" in backups_vars
    assert "backups_postgres_recover_s3_enabled" in backups_vars
    assert "rejectattr('backup', 'defined')" in backups_vars
    assert "selectattr('backup')" in backups_vars
    assert "item.home is not defined or item.home | string is match('^/')" in backups_validate
    assert "no_log: '{{ backups_nolog }}'" in backups_validate
    assert "no_log: '{{ backups_nolog }}'" in backups_tasks
    assert "path: \"{{ item.home | default('/home/' ~ item.user, true) }}/postgres\"" in backups_tasks
    assert "dest: \"{{ item.home | default('/home/' ~ item.user, true) }}/postgres/{{ pg_base }}.env\"" in backups_tasks
    assert 'owner: "{{ item.owner | default(item.user, true) }}"' in backups_tasks
    assert "PG_BACKUP_S3_PREFIX=\"postgres/{{ pg_base }}/$(date -u '+%y/%V')\"" in backups_env
    assert "PG_RECOVER_S3_PREFIX=\"postgres/{{ pg_base }}/$(date -u '+%y/%V')\"" in backups_env
    assert 'PG_SSL="{{ pg_ssl }}"' in backups_env
    assert "backups_postgres_recover_s3_prefix" not in backups_validate
    assert "runtime_pg_backup" not in runtime_defaults
    assert "runtime_pg_recover" not in runtime_defaults
    assert "runtime_pg_backup" not in runtime_validate
    assert "runtime_pg_recover" not in runtime_validate
    assert "docker_swarm_zitadel_pg_backup" not in zitadel_defaults
    assert "docker_swarm_zitadel_pg_recover" not in zitadel_defaults
    assert "docker_swarm_zitadel_pg_image" not in zitadel_defaults
    assert "docker_swarm_zitadel_pg_backup" not in zitadel_validate
    assert "docker_swarm_zitadel_pg_recover" not in zitadel_validate
    assert 'ssl_mode: "{{ runtime_pg_ssl }}"' in runtime_provision
    assert "item.sslmode" not in runtime_provision
    assert "item.sslmode" not in runtime_validate
    assert "ssl_mode: '{{ docker_swarm_zitadel_pg_ssl }}'" in zitadel_provision
    assert "/opt/zitadel/postgres" not in zitadel_provision


def test_postgresql_resource_tasks_are_gated_by_admin_credentials() -> None:
    errors: list[str] = []

    for role_dir in sorted(path for path in (REPO_ROOT / "roles").iterdir() if path.is_dir()):
        role_name = role_dir.name
        if role_name in REQUIRED_ADMIN_CREDENTIAL_ROLES:
            continue
        vars_text = (
            (role_dir / "vars/main.yml").read_text(encoding="utf-8") if (role_dir / "vars/main.yml").is_file() else ""
        )
        main_tasks = _load_tasks(role_dir / "tasks/main.yml")
        gated_postgresql_includes = {
            task["ansible.builtin.include_tasks"]
            for task in main_tasks
            if task.get("ansible.builtin.include_tasks") == "setup_postgresql.yml"
            and f"{role_name}_pg_provision_enabled | bool" in _text(task.get("when", ""))
        }

        if gated_postgresql_includes and (
            f"{role_name}_pg_admin_user | string | length > 0" not in vars_text
            or f"{role_name}_pg_admin_pass | string | length > 0" not in vars_text
        ):
            errors.append(
                f"{(role_dir / 'vars/main.yml').relative_to(REPO_ROOT)}: define {role_name}_pg_provision_enabled from pg_admin_user and pg_admin_pass"
            )

        for tasks_path in sorted((role_dir / "tasks").glob("*.yml")):
            for task in _load_tasks(tasks_path):
                if not _has_postgresql_module(task):
                    continue
                if tasks_path.name in gated_postgresql_includes:
                    continue
                if not _task_has_admin_gate(task, role_name):
                    errors.append(
                        f"{tasks_path.relative_to(REPO_ROOT)}: gate {task.get('name', '<unnamed>')} on non-empty pg_admin_user and pg_admin_pass"
                    )

    assert errors == []
