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


def rel(path: Path) -> str:
    return str(path.relative_to(REPO_ROOT))


def role_task_files() -> Iterator[Path]:
    yield from sorted((REPO_ROOT / "roles").glob("**/*.yml"))


def service_module(task: Mapping[str, object]) -> Mapping[str, object]:
    for module_name in ("ansible.builtin.service", "ansible.builtin.systemd", "ansible.builtin.systemd_service"):
        module = task.get(module_name)
        if isinstance(module, Mapping):
            return cast("Mapping[str, object]", module)
    return {}


def has_systemctl_is_active(task: Mapping[str, object], service_name: object) -> bool:
    command = task.get("ansible.builtin.command")
    if not isinstance(command, Mapping):
        return False

    command = cast("Mapping[str, object]", command)
    argv = command.get("argv")
    return isinstance(argv, list) and argv[:3] == ["systemctl", "is-active", service_name]


def has_docker_container_info(task: Mapping[str, object], container_name: object) -> bool:
    module = task.get("community.docker.docker_container_info")
    if not isinstance(module, Mapping):
        return False

    module = cast("Mapping[str, object]", module)
    return module.get("name") == container_name


def has_docker_container_info_or_include(task_path: Path, task: Mapping[str, object], container_name: object) -> bool:
    if has_docker_container_info(task, container_name):
        return True

    include_tasks = task.get("ansible.builtin.include_tasks")
    if not isinstance(include_tasks, str):
        return False

    include_path = task_path.parent / include_tasks
    if not include_path.is_file():
        return False

    return any(
        has_docker_container_info(included_task, container_name)
        for included_task in iter_tasks(load_yaml(include_path))
    )


def task_include_file(task: Mapping[str, object]) -> str | None:
    include_tasks = task.get("ansible.builtin.include_tasks")
    return include_tasks if isinstance(include_tasks, str) else None


def role_main_verifies_included_container(task_path: Path, container_name: object) -> bool:
    main_path = task_path.parent / "main.yml"
    if task_path.name == "main.yml" or not main_path.is_file():
        return False

    main_tasks = list(iter_tasks(load_yaml(main_path)))
    for index, task in enumerate(main_tasks):
        if task_include_file(task) != task_path.name:
            continue
        return any(
            has_docker_container_info_or_include(main_path, next_task, container_name)
            for next_task in main_tasks[index + 1 :]
        )

    return False


def test_started_or_restarted_services_verify_active_state() -> None:
    errors: list[str] = []

    for task_path in role_task_files():
        tasks = list(iter_tasks(load_yaml(task_path)))
        for index, task in enumerate(tasks):
            module = service_module(task)
            if module.get("state") not in ("started", "restarted"):
                continue
            if task.get("check_mode") is True:
                continue

            service_name = module.get("name")
            task_name = task.get("name", "<unnamed>")
            if not any(has_systemctl_is_active(next_task, service_name) for next_task in tasks[index + 1 :]):
                errors.append(f"{rel(task_path)}: {task_name}: started services must verify systemctl is-active")

    assert errors == []


def test_long_running_docker_containers_verify_running_state() -> None:
    errors: list[str] = []

    for task_path in sorted((REPO_ROOT / "roles").glob("docker_*/tasks/*.yml")):
        tasks = list(iter_tasks(load_yaml(task_path)))
        for index, task in enumerate(tasks):
            container = task.get("community.docker.docker_container")
            if not isinstance(container, Mapping) or "restart_policy" not in container:
                continue

            container = cast("Mapping[str, object]", container)
            container_name = container.get("name")
            task_name = task.get("name", "<unnamed>")
            if not any(
                has_docker_container_info_or_include(task_path, next_task, container_name)
                for next_task in tasks[index + 1 :]
            ) and not role_main_verifies_included_container(task_path, container_name):
                errors.append(f"{rel(task_path)}: {task_name}: long-running containers must verify State.Running")

    assert errors == []
