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


def test_nexus_waits_for_configured_http_port() -> None:
    defaults = cast("Mapping[str, object]", _load_yaml(REPO_ROOT / "roles" / "docker_nexus" / "defaults" / "main.yml"))
    tasks = list(_iter_tasks(_load_yaml(REPO_ROOT / "roles" / "docker_nexus" / "tasks" / "main.yml")))

    assert defaults["docker_nexus_http_port"] == NEXUS_DEFAULT_HTTP_PORT
    assert any(
        isinstance(task.get("ansible.builtin.wait_for"), Mapping)
        and cast("Mapping[str, object]", task["ansible.builtin.wait_for"]).get("port") == "{{ docker_nexus_http_port }}"
        for task in tasks
    )
