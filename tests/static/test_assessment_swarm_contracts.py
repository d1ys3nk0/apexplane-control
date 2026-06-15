from __future__ import annotations

from collections.abc import Iterator, Mapping
from pathlib import Path
from typing import cast

import yaml


REPO_ROOT = Path(__file__).resolve().parents[2]
ASSESSMENT_DIR = REPO_ROOT / "roles" / "assessment"


def load_yaml(path: Path) -> object:
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def iter_assertions(value: object) -> Iterator[list[object]]:
    if isinstance(value, list):
        for item in value:
            yield from iter_assertions(item)
        return
    if not isinstance(value, Mapping):
        return

    task = cast("Mapping[str, object]", value)
    module = task.get("ansible.builtin.assert")
    if isinstance(module, Mapping):
        that = cast("Mapping[str, object]", module).get("that")
        if isinstance(that, list):
            yield cast("list[object]", that)
    for nested_key in ("block", "rescue", "always"):
        yield from iter_assertions(task.get(nested_key))


def test_assessment_exposes_exact_swarm_service_count_inputs() -> None:
    defaults = load_yaml(ASSESSMENT_DIR / "defaults" / "main.yml")
    assert isinstance(defaults, dict)
    defaults_data = cast("dict[str, object]", defaults)

    assert defaults_data["assessment_swarm_global_services"] == []
    assert defaults_data["assessment_swarm_replicated_services"] == []
    assert isinstance(defaults_data["assessment_swarm_log_services"], str)


def test_assessment_validates_exact_swarm_service_count_inputs() -> None:
    assertions = list(iter_assertions(load_yaml(ASSESSMENT_DIR / "tasks" / "validate.yml")))
    assertion_texts = ["\n".join(str(item) for item in assertion) for assertion in assertions]

    assert any("assessment_swarm_global_services is iterable" in text for text in assertion_texts)
    assert any("assessment_swarm_replicated_services is iterable" in text for text in assertion_texts)
    assert any("item.name is defined" in text and "item.replicas is defined" in text for text in assertion_texts)
