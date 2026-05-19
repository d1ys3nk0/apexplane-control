from __future__ import annotations

import re
from typing import TYPE_CHECKING, cast

import yaml


if TYPE_CHECKING:
    from pathlib import Path


DEPRECATED_PLAYBOOK_ROLES = {"platform_sts", "platform_ycl"}
MIGRATION_PLAYBOOK_RE = re.compile(r"^_[0-9]{12}_[a-z0-9_]+\.yml$")


def _rel_path(path: Path, repo_root: Path) -> str:
    return path.relative_to(repo_root).as_posix()


def _load_yaml(path: Path) -> object | None:
    try:
        return yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError:
        return None


def _role_name(role: object) -> str | None:
    if isinstance(role, str):
        return role
    if not isinstance(role, dict):
        return None

    role = cast("dict[str, object]", role)
    value = role.get("role")
    if isinstance(value, str):
        return value

    return None


def _validate_playbook_roles(repo_root: Path) -> list[str]:
    playbooks_dir = repo_root / "playbooks"
    if not playbooks_dir.is_dir():
        return []

    errors = []
    for playbook_path in sorted(playbooks_dir.glob("*/*.yml")):
        rel_path = _rel_path(playbook_path, repo_root)
        if playbook_path.name == "cleanup.yml":
            errors.append(f"{rel_path}: legacy cleanup playbooks must be replaced with _YYMMDDHHMMSS_slug.yml")
            continue

        if playbook_path.name.startswith("_") or playbook_path.name[:1].isdigit():
            if not MIGRATION_PLAYBOOK_RE.fullmatch(playbook_path.name):
                errors.append(f"{rel_path}: migration playbook name must match _YYMMDDHHMMSS_slug.yml")
            continue

        data = _load_yaml(playbook_path)
        if not isinstance(data, list):
            continue

        for play in data:
            if not isinstance(play, dict):
                continue

            play = cast("dict[str, object]", play)
            roles = play.get("roles")
            if not isinstance(roles, list):
                continue

            role_names = [_role_name(role) for role in roles]
            deprecated_roles = sorted(role_name for role_name in role_names if role_name in DEPRECATED_PLAYBOOK_ROLES)
            if deprecated_roles:
                errors.append(f"{rel_path}: deprecated platform roles must be removed: {', '.join(deprecated_roles)}")

            if "cleanup" in role_names:
                errors.append(f"{rel_path}: legacy cleanup role must be replaced with timestamped migration playbooks")

    return errors


def run(repo_root: Path) -> list[str]:
    roles_dir = repo_root / "roles"
    errors = []

    if roles_dir.is_dir():
        cleanup_role_dir = roles_dir / "cleanup"
        if cleanup_role_dir.exists():
            errors.append("roles/cleanup: legacy cleanup role must be replaced with timestamped migration playbooks")

        errors.extend(
            f"{_rel_path(cleanup_path, repo_root)}: role-local cleanup belongs in timestamped project migrations"
            for cleanup_path in sorted(roles_dir.glob("*/tasks/cleanup.yml"))
        )

    errors.extend(_validate_playbook_roles(repo_root))

    return errors
