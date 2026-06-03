from __future__ import annotations

import importlib.util
import os
import sys
from pathlib import Path
from typing import Protocol, cast


TOOLKIT_ROOT = Path(__file__).resolve().parents[2]


class RepoSyncModule(Protocol):
    def check_role_variable_overrides(self, repo_root: Path) -> list[str]: ...


def target_repo_root() -> Path:
    return Path(os.environ.get("APC_TARGET_REPO_ROOT", Path.cwd())).resolve()


def load_repo_sync_module() -> RepoSyncModule:
    script_path = TOOLKIT_ROOT / "check_repo_sync.py"
    spec = importlib.util.spec_from_file_location("apc_check_repo_sync", script_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"failed to load {script_path}")

    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return cast("RepoSyncModule", module)
