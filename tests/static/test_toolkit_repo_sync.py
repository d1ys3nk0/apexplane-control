from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from typing import TYPE_CHECKING, Protocol, cast

import pytest


if TYPE_CHECKING:
    from collections.abc import Mapping

    from _pytest.monkeypatch import MonkeyPatch


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = REPO_ROOT / "toolkit" / "check_repo_sync.py"


class SyncModule(Protocol):
    STRUCTURE_PATHS: Mapping[str, tuple[str, ...]]

    def check_structure(self, repo_root: Path) -> bool: ...

    def check_global_variables(self, repo_root: Path) -> list[str]: ...

    def check_role_variable_overrides(self, repo_root: Path) -> list[str]: ...

    def check_shared_conventions(self, repo_root: Path) -> bool: ...


def load_sync_module() -> SyncModule:
    spec = importlib.util.spec_from_file_location("check_repo_sync", SCRIPT_PATH)
    assert spec is not None
    assert spec.loader is not None

    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return cast("SyncModule", module)


@pytest.fixture
def sync_module() -> SyncModule:
    return load_sync_module()


def test_structure_check_accepts_optional_installed_toolkit_include(
    sync_module: SyncModule,
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
) -> None:
    repo_root = tmp_path / "repo"
    repo_root.mkdir()
    (repo_root / "Taskfile.yml").write_text(
        """---

version: '3'

includes:
  apc:
    taskfile: .ansible/collections/ansible_collections/apexplane/control/toolkit/Taskfile.yml
    optional: true
""",
        encoding="utf-8",
    )
    structure_paths = {
        "Taskfile.yml": (
            r"(?m)^includes:$",
            r"(?m)^\s+apc:$",
            r"(?m)^\s+taskfile: \.ansible/collections/ansible_collections/apexplane/control/toolkit/Taskfile\.yml$",
            r"(?m)^\s+optional: true$",
        ),
    }
    monkeypatch.setattr(sync_module, "STRUCTURE_PATHS", structure_paths)

    assert sync_module.check_structure(repo_root) is True


def test_structure_check_does_not_require_ycl_platform_taskfile(sync_module: SyncModule) -> None:
    assert ".taskfile/platform-ycl.yml" not in sync_module.STRUCTURE_PATHS


def test_global_variables_require_reference_outside_definition_line(sync_module: SyncModule, tmp_path: Path) -> None:
    repo_root = tmp_path / "repo"
    variables_dir = repo_root / "variables"
    variables_dir.mkdir(parents=True)
    (variables_dir / "_global.yml").write_text("---\ngv_foo: value\n", encoding="utf-8")

    assert sync_module.check_global_variables(repo_root) == [
        "gv_foo: defined at variables/_global.yml:2; referenced at none"
    ]


def test_global_variable_self_reference_on_definition_line_is_not_usage(
    sync_module: SyncModule,
    tmp_path: Path,
) -> None:
    repo_root = tmp_path / "repo"
    variables_dir = repo_root / "variables"
    variables_dir.mkdir(parents=True)
    (variables_dir / "_global.yml").write_text("---\ngv_foo: '{{ gv_foo }}'\n", encoding="utf-8")

    assert sync_module.check_global_variables(repo_root) == [
        "gv_foo: defined at variables/_global.yml:2; referenced at none"
    ]


def test_global_variable_reference_from_another_line_is_usage(sync_module: SyncModule, tmp_path: Path) -> None:
    repo_root = tmp_path / "repo"
    variables_dir = repo_root / "variables"
    variables_dir.mkdir(parents=True)
    (variables_dir / "_global.yml").write_text("---\ngv_foo: value\n", encoding="utf-8")
    (variables_dir / "_shared.yml").write_text("---\niv_example: '{{ gv_foo }}'\n", encoding="utf-8")

    assert sync_module.check_global_variables(repo_root) == []


def test_global_variable_definitions_outside_global_file_fail(sync_module: SyncModule, tmp_path: Path) -> None:
    repo_root = tmp_path / "repo"
    variables_dir = repo_root / "variables"
    variables_dir.mkdir(parents=True)
    (variables_dir / "app.yml").write_text("---\ngv_foo: value\niv_example: '{{ gv_foo }}'\n", encoding="utf-8")

    assert sync_module.check_global_variables(repo_root) == [
        "variables/app.yml:2: gv_foo must be defined in _global.yml"
    ]


def test_role_variable_overrides_must_match_role_defaults(sync_module: SyncModule, tmp_path: Path) -> None:
    repo_root = tmp_path / "repo"
    variables_dir = repo_root / "variables"
    role_defaults_dir = repo_root / "roles" / "docker_example" / "defaults"
    variables_dir.mkdir(parents=True)
    role_defaults_dir.mkdir(parents=True)
    (role_defaults_dir / "main.yml").write_text("---\n\ndocker_example_enabled: true\n", encoding="utf-8")
    (variables_dir / "app.yml").write_text(
        "---\n\n# Role: docker_example\ndocker_example_unknown: true\n",
        encoding="utf-8",
    )

    assert sync_module.check_role_variable_overrides(repo_root) == [
        "variables/app.yml:4: docker_example_unknown is not declared in roles/docker_example/defaults/main.yml"
    ]


def test_role_variable_overrides_accept_declared_defaults(sync_module: SyncModule, tmp_path: Path) -> None:
    repo_root = tmp_path / "repo"
    variables_dir = repo_root / "variables"
    role_defaults_dir = repo_root / "roles" / "docker_example" / "defaults"
    variables_dir.mkdir(parents=True)
    role_defaults_dir.mkdir(parents=True)
    (role_defaults_dir / "main.yml").write_text("---\n\ndocker_example_enabled: true\n", encoding="utf-8")
    (variables_dir / "app.yml").write_text(
        "---\n\n# Role: docker_example\ndocker_example_enabled: true\n", encoding="utf-8"
    )

    assert sync_module.check_role_variable_overrides(repo_root) == []
