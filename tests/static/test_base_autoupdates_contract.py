from __future__ import annotations

from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[2]
ROLE_DIR = REPO_ROOT / "roles" / "base_autoupdates"


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_base_autoupdates_defaults_expose_public_inputs() -> None:
    defaults = yaml.safe_load(_read(ROLE_DIR / "defaults" / "main.yml"))

    assert defaults["base_autoupdates_enabled"] is True
    assert isinstance(defaults["base_autoupdates_needrestart_mode"], str)
    assert isinstance(defaults["base_autoupdates_package_blacklist"], list)


def test_base_autoupdates_renders_blacklist_and_restart_policy_from_variables() -> None:
    tasks = _read(ROLE_DIR / "tasks" / "setup_configure.yml")

    assert "Unattended-Upgrade::Package-Blacklist" in tasks
    assert "base_autoupdates_package_blacklist" in tasks
    assert '"{{ item }}";' in tasks
    assert "$nrconf{restart} = '{{ base_autoupdates_needrestart_mode }}';" in tasks


def test_base_autoupdates_disabled_mode_enforces_no_unattended_execution() -> None:
    main_tasks = _read(ROLE_DIR / "tasks" / "main.yml")
    disable_tasks = _read(ROLE_DIR / "tasks" / "setup_disable.yml")

    assert "when: not base_autoupdates_enabled | bool" in main_tasks
    assert 'APT::Periodic::Unattended-Upgrade "0";' in disable_tasks
    assert "name: apt-daily-upgrade.timer" in disable_tasks
    assert "enabled: false" in disable_tasks
    assert "state: stopped" in disable_tasks


def test_base_autoupdates_readme_documents_public_variables() -> None:
    readme = _read(ROLE_DIR / "README.md")

    assert "`base_autoupdates_enabled`" in readme
    assert "`base_autoupdates_package_blacklist`" in readme
    assert "`base_autoupdates_needrestart_mode`" in readme
    assert "stops/disables `apt-daily-upgrade.timer`" in readme
