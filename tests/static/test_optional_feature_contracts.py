from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml


REPO_ROOT = Path(__file__).resolve().parents[2]


def _load_tasks(path: Path) -> list[dict[str, Any]]:
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    assert isinstance(data, list)
    return data


def _text(value: object) -> str:
    if isinstance(value, list):
        return "\n".join(str(item) for item in value)
    return str(value)


def test_zitadel_first_instance_org_uses_requested_enabled_contract() -> None:
    role_dir = REPO_ROOT / "roles" / "docker_swarm_zitadel"
    vars_text = (role_dir / "vars/main.yml").read_text(encoding="utf-8")
    validate_tasks = _load_tasks(role_dir / "tasks/validate.yml")

    assert "docker_swarm_zitadel_init_org_enabled:" in vars_text
    assert "docker_swarm_zitadel_init_org_requested:" in vars_text
    assert "docker_swarm_zitadel_init_org_name | string | length > 0" in vars_text
    assert "and docker_swarm_zitadel_init_org_human_username | string | length > 0" in vars_text
    assert "and docker_swarm_zitadel_init_org_human_password | string | length > 0" in vars_text
    assert "or docker_swarm_zitadel_init_org_human_username | string | length > 0" in vars_text
    assert "or docker_swarm_zitadel_init_org_human_password | string | length > 0" in vars_text
    assert "docker_swarm_zitadel_init_org_enabled | bool else 'start'" in vars_text
    assert "docker_swarm_zitadel_init_org_enabled | bool) | ternary" in vars_text

    org_validation = next(
        task
        for task in validate_tasks
        if task.get("name") == "Validate Docker Swarm Zitadel first-instance org variables"
    )
    assertions = _text(org_validation["ansible.builtin.assert"]["that"])
    assert (
        "docker_swarm_zitadel_init_org_requested | bool == docker_swarm_zitadel_init_org_enabled | bool" in assertions
    )
    assert "docker_swarm_zitadel_enabled | bool" in _text(org_validation.get("when", ""))
