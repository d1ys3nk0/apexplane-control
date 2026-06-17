from __future__ import annotations

from collections.abc import Iterator, Mapping
from pathlib import Path
from typing import cast

import yaml


REPO_ROOT = Path(__file__).resolve().parents[2]


def load_yaml(path: Path) -> object:
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def iter_tasks(value: object) -> Iterator[Mapping[str, object]]:
    if isinstance(value, list):
        for item in value:
            yield from iter_tasks(item)
        return
    if not isinstance(value, Mapping):
        return

    task = cast("Mapping[str, object]", value)
    yield task
    for nested_key in ("block", "rescue", "always"):
        yield from iter_tasks(task.get(nested_key))


def iter_tasks_with_become(
    value: object, *, inherited_become: bool = False
) -> Iterator[tuple[Mapping[str, object], bool]]:
    if isinstance(value, list):
        for item in value:
            yield from iter_tasks_with_become(item, inherited_become=inherited_become)
        return
    if not isinstance(value, Mapping):
        return

    task = cast("Mapping[str, object]", value)
    effective_become = inherited_become or task.get("become") is True
    yield task, effective_become
    for nested_key in ("block", "rescue", "always"):
        yield from iter_tasks_with_become(task.get(nested_key), inherited_become=effective_become)


def rel(path: Path) -> str:
    return str(path.relative_to(REPO_ROOT))


def docker_roles() -> Iterator[Path]:
    roles_dir = REPO_ROOT / "roles"
    yield from sorted(path for path in roles_dir.iterdir() if path.is_dir() and path.name.startswith("docker_"))


def role_defaults(role_dir: Path) -> Mapping[str, object]:
    defaults_path = role_dir / "defaults" / "main.yml"
    if not defaults_path.is_file():
        return {}
    defaults = load_yaml(defaults_path)
    return cast("Mapping[str, object]", defaults) if isinstance(defaults, Mapping) else {}


def is_socket_bind_source(source: str) -> bool:
    return source.endswith(".sock")


def has_file_bind_mounts(module: Mapping[str, object]) -> bool:
    mounts = module.get("mounts")
    if isinstance(mounts, list):
        for mount in mounts:
            mount_value = cast("Mapping[str, object]", mount) if isinstance(mount, Mapping) else {}
            source = mount_value.get("source")
            if mount_value.get("type") == "bind" and isinstance(source, str) and not is_socket_bind_source(source):
                return True

    volumes = module.get("volumes")
    if isinstance(volumes, list):
        for volume in volumes:
            if isinstance(volume, str):
                source = volume.split(":", 1)[0]
                if source.startswith(("/", "./", "../")) and not is_socket_bind_source(source):
                    return True
            volume_value = cast("Mapping[str, object]", volume) if isinstance(volume, Mapping) else {}
            source = volume_value.get("source")
            if volume_value.get("type") == "bind" and isinstance(source, str) and not is_socket_bind_source(source):
                return True

    return False


def has_host_bind_mounts(module: Mapping[str, object]) -> bool:
    mounts = module.get("mounts")
    if isinstance(mounts, list):
        for mount in mounts:
            mount_value = cast("Mapping[str, object]", mount) if isinstance(mount, Mapping) else {}
            source = mount_value.get("source")
            if mount_value.get("type") == "bind" and isinstance(source, str) and source.strip() != "":
                return True

    return False


def has_hostname_placement_constraint(module: Mapping[str, object]) -> bool:
    placement = module.get("placement")
    placement = cast("Mapping[str, object]", placement) if isinstance(placement, Mapping) else {}
    constraints = placement.get("constraints")
    if not isinstance(constraints, list):
        return False

    return any(isinstance(constraint, str) and "node.hostname" in constraint for constraint in constraints)


def swarm_service_modules(role_dir: Path) -> Iterator[Mapping[str, object]]:
    for task_path in sorted((role_dir / "tasks").glob("*.yml")):
        for task in iter_tasks(load_yaml(task_path)):
            service = task.get("community.docker.docker_swarm_service")
            if isinstance(service, Mapping):
                yield cast("Mapping[str, object]", service)


def placement_constraints(service: Mapping[str, object]) -> object:
    placement = service.get("placement")
    if not isinstance(placement, Mapping):
        return None
    return cast("Mapping[str, object]", placement).get("constraints")


def uses_docker_cli(task: Mapping[str, object]) -> bool:
    for module_name in ("ansible.builtin.command", "ansible.builtin.shell", "command", "shell"):
        module = task.get(module_name)
        if isinstance(module, str) and module.strip().startswith("docker "):
            return True
        if not isinstance(module, Mapping):
            continue
        module = cast("Mapping[str, object]", module)
        cmd = module.get("cmd")
        argv = module.get("argv")
        if isinstance(cmd, str) and cmd.strip().startswith("docker "):
            return True
        if isinstance(argv, list) and argv[:1] == ["docker"]:
            return True
    return False


def service_module(task: Mapping[str, object]) -> Mapping[str, object]:
    for module_name in ("ansible.builtin.service", "ansible.builtin.systemd", "ansible.builtin.systemd_service"):
        module = task.get(module_name)
        if isinstance(module, Mapping):
            return cast("Mapping[str, object]", module)
    return {}


def test_docker_api_tasks_escalate_privileges() -> None:
    errors: list[str] = []

    for task_path in sorted((REPO_ROOT / "roles").glob("**/tasks/*.yml")):
        for task, effective_become in iter_tasks_with_become(load_yaml(task_path)):
            uses_docker_module = any(isinstance(key, str) and key.startswith("community.docker.") for key in task)
            if not uses_docker_module and not uses_docker_cli(task):
                continue
            if effective_become:
                continue
            task_name = task.get("name", "<unnamed>")
            errors.append(f"{rel(task_path)}: {task_name}: Docker API/CLI tasks must use become")

    assert errors == []


def test_docker_swarm_hostname_constraints_are_limited_to_host_binds() -> None:
    errors: list[str] = []

    for role_dir in docker_roles():
        for task_path in sorted((role_dir / "tasks").glob("*.yml")):
            for task in iter_tasks(load_yaml(task_path)):
                service = task.get("community.docker.docker_swarm_service")
                if not isinstance(service, Mapping):
                    continue
                service = cast("Mapping[str, object]", service)
                if has_hostname_placement_constraint(service) and not has_host_bind_mounts(service):
                    task_name = task.get("name", "<unnamed>")
                    errors.append(
                        f"{rel(task_path)}: {task_name}: node.hostname constraints are only for host bind mounts"
                    )

    assert errors == []


def test_single_replica_swarm_service_roles_expose_placement_constraints() -> None:
    for role_name in ("docker_swarm_alloy", "docker_swarm_pghero", "docker_swarm_postgres_exporter"):
        role_dir = REPO_ROOT / "roles" / role_name
        constraint_var = f"{role_name}_placement_constraints"
        defaults = role_defaults(role_dir)
        services = list(swarm_service_modules(role_dir))

        assert defaults[constraint_var] == []
        assert any(placement_constraints(service) == f"{{{{ {constraint_var} }}}}" for service in services)


def test_pghero_swarm_service_has_explicit_single_replica() -> None:
    role_dir = REPO_ROOT / "roles" / "docker_swarm_pghero"
    replicated_services = [
        service for service in swarm_service_modules(role_dir) if service.get("mode") == "replicated"
    ]

    assert any(service.get("replicas") == 1 for service in replicated_services)


def test_traefik_swarm_service_uses_manager_placement_and_rolling_updates() -> None:
    role_dir = REPO_ROOT / "roles" / "docker_swarm_traefik"
    defaults = role_defaults(role_dir)
    services = list(swarm_service_modules(role_dir))

    assert "docker_swarm_traefik_ping_enabled" not in defaults
    assert isinstance(defaults["docker_swarm_traefik_health_allowed_cidrs"], list)
    assert defaults["docker_swarm_traefik_health_allowed_cidrs"]
    assert defaults["docker_swarm_traefik_placement_constraints"] == ["node.role == manager"]
    assert defaults["docker_swarm_traefik_update_order"] == "stop-first"
    assert defaults["docker_swarm_traefik_update_parallelism"] == 1
    assert any(
        placement_constraints(service) == "{{ docker_swarm_traefik_placement_constraints }}"
        and service.get("update_config")
        == {
            "order": "{{ docker_swarm_traefik_update_order }}",
            "parallelism": "{{ docker_swarm_traefik_update_parallelism }}",
        }
        for service in services
    )
    assert any(
        isinstance(labels := service.get("labels"), str)
        and "'traefik.http.routers.health.service': 'ping@internal'" in labels
        and "'traefik.http.routers.health.middlewares': 'health-ip-allowlist'" in labels
        and "docker_swarm_traefik_health_allowed_cidrs | join(',')" in labels
        for service in services
    )


def test_docker_image_defaults_use_name_tag_and_full_image() -> None:
    errors: list[str] = []

    for role_dir in docker_roles():
        defaults = role_defaults(role_dir)
        role_name = role_dir.name
        image_full_name = f"{role_name}_image_full"
        image_name_name = f"{role_name}_image_name"
        image_tag_name = f"{role_name}_image_tag"

        uses_primary_image_full = False
        for task_path in sorted((role_dir / "tasks").glob("*.yml")):
            for task in iter_tasks(load_yaml(task_path)):
                for module_name in ("community.docker.docker_container", "community.docker.docker_swarm_service"):
                    module = task.get(module_name)
                    module = cast("Mapping[str, object]", module) if isinstance(module, Mapping) else {}
                    if module.get("image") == f"{{{{ {image_full_name} }}}}":
                        uses_primary_image_full = True

        if uses_primary_image_full:
            if image_name_name not in defaults:
                errors.append(f"{rel(role_dir / 'defaults' / 'main.yml')}: missing {image_name_name}")
            if image_tag_name not in defaults:
                errors.append(f"{rel(role_dir / 'defaults' / 'main.yml')}: missing {image_tag_name}")
            image_default = defaults.get(image_full_name)
            if (
                not isinstance(image_default, str)
                or image_name_name not in image_default
                or image_tag_name not in image_default
            ):
                errors.append(
                    f"{rel(role_dir / 'defaults' / 'main.yml')}: {image_full_name} must include "
                    f"{image_name_name} and {image_tag_name}"
                )

    assert errors == []


def test_docker_image_full_defaults_use_name_and_tag_defaults() -> None:
    errors: list[str] = []

    for role_dir in docker_roles():
        defaults = role_defaults(role_dir)
        for name, value in sorted(defaults.items()):
            if not name.endswith("_image_full"):
                continue
            if name.endswith("_runtime_image_full"):
                continue

            image_name = f"{name.removesuffix('_full')}_name"
            image_tag = f"{name.removesuffix('_full')}_tag"
            if image_name not in defaults:
                errors.append(f"{rel(role_dir / 'defaults' / 'main.yml')}: missing {image_name}")
            if image_tag not in defaults:
                errors.append(f"{rel(role_dir / 'defaults' / 'main.yml')}: missing {image_tag}")
            if not isinstance(value, str) or image_name not in value or image_tag not in value:
                errors.append(
                    f"{rel(role_dir / 'defaults' / 'main.yml')}: {name} must include {image_name} and {image_tag}"
                )

    assert errors == []


def test_dbs_service_roles_expose_data_volume_defaults() -> None:
    role_volume_pairs = {
        "docker_elastic": ("docker_elastic_data_volume", "elastic-data"),
        "docker_postgres": ("docker_postgres_data_volume", "postgres-data"),
        "docker_rabbit": ("docker_rabbit_data_volume", "rabbit-data"),
        "docker_redis": ("docker_redis_data_volume", "redis-data"),
    }

    for role_name, (volume_var, default_volume) in role_volume_pairs.items():
        role_dir = REPO_ROOT / "roles" / role_name
        defaults = role_defaults(role_dir)
        tasks_text = "\n".join(path.read_text(encoding="utf-8") for path in sorted((role_dir / "tasks").glob("*.yml")))

        assert defaults[volume_var] == default_volume
        assert f"name: '{{{{ {volume_var} }}}}'" in tasks_text
        assert f"{{{{ {volume_var} }}}}:" in tasks_text


def task_when_values(task: Mapping[str, object]) -> list[str]:
    when = task.get("when")
    if isinstance(when, str):
        return [when]
    if isinstance(when, list):
        return [item for item in when if isinstance(item, str)]
    return []


def task_when_contains(task: Mapping[str, object], *expected_values: str) -> bool:
    when_values = task_when_values(task)
    return all(any(expected_value in when_value for when_value in when_values) for expected_value in expected_values)


def task_when_rejects_invalid_typed_approval(task: Mapping[str, object]) -> bool:
    when_values = task_when_values(task)
    return any(
        "user_input" in when_value and "default" in when_value and "!= ''" in when_value for when_value in when_values
    ) and any(
        "user_input" in when_value and "default" in when_value and "lower != 'yes'" in when_value
        for when_value in when_values
    )


def test_docker_daemon_restart_requires_typed_interactive_approval() -> None:
    role_dir = REPO_ROOT / "roles" / "docker"
    defaults = role_defaults(role_dir)
    tasks = list(iter_tasks(load_yaml(role_dir / "tasks" / "main.yml")))

    assert "docker_interactive_mode" in defaults
    assert "docker_yes_mode" in defaults
    assert "docker_force_mode" not in defaults

    guarded_restart_indexes: list[int] = []
    for index, task in enumerate(tasks):
        module = service_module(task)
        if module.get("name") == "docker" and module.get("state") == "restarted":
            guarded_restart_indexes.append(index)

    assert guarded_restart_indexes, "roles/docker must have a Docker restart task guarded by typed approval"

    for index in guarded_restart_indexes:
        prior_tasks = tasks[:index]

        assert any(
            "ansible.builtin.debug" in task
            and task.get("changed_when") is True
            and task_when_contains(task, "ansible_check_mode", "docker_update_config.changed")
            for task in prior_tasks
        )
        assert any(
            "ansible.builtin.fail" in task
            and task_when_contains(
                task,
                "not ansible_check_mode",
                "docker_update_config.changed",
                "not (docker_interactive_mode | bool)",
                "not (docker_yes_mode | bool)",
            )
            for task in prior_tasks
        )
        assert any(
            "ansible.builtin.pause" in task
            and task.get("register") == "docker_restart_approval"
            and task_when_contains(
                task,
                "not ansible_check_mode",
                "docker_update_config.changed",
                "docker_interactive_mode | bool",
                "not (docker_yes_mode | bool)",
            )
            for task in prior_tasks
        )
        assert any(
            "ansible.builtin.fail" in task
            and task_when_rejects_invalid_typed_approval(task)
            and task_when_contains(
                task,
                "not ansible_check_mode",
                "docker_update_config.changed",
                "docker_interactive_mode | bool",
                "not (docker_yes_mode | bool)",
            )
            for task in prior_tasks
        )
        restart_task = tasks[index]
        assert task_when_contains(
            restart_task,
            "docker_update_config.changed",
            "docker_restart_approved",
        )
        variables = load_yaml(role_dir / "vars" / "main.yml")
        assert isinstance(variables, Mapping)
        variables = cast("Mapping[object, object]", variables)
        docker_restart_approved = variables.get("docker_restart_approved")
        assert isinstance(docker_restart_approved, str)
        assert "docker_yes_mode" in docker_restart_approved
        assert "docker_restart_approval is defined" in docker_restart_approved
        assert "docker_restart_approval.user_input | default('') | lower) == 'yes'" in docker_restart_approved
