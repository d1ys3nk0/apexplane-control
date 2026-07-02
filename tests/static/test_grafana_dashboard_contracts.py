from __future__ import annotations

from collections.abc import Iterator, Mapping, Sequence
from pathlib import Path
from typing import cast

import yaml


REPO_ROOT = Path(__file__).resolve().parents[2]
DASHBOARDS_DIR = REPO_ROOT / "roles" / "docker_grafana" / "files" / "dashboards"
TOPOLOGY_FILTERS = ("realm", "platform", "cluster")


def _load_yaml(path: Path) -> object:
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def _dashboard_variables(dashboard: object) -> list[Mapping[str, object]]:
    if not isinstance(dashboard, Mapping):
        return []
    templating = dashboard.get("templating")
    if not isinstance(templating, Mapping):
        return []
    variables = templating.get("list")
    if not isinstance(variables, list):
        return []
    return [cast("Mapping[str, object]", item) for item in variables if isinstance(item, Mapping)]


def _variable_names(variables: Sequence[Mapping[str, object]]) -> list[str]:
    return [name for variable in variables if isinstance(name := variable.get("name"), str)]


def _variable_by_name(variables: Sequence[Mapping[str, object]]) -> dict[str, Mapping[str, object]]:
    return {name: variable for variable in variables if isinstance(name := variable.get("name"), str)}


def _query_source(variable: Mapping[str, object]) -> str:
    query = variable.get("query")
    if isinstance(query, Mapping):
        for key in ("query", "stream"):
            value = query.get(key)
            if isinstance(value, str):
                return value
    definition = variable.get("definition")
    return definition if isinstance(definition, str) else ""


def _target_expressions(value: object) -> Iterator[str]:
    if isinstance(value, Mapping):
        expr = value.get("expr")
        if isinstance(expr, str):
            yield expr
        for nested in value.values():
            yield from _target_expressions(nested)
        return
    if isinstance(value, list):
        for item in value:
            yield from _target_expressions(item)


def _missing_filters(source: str, filters: Sequence[str]) -> list[str]:
    return [name for name in filters if f'{name}=~"${name}"' not in source]


def _unexpected_filters(source: str, filters: Sequence[str]) -> list[str]:
    return [name for name in filters if f'{name}=~"${name}"' in source]


def test_realm_dashboards_use_topology_filter_cascade() -> None:
    errors: list[str] = []

    for path in sorted(DASHBOARDS_DIR.glob("*.yaml")):
        dashboard = _load_yaml(path)
        variables = _dashboard_variables(dashboard)
        names = _variable_names(variables)
        if "realm" not in names:
            continue

        relpath = path.relative_to(REPO_ROOT)
        variables_by_name = _variable_by_name(variables)
        realm_index = names.index("realm")
        if names[realm_index : realm_index + len(TOPOLOGY_FILTERS)] != list(TOPOLOGY_FILTERS):
            errors.append(f"{relpath}: realm filters must be ordered as realm, platform, cluster")

        for name, label in (("platform", "Platform"), ("cluster", "Cluster")):
            variable = variables_by_name.get(name)
            if variable is None:
                errors.append(f"{relpath}: missing {name} variable")
                continue
            current = variable.get("current")
            if variable.get("label") != label:
                errors.append(f"{relpath}: {name} variable must be labeled {label}")
            if variable.get("includeAll") is not True:
                errors.append(f"{relpath}: {name} variable must include All")
            if not isinstance(current, Mapping) or current.get("text") != "All" or current.get("value") != "$__all":
                errors.append(f"{relpath}: {name} variable must default to All")

        for name, required, forbidden in (
            ("realm", ("world",), ("realm", "platform", "cluster")),
            ("platform", ("world", "realm"), ("platform", "cluster")),
            ("cluster", ("world", "realm", "platform"), ("cluster",)),
        ):
            source = _query_source(variables_by_name[name])
            missing = _missing_filters(source, required)
            unexpected = _unexpected_filters(source, forbidden)
            if missing:
                errors.append(f"{relpath}: {name} query is missing topology filters: {', '.join(missing)}")
            if unexpected:
                errors.append(f"{relpath}: {name} query contains premature filters: {', '.join(unexpected)}")

        cluster_index = names.index("cluster")
        for variable in variables[cluster_index + 1 :]:
            if variable.get("type") != "query":
                continue
            source = _query_source(variable)
            if not source:
                continue
            missing = _missing_filters(source, ("world", "realm", "platform", "cluster"))
            if missing:
                errors.append(
                    f"{relpath}: {variable.get('name')} query is missing topology filters: {', '.join(missing)}"
                )

        for expr in _target_expressions(dashboard):
            if 'realm=~"$realm"' not in expr:
                continue
            missing = _missing_filters(expr, ("platform", "cluster"))
            if missing:
                errors.append(f"{relpath}: panel query is missing topology filters: {', '.join(missing)}")

    assert errors == []
