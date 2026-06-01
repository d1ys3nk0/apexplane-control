from __future__ import annotations

import contextlib
import importlib.util
import io
import json
from pathlib import Path
from typing import TYPE_CHECKING

import pytest


if TYPE_CHECKING:
    from collections.abc import Callable
    from types import ModuleType


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = REPO_ROOT / "toolkit" / "runtime" / "scripts" / "remote_ansible_state.py"
FILE_MODE_MASK = 0o777
STATE_FILE_MODE = 0o600


def load_remote_state_module() -> ModuleType:
    spec = importlib.util.spec_from_file_location("remote_ansible_state", SCRIPT_PATH)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


remote_state = load_remote_state_module()


def emitted_state(callable_: Callable[..., None], *args: object) -> dict[str, str]:
    stdout = io.StringIO()
    with contextlib.redirect_stdout(stdout):
        callable_(*args)
    output = stdout.getvalue()
    assert output.endswith("\n")
    data = json.loads(output)
    assert isinstance(data, dict)
    assert all(isinstance(key, str) and isinstance(value, str) for key, value in data.items())
    return data


def test_state_paths_accepts_valid_namespace() -> None:
    state_path, lock_path = remote_state.state_paths("ansible-example_1")

    assert state_path == Path("/var/lib/ansible-example_1/state.json")
    assert lock_path == Path("/run/lock/ansible-example_1-state.lock")


def test_state_paths_rejects_invalid_namespace() -> None:
    with pytest.raises(SystemExit, match="Invalid namespace"):
        remote_state.state_paths("example")


def test_read_state_rejects_invalid_json(tmp_path: Path) -> None:
    state_path = tmp_path / "state.json"
    state_path.write_text("{", encoding="utf-8")

    with pytest.raises(SystemExit, match="Invalid remote Ansible state JSON"):
        remote_state.read_state(state_path)


def test_read_state_rejects_invalid_key_type(tmp_path: Path) -> None:
    state_path = tmp_path / "state.json"
    state_path.write_text('{"locked_at": 1}', encoding="utf-8")

    with pytest.raises(SystemExit, match="Invalid remote Ansible state key locked_at"):
        remote_state.read_state(state_path)


def test_acquire_writes_utc_lock_and_release_clears_it(tmp_path: Path) -> None:
    state_path = tmp_path / "state/state.json"
    lock_path = tmp_path / "lock/state.lock"

    acquired = emitted_state(remote_state.acquire, state_path, lock_path, "operator")
    assert acquired["locked_by"] == "operator"
    assert acquired["locked_at"].endswith("Z")
    assert "+00:00" not in acquired["locked_at"]
    assert state_path.stat().st_mode & FILE_MODE_MASK == STATE_FILE_MODE

    with pytest.raises(SystemExit, match="Remote Ansible state is locked"):
        remote_state.acquire(state_path, lock_path, "other")

    released = emitted_state(remote_state.release, state_path, lock_path, "operator")
    assert released["locked_at"] == ""
    assert released["locked_by"] == ""


def test_mark_only_advances_migration_tag(tmp_path: Path) -> None:
    state_path = tmp_path / "state/state.json"
    lock_path = tmp_path / "lock/state.lock"

    first = emitted_state(remote_state.mark, state_path, lock_path, "260601120000")
    assert first["migrate_tag"] == "260601120000"

    older = emitted_state(remote_state.mark, state_path, lock_path, "260101120000")
    assert older["migrate_tag"] == "260601120000"

    newer = emitted_state(remote_state.mark, state_path, lock_path, "260701120000")
    assert newer["migrate_tag"] == "260701120000"


def test_remote_state_uses_python_310_compatible_utc_constant() -> None:
    source = SCRIPT_PATH.read_text(encoding="utf-8")

    assert "from datetime import UTC" not in source
    assert "dt.UTC" not in source
    assert remote_state.REMOTE_STATE_UTC is remote_state.dt.timezone.utc
