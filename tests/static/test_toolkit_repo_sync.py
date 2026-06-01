from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from typing import TYPE_CHECKING, Protocol, cast

import pytest


if TYPE_CHECKING:
    from collections.abc import Mapping

    from _pytest.capture import CaptureFixture
    from _pytest.monkeypatch import MonkeyPatch


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = REPO_ROOT / "toolkit" / "check_repo_sync.py"


class SyncModule(Protocol):
    STRUCTURE_PATHS: Mapping[str, tuple[str, ...]]

    def check_structure(self, repo_root: Path) -> bool: ...

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


def test_structure_check_reports_missing_files_and_regex_failures(
    sync_module: SyncModule,
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
    capsys: CaptureFixture[str],
) -> None:
    repo_root = tmp_path / "repo"
    repo_root.mkdir()
    (repo_root / "Taskfile.yml").write_text("---\n\nversion: '3'\n", encoding="utf-8")
    structure_paths = {
        "Taskfile.yml": (r"(?m)^includes:$",),
        "pyproject.toml": (r'(?m)^requires-python = ">=3\.13"$',),
    }
    monkeypatch.setattr(sync_module, "STRUCTURE_PATHS", structure_paths)

    assert sync_module.check_structure(repo_root) is False

    output = capsys.readouterr().out
    assert "Taskfile.yml: missing 1 regex check(s)" in output
    assert "pyproject.toml: missing" in output


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


def test_shared_conventions_report_consumer_repository_failures(
    sync_module: SyncModule,
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
    capsys: CaptureFixture[str],
) -> None:
    repo_root = tmp_path / "repo"
    repo_root.mkdir()
    monkeypatch.setattr(sync_module, "check_ansible_requirements", lambda _repo_root: ["requirements failed"])
    monkeypatch.setattr(sync_module, "check_global_variables", lambda _repo_root: [])
    monkeypatch.setattr(sync_module, "check_inventory", lambda _repo_root: ["inventory failed"])
    monkeypatch.setattr(sync_module, "check_role_variable_overrides", lambda _repo_root: [])
    monkeypatch.setattr(sync_module, "check_yaml_scalar_style", lambda _repo_root: [])

    assert sync_module.check_shared_conventions(repo_root) is False

    output = capsys.readouterr().out
    assert "ansible requirements: 1 error(s)" in output
    assert "  requirements failed" in output
    assert "inventory: 1 error(s)" in output
    assert "  inventory failed" in output


def test_sync_commands_are_not_exposed() -> None:
    script = SCRIPT_PATH.read_text(encoding="utf-8")

    assert "shared-check" not in script
    assert "shared-sync" not in script
    assert "sync_shared" not in script


def test_galaxy_build_includes_toolkit() -> None:
    yaml = pytest.importorskip("yaml")
    galaxy = cast("dict[str, object]", yaml.safe_load((REPO_ROOT / "galaxy.yml").read_text(encoding="utf-8")))
    build_ignore = galaxy.get("build_ignore")

    assert isinstance(build_ignore, list)
    assert "toolkit" not in build_ignore
