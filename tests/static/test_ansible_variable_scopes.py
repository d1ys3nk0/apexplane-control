from __future__ import annotations

import os
from pathlib import Path

from ansible_variable_scopes import run


REPO_ROOT = Path(os.environ.get("ANSIBLE_LINT_REPO_ROOT", Path(__file__).resolve().parents[2])).resolve()


def test_repository_variable_scopes_pass() -> None:
    assert run(repo_root=REPO_ROOT) == []


def test_global_variable_requires_reference_outside_definition_line(tmp_path: Path) -> None:
    variables_dir = tmp_path / "variables"
    variables_dir.mkdir()
    (variables_dir / "_global.yml").write_text("---\ngv_foo: value\n", encoding="utf-8")

    assert run(repo_root=tmp_path) == ["variables/_global.yml:2: gv_foo is declared but not used"]


def test_global_variable_self_reference_on_definition_line_is_not_usage(tmp_path: Path) -> None:
    variables_dir = tmp_path / "variables"
    variables_dir.mkdir()
    (variables_dir / "_global.yml").write_text("---\ngv_foo: '{{ gv_foo }}'\n", encoding="utf-8")

    assert run(repo_root=tmp_path) == ["variables/_global.yml:2: gv_foo is declared but not used"]


def test_global_variable_reference_from_another_line_is_usage(tmp_path: Path) -> None:
    variables_dir = tmp_path / "variables"
    variables_dir.mkdir()
    (variables_dir / "_global.yml").write_text("---\ngv_foo: value\n", encoding="utf-8")
    (variables_dir / "_shared.yml").write_text("---\niv_example: '{{ gv_foo }}'\n", encoding="utf-8")

    assert run(repo_root=tmp_path) == []


def test_global_variable_definitions_outside_global_file_fail(tmp_path: Path) -> None:
    variables_dir = tmp_path / "variables"
    variables_dir.mkdir()
    (variables_dir / "app.yml").write_text("---\ngv_foo: value\niv_example: '{{ gv_foo }}'\n", encoding="utf-8")

    assert run(repo_root=tmp_path) == ["variables/app.yml:2: gv_foo must be defined only in _global.yml files"]


def test_role_variable_assignment_cannot_reference_another_role_variable(tmp_path: Path) -> None:
    variables_dir = tmp_path / "variables"
    variables_dir.mkdir()
    roles_dir = tmp_path / "roles"
    (roles_dir / "crowdsec" / "defaults").mkdir(parents=True)
    (roles_dir / "haproxy_alb" / "defaults").mkdir(parents=True)
    (roles_dir / "crowdsec" / "defaults" / "main.yml").write_text("---\ncrowdsec_enabled: true\n", encoding="utf-8")
    (roles_dir / "haproxy_alb" / "defaults" / "main.yml").write_text(
        "---\nhaproxy_alb_crowdsec_enabled: false\n", encoding="utf-8"
    )
    (variables_dir / "bal.yml").write_text(
        "---\n"
        "# Role: crowdsec\n"
        "crowdsec_enabled: true\n"
        "# Role: haproxy_alb\n"
        "haproxy_alb_crowdsec_enabled: '{{ crowdsec_enabled }}'\n",
        encoding="utf-8",
    )

    assert run(repo_root=tmp_path) == [
        "variables/bal.yml:5: haproxy_alb_crowdsec_enabled must not reference crowdsec_enabled; "
        "use absolute values, _, gv_, iv_, vv_, ansible_, runtime, or haproxy_alb_ variables"
    ]


def test_role_variable_assignment_can_reference_global_variable(tmp_path: Path) -> None:
    variables_dir = tmp_path / "variables"
    variables_dir.mkdir()
    roles_dir = tmp_path / "roles"
    (roles_dir / "crowdsec" / "defaults").mkdir(parents=True)
    (roles_dir / "haproxy_alb" / "defaults").mkdir(parents=True)
    (roles_dir / "crowdsec" / "defaults" / "main.yml").write_text("---\ncrowdsec_enabled: true\n", encoding="utf-8")
    (roles_dir / "haproxy_alb" / "defaults" / "main.yml").write_text(
        "---\nhaproxy_alb_crowdsec_enabled: false\n", encoding="utf-8"
    )
    (variables_dir / "_global.yml").write_text("---\ngv_crowdsec_enabled: true\n", encoding="utf-8")
    (variables_dir / "bal.yml").write_text(
        "---\n"
        "# Role: crowdsec\n"
        "crowdsec_enabled: '{{ gv_crowdsec_enabled }}'\n"
        "# Role: haproxy_alb\n"
        "haproxy_alb_crowdsec_enabled: '{{ gv_crowdsec_enabled }}'\n",
        encoding="utf-8",
    )

    assert run(repo_root=tmp_path) == []
