from __future__ import annotations

from collections.abc import Iterator, Mapping
from pathlib import Path
from typing import cast

import yaml


REPO_ROOT = Path(__file__).resolve().parents[2]
NEXUS_DEFAULT_HTTP_PORT = 8081


def _load_yaml(path: Path) -> object:
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def _iter_tasks(value: object) -> Iterator[Mapping[str, object]]:
    if isinstance(value, list):
        for item in value:
            yield from _iter_tasks(item)
        return
    if not isinstance(value, Mapping):
        return

    task = cast("Mapping[str, object]", value)
    yield task
    for nested_key in ("block", "rescue", "always"):
        yield from _iter_tasks(task.get(nested_key))


def test_docker_image_tag_defaults_are_pinned() -> None:
    errors: list[str] = []

    for defaults_path in sorted((REPO_ROOT / "roles").glob("docker_*/defaults/main.yml")):
        defaults = _load_yaml(defaults_path)
        if not isinstance(defaults, Mapping):
            continue
        for name, value in defaults.items():
            if isinstance(name, str) and name.endswith("_image_tag") and value == "latest":
                errors.append(f"{defaults_path.relative_to(REPO_ROOT)}: {name} must not use latest")

    assert errors == []


def test_direct_artifact_downloads_define_checksum() -> None:
    expected_get_url_tasks = {
        REPO_ROOT / "roles" / "cadvisor" / "tasks" / "setup_install.yml": "Download cadvisor binary",
        REPO_ROOT / "roles" / "docker_ctop" / "tasks" / "main.yml": "Download ctop binary",
        REPO_ROOT / "roles" / "mattermost" / "tasks" / "setup_install.yml": "Download Mattermost Team Edition archive",
        REPO_ROOT / "roles" / "promtail" / "tasks" / "setup_install.yml": "Download promtail deb package",
        REPO_ROOT / "roles" / "node_exporter" / "tasks" / "setup_install.yml": "Download node_exporter archive",
    }
    errors: list[str] = []

    for path, task_name in expected_get_url_tasks.items():
        tasks = list(_iter_tasks(_load_yaml(path)))
        task = next((item for item in tasks if item.get("name") == task_name), {})
        get_url = task.get("ansible.builtin.get_url")
        if not isinstance(get_url, Mapping) or "checksum" not in get_url:
            errors.append(f"{path.relative_to(REPO_ROOT)}: {task_name} must set get_url.checksum")

    assert errors == []


def test_nexus_waits_for_configured_http_port() -> None:
    defaults = cast("Mapping[str, object]", _load_yaml(REPO_ROOT / "roles" / "docker_nexus" / "defaults" / "main.yml"))
    tasks = list(_iter_tasks(_load_yaml(REPO_ROOT / "roles" / "docker_nexus" / "tasks" / "main.yml")))

    assert defaults["docker_nexus_http_port"] == NEXUS_DEFAULT_HTTP_PORT
    assert any(
        isinstance(task.get("ansible.builtin.wait_for"), Mapping)
        and cast("Mapping[str, object]", task["ansible.builtin.wait_for"]).get("port") == "{{ docker_nexus_http_port }}"
        for task in tasks
    )
