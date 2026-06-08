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


def test_docker_container_mounts_use_module_parameter_names() -> None:
    errors: list[str] = []

    for role_dir in docker_roles():
        for task_path in sorted((role_dir / "tasks").glob("*.yml")):
            for task in iter_tasks(load_yaml(task_path)):
                container = task.get("community.docker.docker_container")
                if not isinstance(container, Mapping):
                    continue
                container = cast("Mapping[str, object]", container)
                mounts = container.get("mounts")
                if not isinstance(mounts, list):
                    continue
                task_name = task.get("name", "<unnamed>")
                errors.extend(
                    f"{rel(task_path)}: {task_name}: mounts must use read_only, not readonly"
                    for mount in mounts
                    if isinstance(mount, Mapping) and "readonly" in mount
                )

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


def test_docker_container_runtime_type_policy() -> None:
    errors: list[str] = []

    for role_dir in docker_roles():
        if not role_dir.name.startswith("docker_swarm_"):
            continue
        for task_path in sorted((role_dir / "tasks").glob("*.yml")):
            for task in iter_tasks(load_yaml(task_path)):
                task_name = task.get("name", "<unnamed>")
                container = task.get("community.docker.docker_container")
                container = cast("Mapping[str, object]", container) if isinstance(container, Mapping) else {}
                if "restart_policy" in container and not has_file_bind_mounts(container):
                    errors.append(
                        f"{rel(task_path)}: {task_name}: workloads without file binds must use docker_swarm_service"
                    )

    assert errors == []


def test_docker_container_hostnames_use_inventory_hostname() -> None:
    errors: list[str] = []

    for role_dir in docker_roles():
        for task_path in sorted((role_dir / "tasks").glob("*.yml")):
            for task in iter_tasks(load_yaml(task_path)):
                container = task.get("community.docker.docker_container")
                if not isinstance(container, Mapping) or "image" not in container:
                    continue
                container = cast("Mapping[str, object]", container)
                hostname = container.get("hostname")
                if not isinstance(hostname, str) or "inventory_hostname" not in hostname:
                    task_name = task.get("name", "<unnamed>")
                    errors.append(
                        f"{rel(task_path)}: {task_name}: docker_container image tasks need inventory_hostname hostname"
                    )

    assert errors == []


def test_docker_restart_policy_containers_use_role_memory_defaults() -> None:
    errors: list[str] = []

    for role_dir in docker_roles():
        defaults = role_defaults(role_dir)
        for task_path in sorted((role_dir / "tasks").glob("*.yml")):
            for task in iter_tasks(load_yaml(task_path)):
                container = task.get("community.docker.docker_container")
                if not isinstance(container, Mapping) or "restart_policy" not in container:
                    continue
                container = cast("Mapping[str, object]", container)
                task_name = task.get("name", "<unnamed>")
                required_suffixes = {
                    "memory_reservation": "_mem_res",
                    "memory": "_mem_lim",
                    "memory_swap": "_mem_swp",
                }
                for key, suffix in required_suffixes.items():
                    value = container.get(key)
                    if not isinstance(value, str):
                        errors.append(f"{rel(task_path)}: {task_name}: {key} must be set from a role default")
                        continue
                    default_names = [name for name in defaults if name.endswith(suffix)]
                    if not any(name in value for name in default_names):
                        errors.append(f"{rel(task_path)}: {task_name}: {key} must reference a role default variable")

    assert errors == []


def test_docker_swarm_services_use_role_memory_defaults() -> None:
    errors: list[str] = []

    for role_dir in docker_roles():
        defaults = role_defaults(role_dir)
        for task_path in sorted((role_dir / "tasks").glob("*.yml")):
            for task in iter_tasks(load_yaml(task_path)):
                service = task.get("community.docker.docker_swarm_service")
                if not isinstance(service, Mapping) or "image" not in service:
                    continue
                service = cast("Mapping[str, object]", service)
                task_name = task.get("name", "<unnamed>")
                resource_suffixes = {
                    ("reservations", "memory"): "_mem_res",
                    ("limits", "memory"): "_mem_lim",
                }
                for (section_name, key), suffix in resource_suffixes.items():
                    section = service.get(section_name)
                    if not isinstance(section, Mapping):
                        errors.append(f"{rel(task_path)}: {task_name}: {section_name}.{key} must be set")
                        continue
                    section = cast("Mapping[str, object]", section)
                    value = section.get(key)
                    if not isinstance(value, str):
                        errors.append(
                            f"{rel(task_path)}: {task_name}: {section_name}.{key} must be set from a role default"
                        )
                        continue
                    default_names = [name for name in defaults if name.endswith(suffix)]
                    if not any(name in value for name in default_names):
                        errors.append(
                            f"{rel(task_path)}: {task_name}: {section_name}.{key} must reference a role default variable"
                        )

    assert errors == []


def test_docker_role_memory_defaults_use_absolute_mem_names() -> None:
    errors: list[str] = []
    old_suffixes = (
        "_mem_mb",
        "_memory",
        "_memory_reservation",
        "_memory_swap",
        "_memory_percent",
        "_memory_reservation_percent",
        "_memory_swap_percent",
    )

    for role_dir in docker_roles():
        defaults = role_defaults(role_dir)
        for name, value in defaults.items():
            if name.endswith(old_suffixes):
                errors.append(
                    f"{rel(role_dir / 'defaults' / 'main.yml')}: {name} must use *_mem_res, *_mem_lim, or *_mem_swp"
                )
            if (
                name.endswith(("_mem_res", "_mem_lim", "_mem_swp"))
                and isinstance(value, str)
                and "ansible_memtotal_mb" in value
            ):
                errors.append(
                    f"{rel(role_dir / 'defaults' / 'main.yml')}: {name} must be an absolute memory value, "
                    "not derived from host RAM"
                )

    assert errors == []


def test_docker_role_memory_defaults_use_standard_reservation_steps() -> None:
    errors: list[str] = []
    allowed_reservations = set(range(100, 1001, 100))

    for role_dir in docker_roles():
        defaults = role_defaults(role_dir)
        mem_names = sorted(name for name in defaults if name.endswith(("_mem_res", "_mem_lim", "_mem_swp")))
        for res_name in (name for name in mem_names if name.endswith("_mem_res")):
            prefix = res_name.removesuffix("_res")
            res_value = defaults.get(res_name)
            lim_value = defaults.get(f"{prefix}_lim")
            swp_value = defaults.get(f"{prefix}_swp")

            if not isinstance(res_value, str) or not res_value.endswith("M") or not res_value[:-1].isdigit():
                errors.append(f"{rel(role_dir / 'defaults' / 'main.yml')}: {res_name} must be an absolute M value")
                continue

            res_mb = int(res_value[:-1])
            if res_mb not in allowed_reservations:
                errors.append(
                    f"{rel(role_dir / 'defaults' / 'main.yml')}: {res_name} must be one of 100M, 200M, ..., 1000M"
                )

            if not isinstance(lim_value, str) or lim_value != f"{res_mb * 3 // 2}M":
                errors.append(f"{rel(role_dir / 'defaults' / 'main.yml')}: {prefix}_lim must be 1.5x {res_name}")

            if swp_value is not None and (not isinstance(swp_value, str) or swp_value != f"{res_mb * 2}M"):
                errors.append(f"{rel(role_dir / 'defaults' / 'main.yml')}: {prefix}_swp must be 2x {res_name}")

    assert errors == []


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


def test_redis_and_valkey_default_image_tags_are_separate() -> None:
    redis_defaults = role_defaults(REPO_ROOT / "roles" / "docker_redis")
    valkey_defaults = role_defaults(REPO_ROOT / "roles" / "docker_valkey")

    assert isinstance(redis_defaults["docker_redis_image_tag"], str)
    assert isinstance(valkey_defaults["docker_valkey_image_tag"], str)
    assert redis_defaults["docker_redis_image_tag"] != ""
    assert valkey_defaults["docker_valkey_image_tag"] != ""
    assert isinstance(redis_defaults["docker_redis_image_full"], str)
    assert isinstance(valkey_defaults["docker_valkey_image_full"], str)

    redis_image_full = redis_defaults["docker_redis_image_full"]
    valkey_image_full = valkey_defaults["docker_valkey_image_full"]

    assert "{{ docker_redis_image_tag }}" in redis_image_full
    assert "{{ docker_valkey_image_tag }}" in valkey_image_full
    assert "docker_valkey_image_tag" not in redis_image_full
    assert "docker_redis_image_tag" not in valkey_image_full
