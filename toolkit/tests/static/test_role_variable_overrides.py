from __future__ import annotations

from apc_target_static import load_repo_sync_module, target_repo_root


def test_target_role_variable_overrides_match_apc_role_defaults() -> None:
    repo_sync = load_repo_sync_module()

    assert repo_sync.check_role_variable_overrides(target_repo_root()) == []
