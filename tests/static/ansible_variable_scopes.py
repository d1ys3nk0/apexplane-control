from __future__ import annotations

import os
import re
from collections.abc import Iterable, Iterator, Mapping
from pathlib import Path
from typing import cast

import yaml


CONVENTION_YAML_DIRS = ("inventories", "playbooks", "roles", "variables")
REFERENCE_DIRS = ("bin", "inventories", "playbooks", "roles", "scripts", "templates", "tests", "variables")
HOST_GROUP_RE = re.compile(r"^(?P<realm>[a-z][a-z0-9]*)_(?P<platform>[a-z][a-z0-9]*)_(?P<cluster>[a-z][a-z0-9]*)$")
HOST_NAME_RE = re.compile(
    r"^(?P<realm>[a-z][a-z0-9]*)-(?P<platform>[a-z][a-z0-9]*)-(?P<cluster>[a-z][a-z0-9]*)[0-9]{2}$"
)
TOP_LEVEL_VAR_RE = re.compile(r"^(?P<name>[A-Za-z_][A-Za-z0-9_]*):")
TOP_LEVEL_ASSIGNMENT_RE = re.compile(r"^(?P<name>[A-Za-z_][A-Za-z0-9_]*):(?P<value>.*)$")
BLOCK_LIST_MAPPING_RE = re.compile(r"^(?P<indent>\s*)-\s+(?!{)[A-Za-z_][A-Za-z0-9_-]*:(?:\s|$)")
ROLE_COMMENT_RE = re.compile(r"^# Role: (?P<name>[a-z][a-z0-9_]*[a-z0-9])$")
ANSIBLE_COMMENT = "# Ansible"
JINJA_BLOCK_RE = re.compile(r"{{(?P<expression>.*?)}}", re.DOTALL)
QUOTED_STRING_RE = re.compile(r"""'(?:\\.|[^'])*'|"(?:\\.|[^"])*" """.strip())
VAR_NAME_RE = re.compile(r"(?<![.\w])(?P<name>[A-Za-z_][A-Za-z0-9_]*)\b")
ALLOWED_VARIABLE_PREFIXES = ("_", "gv_", "iv_", "vv_", "ansible_")
ALLOWED_RUNTIME_VARIABLES = {
    "cluster_name",
    "cluster_realm",
    "target_hosts",
}
ALLOWED_REFERENCE_NAMES = {
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
    "as",
    "attribute",
    "basename",
    "bool",
    "combine",
    "default",
    "defined",
    "dict",
    "dict2items",
    "difference",
    "else",
    "elif",
    "end",
    "endif",
    "equalto",
    "false",
    "first",
    "float",
    "for",
    "from_json",
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
    "sort",
    "string",
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
YAML_SUFFIXES = {".yml", ".yaml"}
LEGACY_VAULT_SUFFIXES = (".vault.yml", ".vault.yaml")
MIN_HELPER_REFERENCES = 2
STANDARD_PORT_GLOBALS = {
    "gv_alertmanager_http_port": "9093",
    "gv_bypass_http_port": "80",
    "gv_crowdsec_spoa_port": "9000",
    "gv_grafana_http_port": "3000",
    "gv_haproxy_prometheus_exporter_port": "8405",
    "gv_haproxy_stats_port": "8404",
    "gv_jaeger_http_port": "16686",
    "gv_loki_grpc_port": "3099",
    "gv_loki_http_port": "3100",
    "gv_mattermost_expose_http_port": "8065",
    "gv_postgres_exporter_port": "9187",
    "gv_prometheus_http_port": "9090",
    "gv_sentry_http_port": "9000",
    "gv_smtp_port": "465",
    "gv_traefik_http_expose_port": "80",
    "gv_traefik_http_port": "80",
    "gv_traefik_https_expose_port": "443",
    "gv_zitadel_http_port": "8080",
    "gv_zitadel_http_public_port": "8080",
}


def _rel_path(path: Path, repo_root: Path) -> str:
    return str(path.relative_to(repo_root))


def _strip_inline_comment(raw: str) -> str:
    quote: str | None = None
    for index, char in enumerate(raw):
        if char in {"'", '"'}:
            quote = None if quote == char else char
        if char == "#" and quote is None:
            return raw[:index].strip()
    return raw.strip()


def _strip_inline_comment_preserving_indent(raw: str) -> str:
    quote: str | None = None
    for index, char in enumerate(raw):
        if char in {"'", '"'}:
            quote = None if quote == char else char
        if char == "#" and quote is None:
            return raw[:index].rstrip()
    return raw.rstrip()


def _load_yaml(path: Path) -> object | None:
    try:
        return yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError:
        return None


def _iter_convention_yaml_files(repo_root: Path) -> list[Path]:
    files: list[Path] = []
    for dirname in CONVENTION_YAML_DIRS:
        directory = repo_root / dirname
        if not directory.is_dir():
            continue
        files.extend(path for path in sorted(directory.rglob("*")) if path.is_file() and path.suffix in YAML_SUFFIXES)
    return files


def _iter_variable_definitions(variables_dir: Path) -> list[tuple[Path, int, str]]:
    definitions: list[tuple[Path, int, str]] = []
    for path in sorted(variables_dir.rglob("*.yml")):
        if not path.is_file():
            continue
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            match = TOP_LEVEL_VAR_RE.match(line)
            if match is None:
                continue
            definitions.append((path, line_number, match.group("name")))
    return definitions


def _iter_variable_assignments(variables_dir: Path) -> list[tuple[Path, int, str, str]]:
    assignments: list[tuple[Path, int, str, str]] = []
    for path in sorted(variables_dir.rglob("*.yml")):
        if not path.is_file():
            continue
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            match = TOP_LEVEL_ASSIGNMENT_RE.match(line)
            if match is None:
                continue
            assignments.append((path, line_number, match.group("name"), match.group("value")))
    return assignments


def _shared_roles_dir(repo_root: Path) -> Path:
    return Path(os.environ.get("APEXPLANE_CONTROL_PATH", repo_root.parent / "apexplane-control")) / "roles"


def _role_names(repo_root: Path) -> set[str]:
    names: set[str] = set()
    for roles_dir in (repo_root / "roles", _shared_roles_dir(repo_root)):
        if not roles_dir.is_dir():
            continue
        names.update(path.name for path in roles_dir.iterdir() if path.is_dir())
    return names


def _role_defaults(repo_root: Path, role_name: str) -> Mapping[object, object]:
    for roles_dir in (repo_root / "roles", _shared_roles_dir(repo_root)):
        defaults_path = roles_dir / role_name / "defaults" / "main.yml"
        if defaults_path.is_file():
            defaults = _load_yaml(defaults_path)
            return cast("Mapping[object, object]", defaults) if isinstance(defaults, Mapping) else {}
    return {}


def _role_name_length(role_name: str) -> int:
    return len(role_name)


def _role_name_for_variable(name: str, role_names: set[str]) -> str | None:
    return next(
        (
            role_name
            for role_name in sorted(role_names, key=_role_name_length, reverse=True)
            if name.startswith(f"{role_name}_")
        ),
        None,
    )


def _is_allowed_variable_name(name: str, role_names: set[str]) -> bool:
    return (
        name.startswith(ALLOWED_VARIABLE_PREFIXES)
        or name in ALLOWED_RUNTIME_VARIABLES
        or _role_name_for_variable(name, role_names) is not None
    )


def _is_allowed_role_reference(name: str, target_role: str, role_names: set[str]) -> bool:
    if (
        name.startswith(ALLOWED_VARIABLE_PREFIXES)
        or name in ALLOWED_RUNTIME_VARIABLES
        or name in ALLOWED_REFERENCE_NAMES
        or name in IGNORED_JINJA_NAMES
    ):
        return True
    reference_role = _role_name_for_variable(name, role_names)
    return reference_role == target_role


def _jinja_variable_references(value: str) -> set[str]:
    references: set[str] = set()
    for match in JINJA_BLOCK_RE.finditer(value):
        expression = QUOTED_STRING_RE.sub("", match.group("expression"))
        references.update(
            name_match.group("name")
            for name_match in VAR_NAME_RE.finditer(expression)
            if name_match.group("name") not in IGNORED_JINJA_NAMES
        )
    return references


def _role_variable_reference_errors(repo_root: Path) -> list[str]:
    variables_dir = repo_root / "variables"
    role_names = _role_names(repo_root)
    errors: list[str] = []
    for path, line_number, target_name, raw_value in _iter_variable_assignments(variables_dir):
        target_role = _role_name_for_variable(target_name, role_names)
        if target_role is None:
            continue
        for reference_name in sorted(_jinja_variable_references(raw_value)):
            if _is_allowed_role_reference(reference_name, target_role, role_names):
                continue
            reference_role = _role_name_for_variable(reference_name, role_names)
            allowed_hint = f"_, gv_, iv_, vv_, ansible_, runtime, or {target_role}_ variables"
            if reference_role is None:
                errors.append(
                    f"{_rel_path(path, repo_root)}:{line_number}: {target_name} must not reference "
                    f"{reference_name}; use {allowed_hint}"
                )
                continue
            errors.append(
                f"{_rel_path(path, repo_root)}:{line_number}: {target_name} must not reference "
                f"{reference_name}; use {allowed_hint}"
            )
    return errors


def _role_variable_grouping_errors(repo_root: Path) -> list[str]:
    variables_dir = repo_root / "variables"
    role_names = _role_names(repo_root)
    errors: list[str] = []
    for path in sorted(variables_dir.rglob("*.yml")):
        if not path.is_file():
            continue

        current_role: str | None = None
        role_section_lines: dict[str, int] = {}
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            role_comment_match = ROLE_COMMENT_RE.fullmatch(line)
            if role_comment_match is not None:
                current_role = role_comment_match.group("name")
                first_line_number = role_section_lines.setdefault(current_role, line_number)
                if first_line_number != line_number:
                    errors.append(
                        f"{_rel_path(path, repo_root)}:{line_number}: role {current_role} variables are scattered; "
                        f"merge with # Role: {current_role} at line {first_line_number}"
                    )
                continue

            variable_match = TOP_LEVEL_VAR_RE.match(line)
            if variable_match is None:
                continue
            variable_name = variable_match.group("name")
            variable_role = _role_name_for_variable(variable_name, role_names)
            if variable_role is None or variable_role == current_role:
                continue
            expected_comment = f"# Role: {variable_role}"
            errors.append(
                f"{_rel_path(path, repo_root)}:{line_number}: {variable_name} must be grouped under {expected_comment}"
            )
    return errors


def _iter_reference_files(repo_root: Path) -> Iterator[Path]:
    for dirname in REFERENCE_DIRS:
        directory = repo_root / dirname
        if directory.is_file():
            yield directory
            continue
        if not directory.is_dir():
            continue
        for path in sorted(directory.rglob("*")):
            if path.is_file() and "__pycache__" not in path.parts:
                yield path


def _line_has_variable_reference(line: str, name: str) -> bool:
    if line.lstrip().startswith("#"):
        return False
    searchable_line = _strip_inline_comment(line)
    return re.search(rf"\b{re.escape(name)}\b", searchable_line) is not None


def _is_variable_used(
    *,
    name: str,
    definition_path: Path,
    definition_line_number: int,
    reference_files: Iterable[Path],
) -> bool:
    for path in reference_files:
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except UnicodeDecodeError:
            continue
        for line_number, line in enumerate(lines, start=1):
            reference_line = line
            if path == definition_path and line_number == definition_line_number:
                reference_line = line.split(":", maxsplit=1)[1]
            if _line_has_variable_reference(reference_line, name):
                return True
    return False


def _unused_global_variable_errors(repo_root: Path) -> list[str]:
    variables_dir = repo_root / "variables"
    if not variables_dir.is_dir():
        return []

    reference_files = list(_iter_reference_files(repo_root))
    errors: list[str] = []
    for path, line_number, name in _iter_variable_definitions(variables_dir):
        if not name.startswith("gv_"):
            continue
        if not _is_variable_used(
            name=name,
            definition_path=path,
            definition_line_number=line_number,
            reference_files=reference_files,
        ):
            errors.append(f"{_rel_path(path, repo_root)}:{line_number}: {name} is declared but not used")
    return errors


def _standard_port_global_errors(repo_root: Path) -> list[str]:
    variables_dir = repo_root / "variables"
    if not variables_dir.is_dir():
        return []

    standard_names: set[str] = set()
    defined_names: set[str] = set()
    assignments = _iter_variable_assignments(variables_dir)
    for _path, _line_number, name, raw_value in assignments:
        if name not in STANDARD_PORT_GLOBALS:
            continue
        defined_names.add(name)
        normalized_value = _strip_inline_comment(raw_value).strip().strip("'\"")
        if normalized_value == STANDARD_PORT_GLOBALS[name]:
            standard_names.add(name)

    errors: list[str] = []
    for path, line_number, name, _raw_value in assignments:
        if name in standard_names:
            errors.append(
                f"{_rel_path(path, repo_root)}:{line_number}: {name} wraps standard port "
                f"{STANDARD_PORT_GLOBALS[name]}; inline the port with a comment"
            )

    for path in sorted(variables_dir.rglob("*.yml")):
        if not path.is_file():
            continue
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            if line.lstrip().startswith("#"):
                continue
            searchable_line = _strip_inline_comment(line)
            for reference_name in sorted(_jinja_variable_references(searchable_line)):
                if reference_name not in STANDARD_PORT_GLOBALS:
                    continue
                if reference_name not in standard_names and reference_name in defined_names:
                    continue
                errors.append(
                    f"{_rel_path(path, repo_root)}:{line_number}: {reference_name} wraps standard port "
                    f"{STANDARD_PORT_GLOBALS[reference_name]}; inline the port with a comment"
                )
    return errors


def _docker_image_tag_override_errors(repo_root: Path) -> list[str]:
    variables_dir = repo_root / "variables"
    role_names = _role_names(repo_root)
    errors: list[str] = []
    defaults_by_role: dict[str, Mapping[object, object]] = {}

    for path, line_number, name in _iter_variable_definitions(variables_dir):
        if not name.endswith(("_image", "_image_full")):
            continue

        role_name = _role_name_for_variable(name, role_names)
        if role_name is None:
            continue

        defaults = defaults_by_role.setdefault(role_name, _role_defaults(repo_root, role_name))
        image_base = name.removesuffix("_full")
        tag_name = f"{image_base}_tag"
        image_name_name = f"{image_base}_name"
        if image_name_name in defaults and tag_name in defaults:
            errors.append(
                f"{_rel_path(path, repo_root)}:{line_number}: use {image_name_name} and {tag_name} instead of {name}"
            )
            continue

        if name not in defaults or tag_name not in defaults:
            continue

        errors.append(f"{_rel_path(path, repo_root)}:{line_number}: use {tag_name} instead of {name}")

    return errors


def _docker_image_name_pair_errors(repo_root: Path) -> list[str]:
    variables_dir = repo_root / "variables"
    role_names = _role_names(repo_root)
    errors: list[str] = []
    defaults_by_role: dict[str, Mapping[object, object]] = {}
    definitions_by_path: dict[Path, set[str]] = {}

    for path, _line_number, name in _iter_variable_definitions(variables_dir):
        definitions_by_path.setdefault(path, set()).add(name)

    for path, line_number, name in _iter_variable_definitions(variables_dir):
        if not name.endswith("_image_name"):
            continue

        role_name = _role_name_for_variable(name, role_names)
        if role_name is None:
            continue

        defaults = defaults_by_role.setdefault(role_name, _role_defaults(repo_root, role_name))
        tag_name = f"{name.removesuffix('_name')}_tag"
        if name not in defaults or tag_name not in defaults:
            continue
        if tag_name in definitions_by_path.get(path, set()):
            continue

        errors.append(f"{_rel_path(path, repo_root)}:{line_number}: {name} requires {tag_name} in the same file")

    return errors


def _redundant_docker_memory_override_errors(repo_root: Path) -> list[str]:
    variables_dir = repo_root / "variables"
    role_names = _role_names(repo_root)
    errors: list[str] = []
    defaults_by_role: dict[str, Mapping[object, object]] = {}

    for path, line_number, name, raw_value in _iter_variable_assignments(variables_dir):
        if not name.endswith(("_mem_res", "_mem_lim", "_mem_swp")):
            continue

        role_name = _role_name_for_variable(name, role_names)
        if role_name is None:
            continue

        defaults = defaults_by_role.setdefault(role_name, _role_defaults(repo_root, role_name))
        normalized_value = _strip_inline_comment(raw_value).strip().strip("'\"")
        if defaults.get(name) == normalized_value:
            errors.append(f"{_rel_path(path, repo_root)}:{line_number}: {name} matches role default; remove override")

    return errors


def _role_debug_override_errors(repo_root: Path) -> list[str]:
    variables_dir = repo_root / "variables"
    role_names = _role_names(repo_root)
    errors: list[str] = []
    for path, line_number, name in _iter_variable_definitions(variables_dir):
        if not name.endswith("_debug"):
            continue
        role_name = _role_name_for_variable(name, role_names)
        if role_name is None:
            continue
        errors.append(
            f"{_rel_path(path, repo_root)}:{line_number}: use {role_name}_nolog in role defaults instead of "
            f"project variable {name}"
        )
    return errors


def _helper_variable_scope_errors(repo_root: Path) -> list[str]:
    variables_dir = repo_root / "variables"
    if not variables_dir.is_dir():
        return []

    definitions: dict[str, list[tuple[Path, int]]] = {}
    references: dict[str, list[tuple[Path, int]]] = {}
    for path, line_number, name in _iter_variable_definitions(variables_dir):
        if name.startswith("_"):
            definitions.setdefault(name, []).append((path, line_number))

    for path, line_number, _target_name, raw_value in _iter_variable_assignments(variables_dir):
        for reference_name in _jinja_variable_references(raw_value):
            if reference_name.startswith("_"):
                references.setdefault(reference_name, []).append((path, line_number))

    errors: list[str] = []
    duplicate_definition_names: set[str] = set()
    for name, reference_locations in sorted(references.items()):
        definition_locations = definitions.get(name, [])
        if not definition_locations:
            first_path, first_line_number = reference_locations[0]
            errors.append(
                f"{_rel_path(first_path, repo_root)}:{first_line_number}: {name} is referenced but not defined"
            )
            continue

        definition_files = {path for path, _line_number in definition_locations}
        if len(definition_files) != 1:
            first_path, first_line_number = definition_locations[0]
            duplicate_definition_names.add(name)
            errors.append(
                f"{_rel_path(first_path, repo_root)}:{first_line_number}: {name} must be defined in only one variables file"
            )
            continue

        definition_path = next(iter(definition_files))
        cross_file_references = [
            (reference_path, reference_line_number)
            for reference_path, reference_line_number in reference_locations
            if reference_path != definition_path
        ]
        for reference_path, reference_line_number in cross_file_references:
            errors.append(
                f"{_rel_path(reference_path, repo_root)}:{reference_line_number}: {name} must not be referenced "
                f"outside {_rel_path(definition_path, repo_root)}; use gv_ or a direct role variable"
            )

    for name, definition_locations in sorted(definitions.items()):
        definition_files = {path for path, _line_number in definition_locations}
        first_path, first_line_number = definition_locations[0]
        if len(definition_files) != 1:
            if name not in duplicate_definition_names:
                errors.append(
                    f"{_rel_path(first_path, repo_root)}:{first_line_number}: {name} must be defined in only one variables file"
                )
            continue

        reference_locations = references.get(name, [])
        definition_path = next(iter(definition_files))
        same_file_references = [
            (reference_path, reference_line_number)
            for reference_path, reference_line_number in reference_locations
            if reference_path == definition_path
        ]
        if len(same_file_references) < MIN_HELPER_REFERENCES:
            errors.append(
                f"{_rel_path(first_path, repo_root)}:{first_line_number}: {name} is used {len(same_file_references)} "
                "time(s); assign the value directly unless a helper is used multiple times in this file"
            )
    return errors


def _null_literal_errors(repo_root: Path) -> list[str]:
    errors: list[str] = []
    for path in _iter_convention_yaml_files(repo_root):
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            raw_value = _strip_inline_comment(line).strip()
            if re.search(r"(^|[:\[, -])null($|[\]}, ])", raw_value) is not None:
                errors.append(f"{_rel_path(path, repo_root)}:{line_number}: use ~ instead of null")
    return errors


def _inline_mapping_errors(repo_root: Path) -> list[str]:
    errors: list[str] = []
    for path in _iter_convention_yaml_files(repo_root):
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            raw_value = _strip_inline_comment(line).strip()
            if re.search(r"(^|:\s|-\s){[^{}\n]*:[^{}\n]*}", raw_value) is not None:
                errors.append(
                    f"{_rel_path(path, repo_root)}:{line_number}: use block mapping syntax instead of inline {{...}}"
                )
    return errors


def _list_mapping_spacing_errors(repo_root: Path) -> list[str]:
    errors: list[str] = []
    for path in _iter_convention_yaml_files(repo_root):
        previous_mapping_item_line_by_indent: dict[str, int] = {}
        lines = path.read_text(encoding="utf-8").splitlines()
        for line_number, line in enumerate(lines, start=1):
            raw_value = _strip_inline_comment_preserving_indent(line)
            match = BLOCK_LIST_MAPPING_RE.match(raw_value)
            if match is None:
                if raw_value.strip():
                    line_indent = len(raw_value) - len(raw_value.lstrip())
                    if raw_value.lstrip().startswith("-"):
                        continue
                    for indent in list(previous_mapping_item_line_by_indent):
                        if len(indent) > line_indent:
                            del previous_mapping_item_line_by_indent[indent]
                continue

            indent = match.group("indent")
            previous_item_line = previous_mapping_item_line_by_indent.get(indent)
            previous_line = lines[line_number - 2] if line_number > 1 else ""
            if previous_item_line is not None and previous_line.strip():
                errors.append(
                    f"{_rel_path(path, repo_root)}:{line_number}: separate block mapping list items with an empty line"
                )
            previous_mapping_item_line_by_indent[indent] = line_number
    return errors


def _mapping_child(data: Mapping[object, object], key: str) -> Mapping[object, object]:
    value = data.get(key)
    return cast("Mapping[object, object]", value) if isinstance(value, Mapping) else {}


def _inventory_naming_errors(repo_root: Path) -> list[str]:
    inventories_dir = repo_root / "inventories"
    if not inventories_dir.is_dir():
        return []

    errors: list[str] = []
    for path in sorted(inventories_dir.glob("*/*.yml")):
        cluster = path.parent.name
        realm = path.stem
        data = _load_yaml(path)
        if not isinstance(data, Mapping):
            continue

        inventory_data = cast("Mapping[object, object]", data)
        all_group = _mapping_child(inventory_data, "all")
        realm_groups = _mapping_child(_mapping_child(all_group, "children"), realm)
        platform_groups = _mapping_child(realm_groups, "children")
        for platform_group_name, platform_group_data in sorted(platform_groups.items()):
            if not isinstance(platform_group_name, str) or not isinstance(platform_group_data, Mapping):
                continue
            platform_prefix = f"{realm}_"
            if not platform_group_name.startswith(platform_prefix):
                errors.append(
                    f"{_rel_path(path, repo_root)}:1: inventory platform group {platform_group_name} must start with {platform_prefix}"
                )
                continue
            platform = platform_group_name.removeprefix(platform_prefix)
            host_groups = _mapping_child(cast("Mapping[object, object]", platform_group_data), "children")
            for host_group_name, host_group_data in sorted(host_groups.items()):
                if not isinstance(host_group_name, str) or not isinstance(host_group_data, Mapping):
                    continue
                expected_group = f"{realm}_{platform}_{cluster}"
                if host_group_name != expected_group or HOST_GROUP_RE.fullmatch(host_group_name) is None:
                    errors.append(
                        f"{_rel_path(path, repo_root)}:1: inventory host group {host_group_name} must be {expected_group}"
                    )
                    continue
                hosts = _mapping_child(cast("Mapping[object, object]", host_group_data), "hosts")
                for host_name in sorted(name for name in hosts if isinstance(name, str)):
                    expected_prefix = f"{realm}-{platform}-{cluster}"
                    if not host_name.startswith(expected_prefix) or HOST_NAME_RE.fullmatch(host_name) is None:
                        errors.append(
                            f"{_rel_path(path, repo_root)}:1: inventory host {host_name} must match {expected_prefix}NN"
                        )
    return errors


def _legacy_vault_filename_errors(repo_root: Path) -> list[str]:
    variables_dir = repo_root / "variables"
    errors: list[str] = []
    for path in sorted(variables_dir.rglob("*")):
        if not path.is_file() or path.suffix not in YAML_SUFFIXES:
            continue
        if path.name.endswith(LEGACY_VAULT_SUFFIXES):
            errors.append(f"{_rel_path(path, repo_root)}: legacy vault filename must be _vault.yml")
    return errors


def _variable_prefix_errors(repo_root: Path) -> list[str]:
    variables_dir = repo_root / "variables"
    role_names = _role_names(repo_root)
    errors: list[str] = []
    for path, line_number, name in _iter_variable_definitions(variables_dir):
        if _is_allowed_variable_name(name, role_names):
            continue
        errors.append(
            f"{_rel_path(path, repo_root)}:{line_number}: {name} must start with _, gv_, iv_, vv_, "
            "ansible_, or an existing role prefix"
        )
    return errors


def _variable_file_layout_errors(repo_root: Path) -> list[str]:
    variables_dir = repo_root / "variables"
    if not variables_dir.is_dir():
        return []

    errors: list[str] = []
    for path in sorted(variables_dir.rglob("*.yml")):
        if not path.is_file() or path.name in {"_global.yml", "_vault.yml"}:
            continue

        section = "helpers"
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            stripped = line.strip()
            if not stripped or stripped == "---":
                continue

            if line.startswith("#"):
                if line == ANSIBLE_COMMENT:
                    if section != "helpers":
                        errors.append(
                            f"{_rel_path(path, repo_root)}:{line_number}: # Ansible must appear before role sections"
                        )
                    section = "ansible"
                    continue

                role_comment_match = ROLE_COMMENT_RE.fullmatch(line)
                if role_comment_match is not None:
                    section = "role"
                    continue

                errors.append(
                    f"{_rel_path(path, repo_root)}:{line_number}: variables file section comments must be "
                    "# Ansible or # Role: <role_name>"
                )
                continue

            variable_match = TOP_LEVEL_VAR_RE.match(line)
            if variable_match is None:
                continue

            variable_name = variable_match.group("name")
            if variable_name.startswith("_"):
                if section != "helpers":
                    errors.append(
                        f"{_rel_path(path, repo_root)}:{line_number}: {variable_name} helper variables must be "
                        "declared before # Ansible and # Role sections"
                    )
                continue

            if variable_name.startswith("ansible_") and section != "ansible":
                errors.append(
                    f"{_rel_path(path, repo_root)}:{line_number}: {variable_name} must be grouped under # Ansible"
                )

    return errors


def run(*, repo_root: Path, **_kwargs: object) -> list[str]:
    variables_dir = repo_root / "variables"
    errors: list[str] = []
    errors.extend(_null_literal_errors(repo_root))
    errors.extend(_inline_mapping_errors(repo_root))
    errors.extend(_list_mapping_spacing_errors(repo_root))

    if not variables_dir.is_dir():
        return errors

    errors.extend(_legacy_vault_filename_errors(repo_root))
    for path, line_number, name in _iter_variable_definitions(variables_dir):
        rel_path = path.relative_to(repo_root)
        if path.name == "_global.yml" and not name.startswith("gv_"):
            errors.append(
                f"{rel_path}:{line_number}: {name} must not be defined in _global.yml; use only gv_ variables"
            )
        if name.startswith("gv_") and path.name != "_global.yml":
            errors.append(f"{rel_path}:{line_number}: {name} must be defined only in _global.yml files")
        if name.startswith("vv_") and path.name != "_vault.yml":
            errors.append(f"{rel_path}:{line_number}: {name} must be defined only in _vault.yml files")
    errors.extend(_variable_prefix_errors(repo_root))
    errors.extend(_variable_file_layout_errors(repo_root))
    errors.extend(_inventory_naming_errors(repo_root))
    errors.extend(_helper_variable_scope_errors(repo_root))
    errors.extend(_role_variable_reference_errors(repo_root))
    errors.extend(_role_variable_grouping_errors(repo_root))
    errors.extend(_standard_port_global_errors(repo_root))
    errors.extend(_docker_image_tag_override_errors(repo_root))
    errors.extend(_docker_image_name_pair_errors(repo_root))
    errors.extend(_redundant_docker_memory_override_errors(repo_root))
    errors.extend(_role_debug_override_errors(repo_root))
    errors.extend(_unused_global_variable_errors(repo_root))
    return errors
