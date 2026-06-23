from __future__ import annotations

import re
from collections import Counter
from collections.abc import Iterable, Iterator, Mapping
from dataclasses import dataclass
from typing import TYPE_CHECKING, cast

import yaml
from jinja2 import Environment, TemplateError, meta


if TYPE_CHECKING:
    from pathlib import Path


VAR_NAME_RE = re.compile(r"\b[A-Za-z_][A-Za-z0-9_]*\b")
TOP_LEVEL_VAR_RE = re.compile(r"^(?P<name>[A-Za-z_][A-Za-z0-9_]*):(?P<value>.*)$")
JINJA_BLOCK_RE = re.compile(r"({{.*?}}|{%.*?%})", re.DOTALL)
QUOTED_STRING_RE = re.compile(r"""'(?:\\.|[^'])*'|"(?:\\.|[^"])*" """.strip())
FALLBACK_VAR_RE = re.compile(r"(?<![.\w])(?P<name>[A-Za-z_][A-Za-z0-9_]*)\b")
YAML_ALIAS_RE = re.compile(r"(?<![A-Za-z0-9_])\*(?P<name>[A-Za-z_][A-Za-z0-9_]*)\b")
FORBIDDEN_PREFIXES = ("gv_", "iv_", "vv_", "c_")
YAML_SUFFIXES = {".yml", ".yaml"}
NON_ANSIBLE_ROLE_YAML_DIRS = {("docker_grafana", "files", "dashboards")}
PROMETHEUS_ALERT_TOPOLOGY_LABELS = {"cluster", "platform", "realm", "world"}
PROMETHEUS_ALERT_REQUIRED_ANNOTATIONS = {"rule", "summary"}
PROMETHEUS_ALERT_FORBIDDEN_ANNOTATIONS = {"current", "description", "expected"}
EXPRESSION_KEYS = {
    "changed_when",
    "failed_when",
    "loop",
    "that",
    "until",
    "when",
    "with_dict",
    "with_fileglob",
    "with_first_found",
    "with_items",
    "with_list",
    "with_nested",
    "with_sequence",
    "with_subelements",
}
EXPRESSION_LIST_ITEM_KEYS = {
    "changed_when",
    "failed_when",
    "that",
    "until",
    "when",
}
ALLOWED_GLOBALS = {
    "ansible_check_mode",
    "ansible_diff_mode",
    "ansible_facts",
    "ansible_forks",
    "ansible_inventory_sources",
    "ansible_limit",
    "ansible_loop",
    "ansible_loop_var",
    "ansible_play_batch",
    "ansible_play_hosts",
    "ansible_play_hosts_all",
    "ansible_play_name",
    "ansible_play_role_names",
    "ansible_playbook_python",
    "ansible_role_name",
    "ansible_run_tags",
    "ansible_skip_tags",
    "ansible_verbosity",
    "environment",
    "group_names",
    "groups",
    "hostvars",
    "inventory_dir",
    "inventory_file",
    "inventory_hostname",
    "inventory_hostname_short",
    "lookup",
    "omit",
    "play_hosts",
    "playbook_dir",
    "q",
    "query",
    "role_name",
    "role_names",
    "role_path",
    "vars",
}
IGNORED_JINJA_NAMES = {
    "and",
    "ansible",
    "as",
    "attribute",
    "basename",
    "boolean",
    "bool",
    "changed",
    "combine",
    "default",
    "defined",
    "dict2items",
    "difference",
    "dict",
    "do",
    "else",
    "elif",
    "end",
    "endif",
    "endfor",
    "false",
    "first",
    "float",
    "for",
    "from_json",
    "from_yaml",
    "hash",
    "hashtype",
    "if",
    "in",
    "indent",
    "intersect",
    "int",
    "is",
    "iterable",
    "join",
    "json",
    "last",
    "length",
    "list",
    "lower",
    "map",
    "mapping",
    "match",
    "none",
    "not",
    "or",
    "password_hash",
    "product",
    "quote",
    "range",
    "regex_search",
    "regex_replace",
    "reject",
    "salt",
    "select",
    "selectattr",
    "set",
    "sort",
    "subelements",
    "string",
    "sort_keys",
    "ternary",
    "to_json",
    "to_nice_json",
    "to_nice_yaml",
    "trim",
    "true",
    "type_debug",
    "undefined",
    "unique",
    "upper",
    "url",
}


@dataclass(frozen=True)
class DefaultsContract:
    declared: set[str]
    required: set[str]
    errors: list[str]


@dataclass(frozen=True)
class VariableReference:
    path: Path
    name: str
    line_number: int


def _rel_path(path: Path, repo_root: Path) -> str:
    return str(path.relative_to(repo_root))


def _line_number_for(path: Path, variable_name: str) -> int:
    pattern = re.compile(rf"\b{re.escape(variable_name)}\b")
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if pattern.search(line):
            return line_number
    return 1


def _definition_line_numbers(path: Path, variable_names: Iterable[str]) -> dict[str, int]:
    names = set(variable_names)
    line_numbers: dict[str, int] = {}
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        match = TOP_LEVEL_VAR_RE.match(line)
        if match is not None and match.group("name") in names:
            line_numbers[match.group("name")] = line_number
    return line_numbers


def _strip_inline_comment(raw: str) -> str:
    quote: str | None = None
    for index, char in enumerate(raw):
        if char in {"'", '"'}:
            quote = None if quote == char else char
        if char == "#" and quote is None:
            return raw[:index].strip()
    return raw.strip()


def _load_yaml(path: Path) -> object | None:
    try:
        return yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError:
        return None


def _read_defaults(role_dir: Path, repo_root: Path) -> DefaultsContract:
    defaults_path = role_dir / "defaults" / "main.yml"
    if not defaults_path.is_file():
        return DefaultsContract(declared=set(), required=set(), errors=[])

    raw_defaults = _load_yaml(defaults_path)
    if not isinstance(raw_defaults, Mapping):
        rel_defaults = _rel_path(defaults_path, repo_root)
        return DefaultsContract(
            declared=set(), required=set(), errors=[f"{rel_defaults}:1: defaults/main.yml must be a mapping"]
        )

    defaults_map = cast("Mapping[object, object]", raw_defaults)
    declared = {key for key in defaults_map if isinstance(key, str)}
    required: set[str] = set()
    errors: list[str] = []
    seen_top_level: set[str] = set()
    for line_number, line in enumerate(defaults_path.read_text(encoding="utf-8").splitlines(), start=1):
        match = TOP_LEVEL_VAR_RE.match(line)
        if match is None:
            continue
        name = match.group("name")
        if name not in declared:
            continue
        seen_top_level.add(name)
        raw_value = _strip_inline_comment(match.group("value"))
        if raw_value == "~":
            required.add(name)
        elif defaults_map.get(name) is None:
            rel_defaults = _rel_path(defaults_path, repo_root)
            errors.append(f"{rel_defaults}:{line_number}: {name} required-variable defaults must use ~")

    for name in declared - seen_top_level:
        if defaults_map.get(name) is None:
            rel_defaults = _rel_path(defaults_path, repo_root)
            errors.append(f"{rel_defaults}:1: {name} required-variable defaults must use ~")

    return DefaultsContract(declared=declared, required=required, errors=errors)


def _jinja_variables_from_template(env: Environment, text: str) -> set[str]:
    try:
        parsed = env.parse(text)
        return set(meta.find_undeclared_variables(parsed))
    except TemplateError:
        return _fallback_variables_from_template(text)


def _jinja_variables_from_expression(env: Environment, text: str) -> set[str]:
    try:
        parsed = env.parse(f"{{{{ {text} }}}}")
        return set(meta.find_undeclared_variables(parsed))
    except TemplateError:
        return _fallback_variables_from_expression(text)


def _fallback_variables_from_template(text: str) -> set[str]:
    variables: set[str] = set()
    for match in JINJA_BLOCK_RE.finditer(text):
        block = match.group(0)
        variables.update(_fallback_variables_from_expression(block[2:-2]))
    return variables


def _fallback_variables_from_expression(text: str) -> set[str]:
    without_strings = QUOTED_STRING_RE.sub("", text)
    return {
        match.group("name")
        for match in FALLBACK_VAR_RE.finditer(without_strings)
        if match.group("name") not in IGNORED_JINJA_NAMES
    }


def _extract_string_variables(env: Environment, text: str, *, expression_context: bool) -> set[str]:
    variables = _jinja_variables_from_template(env, text)
    if expression_context:
        variables.update(_jinja_variables_from_expression(env, text))
    return variables


def _iter_yaml_strings(value: object, *, parent_key: str | None = None) -> Iterator[tuple[str, bool]]:
    if isinstance(value, str):
        yield value, parent_key in EXPRESSION_KEYS
        return
    if isinstance(value, list):
        item_parent_key = parent_key if parent_key in EXPRESSION_LIST_ITEM_KEYS else None
        for item in value:
            yield from _iter_yaml_strings(item, parent_key=item_parent_key)
        return
    if isinstance(value, Mapping):
        for key, item in value.items():
            key_text = key if isinstance(key, str) else parent_key
            yield from _iter_yaml_strings(item, parent_key=key_text)


def _set_fact_keys(task: Mapping[object, object]) -> set[str]:
    keys: set[str] = set()
    for module_name in ("ansible.builtin.set_fact", "set_fact"):
        module_args = task.get(module_name)
        if isinstance(module_args, Mapping):
            keys.update(key for key in module_args if isinstance(key, str) and key != "cacheable")
    return keys


def _set_fact_items(task: Mapping[object, object]) -> Iterator[tuple[str, object]]:
    for module_name in ("ansible.builtin.set_fact", "set_fact"):
        module_args = task.get(module_name)
        if isinstance(module_args, Mapping):
            yield from (
                (key, value)
                for key, value in cast("Mapping[object, object]", module_args).items()
                if isinstance(key, str) and key != "cacheable"
            )


def _top_level_yaml_keys(path: Path) -> set[str]:
    if not path.is_file():
        return set()
    data = _load_yaml(path)
    if not isinstance(data, Mapping):
        return set()
    return {key for key in data if isinstance(key, str)}


def _iter_task_mappings(value: object) -> Iterator[Mapping[object, object]]:
    if isinstance(value, list):
        for item in value:
            yield from _iter_task_mappings(item)
        return
    if not isinstance(value, Mapping):
        return

    task = cast("Mapping[object, object]", value)
    yield task
    for nested_key in ("block", "rescue", "always"):
        yield from _iter_task_mappings(task.get(nested_key))


def _collect_local_variables(value: object) -> set[str]:
    locals_: set[str] = set()
    if isinstance(value, list):
        for item in value:
            locals_.update(_collect_local_variables(item))
        return locals_
    if not isinstance(value, Mapping):
        return locals_

    task = cast("Mapping[object, object]", value)
    register = task.get("register")
    if isinstance(register, str):
        locals_.add(register)

    task_vars = task.get("vars")
    if isinstance(task_vars, Mapping):
        locals_.update(key for key in task_vars if isinstance(key, str))

    loop_control = task.get("loop_control")
    if isinstance(loop_control, Mapping):
        loop_control_map = cast("Mapping[object, object]", loop_control)
        loop_var = loop_control_map.get("loop_var")
        if isinstance(loop_var, str):
            locals_.add(loop_var)

    locals_.update(_set_fact_keys(task))
    for item in task.values():
        locals_.update(_collect_local_variables(item))
    return locals_


def _iter_role_files(role_dir: Path) -> Iterator[Path]:
    for path in sorted(role_dir.rglob("*")):
        relative_parts = path.relative_to(role_dir).parts
        role_yaml_dir = (role_dir.name, *relative_parts[:-1])
        if path.is_file() and "__pycache__" not in path.parts and role_yaml_dir not in NON_ANSIBLE_ROLE_YAML_DIRS:
            yield path


def _null_literal_errors(role_dir: Path, repo_root: Path) -> list[str]:
    errors: list[str] = []
    for path in _iter_role_files(role_dir):
        if path.suffix not in YAML_SUFFIXES:
            continue
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            raw_value = _strip_inline_comment(line).strip()
            if re.search(r"(^|[:\[, -])null($|[\]}, ])", raw_value) is not None:
                errors.append(f"{_rel_path(path, repo_root)}:{line_number}: use ~ instead of null")
    return errors


def _collect_role_locals(role_dir: Path) -> set[str]:
    locals_ = {"item"}
    vars_path = role_dir / "vars" / "main.yml"
    if vars_path.is_file():
        locals_.update(_top_level_yaml_keys(vars_path))
    for path in _iter_role_files(role_dir):
        if path.suffix not in YAML_SUFFIXES:
            continue
        data = _load_yaml(path)
        if data is not None:
            locals_.update(_collect_local_variables(data))
    return locals_


def _iter_file_references(path: Path, env: Environment) -> Iterator[VariableReference]:
    variables: set[str] = set()
    file_text = path.read_text(encoding="utf-8")
    data = _load_yaml(path) if path.suffix in YAML_SUFFIXES else None
    if data is None:
        variables.update(_jinja_variables_from_template(env, file_text))
    else:
        for item_text, expression_context in _iter_yaml_strings(data):
            variables.update(_extract_string_variables(env, item_text, expression_context=expression_context))
    if path.suffix in YAML_SUFFIXES:
        variables.update(match.group("name") for match in YAML_ALIAS_RE.finditer(file_text))

    for name in sorted(variables):
        yield VariableReference(path=path, name=name, line_number=_line_number_for(path, name))


def _is_allowed_global(name: str) -> bool:
    return name.startswith(("ansible_", "_")) or name in ALLOWED_GLOBALS or name in IGNORED_JINJA_NAMES


def _is_known_local(name: str, role_locals: Iterable[str]) -> bool:
    return name in role_locals


def _validate_required_variables(
    *,
    role_dir: Path,
    repo_root: Path,
    required_variables: Iterable[str],
) -> list[str]:
    validate_path = role_dir / "tasks" / "validate.yml"
    required = sorted(required_variables)
    if not required:
        return []
    if not validate_path.is_file():
        rel_role = _rel_path(role_dir, repo_root)
        return [f"{rel_role}/tasks/validate.yml:1: required variables need tasks/validate.yml"]

    validate_text = validate_path.read_text(encoding="utf-8")
    errors: list[str] = []
    for name in required:
        validates_not_none = re.search(rf"\b{re.escape(name)}\b\s+is\s+not\s+none", validate_text) is not None
        validates_optional_none = re.search(rf"\b{re.escape(name)}\b\s+is\s+none\s+or\b", validate_text) is not None
        if not validates_not_none and not validates_optional_none:
            rel_validate = _rel_path(validate_path, repo_root)
            errors.append(f"{rel_validate}:1: required variable {name} must be validated with '{name} is not none'")
        if re.search(rf"\b{re.escape(name)}\b\s*\|\s*string\s*\|\s*length\s*>\s*0", validate_text) is None:
            rel_validate = _rel_path(validate_path, repo_root)
            errors.append(
                f"{rel_validate}:1: required variable {name} must be validated with '{name} | string | length > 0'"
            )
    return errors


def _unused_default_errors(role_dir: Path, repo_root: Path, env: Environment, defaults: DefaultsContract) -> list[str]:
    defaults_path = role_dir / "defaults" / "main.yml"
    if not defaults.declared or not defaults_path.is_file():
        return []

    references: set[str] = set()
    for path in _iter_role_files(role_dir):
        if "files" in path.relative_to(role_dir).parts:
            continue
        references.update(reference.name for reference in _iter_file_references(path, env))

    line_numbers = _definition_line_numbers(defaults_path, defaults.declared)
    rel_defaults = _rel_path(defaults_path, repo_root)
    role_name = role_dir.name
    return [
        f"{rel_defaults}:{line_numbers.get(name, 1)}: {name} is declared but not used in role {role_name}"
        for name in sorted(defaults.declared - references)
    ]


def _cluster_context_naming_errors(role_dir: Path, repo_root: Path, defaults: DefaultsContract) -> list[str]:
    defaults_path = role_dir / "defaults" / "main.yml"
    if not defaults.declared or not defaults_path.is_file():
        return []

    role_name = role_dir.name
    if role_name == "alloy":
        return []

    forbidden_names = {
        f"{role_name}_platform": f"{role_name}_cluster_platform",
        f"{role_name}_realm": f"{role_name}_cluster_realm",
    }
    line_numbers = _definition_line_numbers(defaults_path, defaults.declared)
    rel_defaults = _rel_path(defaults_path, repo_root)
    return [
        f"{rel_defaults}:{line_numbers.get(name, 1)}: use {replacement} for cluster context instead of {name}"
        for name, replacement in forbidden_names.items()
        if name in defaults.declared
    ]


def _swarm_service_mode_contract_errors(role_dir: Path, repo_root: Path, defaults: DefaultsContract) -> list[str]:
    defaults_path = role_dir / "defaults" / "main.yml"
    if role_dir.name == "docker_swarm" or not defaults.declared or not defaults_path.is_file():
        return []

    line_numbers = _definition_line_numbers(defaults_path, defaults.declared)
    rel_defaults = _rel_path(defaults_path, repo_root)
    return [
        f"{rel_defaults}:{line_numbers.get(name, 1)}: use an explicit boolean enabled flag instead of exposing {name}"
        for name in sorted(defaults.declared)
        if name.endswith("_swarm_mode")
    ]


def _nolog_contract_errors(role_dir: Path, repo_root: Path, defaults: DefaultsContract) -> list[str]:
    role_name = role_dir.name
    defaults_path = role_dir / "defaults" / "main.yml"
    vars_path = role_dir / "vars" / "main.yml"
    expected_value = f"{{{{ {role_name}_nolog }}}}"
    errors: list[str] = []
    nolog_name = f"{role_name}_nolog"
    ci_mode_name = f"{role_name}_ci_mode"
    debug_mode_name = f"{role_name}_debug_mode"

    vars_map = _load_yaml(vars_path) if vars_path.is_file() else {}
    vars_values = cast("Mapping[object, object]", vars_map) if isinstance(vars_map, Mapping) else {}
    vars_declared = {key for key in vars_values if isinstance(key, str)}
    declared = defaults.declared | vars_declared

    if nolog_name in declared and defaults_path.is_file():
        defaults_map = _load_yaml(defaults_path)
        defaults_values = cast("Mapping[object, object]", defaults_map) if isinstance(defaults_map, Mapping) else {}
        variable_values = {**defaults_values, **vars_values}
        defaults_line_numbers = _definition_line_numbers(defaults_path, defaults.declared)
        vars_line_numbers = _definition_line_numbers(vars_path, vars_declared) if vars_path.is_file() else {}
        variable_line_numbers = {**defaults_line_numbers, **vars_line_numbers}
        variable_paths = {**dict.fromkeys(defaults.declared, defaults_path), **dict.fromkeys(vars_declared, vars_path)}
        expected_ci_mode = "{{ lookup('env', 'CI') | default('0', true) in ['1', 'true'] }}"
        expected_debug_mode = "{{ lookup('env', 'DEBUG') | default('0', true) in ['1', 'true'] }}"
        expected_nolog = f"{{{{ ({ci_mode_name} | bool) and not ({debug_mode_name} | bool) }}}}"
        nolog_line_number = variable_line_numbers.get(nolog_name, 1)
        nolog_rel_path = _rel_path(variable_paths.get(nolog_name, defaults_path), repo_root)
        errors.extend(
            f"{nolog_rel_path}:{nolog_line_number}: {nolog_name} requires {mode_name} in role variables"
            for mode_name in (ci_mode_name, debug_mode_name)
            if mode_name not in declared
        )
        if ci_mode_name in declared and variable_values.get(ci_mode_name) != expected_ci_mode:
            rel_path = _rel_path(variable_paths.get(ci_mode_name, defaults_path), repo_root)
            errors.append(
                f"{rel_path}:{variable_line_numbers.get(ci_mode_name, 1)}: define {ci_mode_name} from the CI environment variable"
            )
        if debug_mode_name in declared and variable_values.get(debug_mode_name) != expected_debug_mode:
            rel_path = _rel_path(variable_paths.get(debug_mode_name, defaults_path), repo_root)
            errors.append(
                f"{rel_path}:{variable_line_numbers.get(debug_mode_name, 1)}: define {debug_mode_name} from the DEBUG "
                "environment variable"
            )
        if variable_values.get(nolog_name) != expected_nolog:
            errors.append(
                f"{nolog_rel_path}:{nolog_line_number}: define {nolog_name} from {ci_mode_name} and {debug_mode_name}"
            )

    for path in _iter_role_files(role_dir):
        if "files" in path.relative_to(role_dir).parts or path.suffix not in YAML_SUFFIXES:
            continue
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            stripped = line.strip()
            if not stripped.startswith("no_log:"):
                continue
            value = _strip_inline_comment(stripped.removeprefix("no_log:")).strip()
            if value in {f"'{expected_value}'", f'"{expected_value}"'}:
                continue
            errors.append(f"{_rel_path(path, repo_root)}:{line_number}: use no_log: '{{{{ {role_name}_nolog }}}}'")
    return errors


def _task_accumulation_errors(role_dir: Path, repo_root: Path) -> list[str]:
    vars_declared = _top_level_yaml_keys(role_dir / "vars" / "main.yml")
    accumulation_counts: Counter[str] = Counter()
    accumulation_paths: dict[str, Path] = {}

    for path in _iter_role_files(role_dir):
        if "tasks" not in path.relative_to(role_dir).parts or path.suffix not in YAML_SUFFIXES:
            continue
        data = _load_yaml(path)
        if data is None:
            continue
        for task in _iter_task_mappings(data):
            for name, value in _set_fact_items(task):
                if not isinstance(value, str):
                    continue
                if re.search(rf"\b{re.escape(name)}\b\s*\+", value) is None:
                    continue
                accumulation_counts[name] += 1
                accumulation_paths.setdefault(name, path)

    return [
        f"{_rel_path(accumulation_paths[name], repo_root)}:{_line_number_for(accumulation_paths[name], name)}: "
        f"derive repeated accumulated variable {name} in roles/{role_dir.name}/vars/main.yml"
        for name, count in sorted(accumulation_counts.items())
        if count > 1 and name not in vars_declared
    ]


def _prometheus_alert_topology_label_errors(role_dir: Path, repo_root: Path) -> list[str]:
    if role_dir.name != "docker_prometheus":
        return []

    alerts_path = role_dir / "templates" / "alerts.yml.j2"
    if not alerts_path.is_file():
        return []

    errors: list[str] = []
    current_alert: str | None = None
    current_line_number = 1
    current_labels: set[str] | None = None
    labels_indent = -1

    def finish_alert() -> None:
        if current_alert is None:
            return
        missing = PROMETHEUS_ALERT_TOPOLOGY_LABELS - (current_labels or set())
        if missing:
            errors.append(
                f"{_rel_path(alerts_path, repo_root)}:{current_line_number}: alert {current_alert} labels must include "
                f"{', '.join(sorted(PROMETHEUS_ALERT_TOPOLOGY_LABELS))}"
            )

    for line_number, line in enumerate(alerts_path.read_text(encoding="utf-8").splitlines(), start=1):
        alert_match = re.match(r"^\s*-\s+alert:\s+(?P<name>[A-Za-z0-9_]+)\s*$", line)
        if alert_match is not None:
            finish_alert()
            current_alert = alert_match.group("name")
            current_line_number = line_number
            current_labels = None
            labels_indent = -1
            continue

        if current_alert is None:
            continue

        if re.match(r"^\s*labels:\s*$", line) is not None:
            current_labels = set()
            labels_indent = len(line) - len(line.lstrip())
            continue

        if current_labels is None or labels_indent < 0:
            continue

        line_indent = len(line) - len(line.lstrip())
        if line.strip() and line_indent <= labels_indent:
            labels_indent = -1
            continue

        label_match = re.match(r"^\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*):", line)
        if label_match is not None:
            current_labels.add(label_match.group("name"))

    finish_alert()
    return errors


def _prometheus_alert_annotation_errors(role_dir: Path, repo_root: Path) -> list[str]:
    if role_dir.name != "docker_prometheus":
        return []

    alerts_path = role_dir / "templates" / "alerts.yml.j2"
    if not alerts_path.is_file():
        return []

    errors: list[str] = []
    current_alert: str | None = None
    current_line_number = 1
    current_annotations: set[str] | None = None
    annotations_indent = -1

    def finish_alert() -> None:
        if current_alert is None:
            return
        missing = PROMETHEUS_ALERT_REQUIRED_ANNOTATIONS - (current_annotations or set())
        if missing:
            errors.append(
                f"{_rel_path(alerts_path, repo_root)}:{current_line_number}: alert {current_alert} annotations must "
                f"include {', '.join(sorted(PROMETHEUS_ALERT_REQUIRED_ANNOTATIONS))}"
            )

    for line_number, line in enumerate(alerts_path.read_text(encoding="utf-8").splitlines(), start=1):
        if re.match(r"^\s*{%\s*endraw\s*%}\s*$", line) is not None:
            break

        alert_match = re.match(r"^\s*-\s+alert:\s+(?P<name>[A-Za-z0-9_]+)\s*$", line)
        if alert_match is not None:
            finish_alert()
            current_alert = alert_match.group("name")
            current_line_number = line_number
            current_annotations = None
            annotations_indent = -1
            continue

        if current_alert is None:
            continue

        if re.match(r"^\s*annotations:\s*$", line) is not None:
            current_annotations = set()
            annotations_indent = len(line) - len(line.lstrip())
            continue

        if current_annotations is None or annotations_indent < 0:
            continue

        line_indent = len(line) - len(line.lstrip())
        if line.strip() and line_indent <= annotations_indent:
            annotations_indent = -1
            continue

        annotation_match = re.match(r"^\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*):", line)
        if annotation_match is None:
            continue

        annotation_name = annotation_match.group("name")
        current_annotations.add(annotation_name)
        if annotation_name in PROMETHEUS_ALERT_FORBIDDEN_ANNOTATIONS:
            errors.append(
                f"{_rel_path(alerts_path, repo_root)}:{line_number}: alert {current_alert} annotations must use "
                "summary and rule instead of description, current, or expected"
            )

    finish_alert()
    return errors


def _role_errors(role_dir: Path, repo_root: Path, env: Environment) -> list[str]:
    role_name = role_dir.name
    role_prefix = f"{role_name}_"
    defaults = _read_defaults(role_dir, repo_root)
    role_locals = _collect_role_locals(role_dir)
    errors = [*defaults.errors, *_null_literal_errors(role_dir, repo_root)]

    for path in _iter_role_files(role_dir):
        if "files" in path.relative_to(role_dir).parts:
            continue
        for reference in _iter_file_references(path, env):
            name = reference.name
            rel_file = _rel_path(reference.path, repo_root)
            if name.startswith(FORBIDDEN_PREFIXES):
                errors.append(
                    f"{rel_file}:{reference.line_number}: {name} must not be referenced directly inside role {role_name}"
                )
                continue
            if _is_allowed_global(name) or _is_known_local(name, role_locals):
                continue
            if name.startswith(role_prefix):
                if name not in defaults.declared:
                    errors.append(
                        f"{rel_file}:{reference.line_number}: {name} must be declared in roles/{role_name}/defaults/main.yml"
                    )
                continue
            if VAR_NAME_RE.fullmatch(name) is not None:
                errors.append(
                    f"{rel_file}:{reference.line_number}: {name} is not an allowed role input for role {role_name}"
                )

    errors.extend(
        _validate_required_variables(
            role_dir=role_dir,
            repo_root=repo_root,
            required_variables=defaults.required,
        )
    )
    errors.extend(_unused_default_errors(role_dir, repo_root, env, defaults))
    errors.extend(_cluster_context_naming_errors(role_dir, repo_root, defaults))
    errors.extend(_swarm_service_mode_contract_errors(role_dir, repo_root, defaults))
    errors.extend(_nolog_contract_errors(role_dir, repo_root, defaults))
    errors.extend(_task_accumulation_errors(role_dir, repo_root))
    errors.extend(_prometheus_alert_topology_label_errors(role_dir, repo_root))
    errors.extend(_prometheus_alert_annotation_errors(role_dir, repo_root))
    return errors


def run(*, repo_root: Path, **_kwargs: object) -> list[str]:
    roles_dir = repo_root / "roles"
    if not roles_dir.is_dir():
        return ["roles directory is missing"]

    env = Environment(autoescape=False)  # noqa: S701
    errors: list[str] = []
    for role_dir in sorted(path for path in roles_dir.iterdir() if path.is_dir()):
        errors.extend(_role_errors(role_dir, repo_root, env))
    return errors
