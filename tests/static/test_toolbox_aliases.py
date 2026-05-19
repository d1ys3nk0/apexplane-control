from __future__ import annotations

import os
from pathlib import Path

from jinja2 import Environment, FileSystemLoader, StrictUndefined


REPO_ROOT = Path(os.environ.get("ANSIBLE_LINT_REPO_ROOT", Path(__file__).resolve().parents[2])).resolve()
TEMPLATE_DIR = REPO_ROOT / "roles" / "toolbox" / "templates"


def render_toolbox(*, docker_enabled: bool = False, haproxy_enabled: bool = False) -> str:
    env = Environment(loader=FileSystemLoader(TEMPLATE_DIR), undefined=StrictUndefined, autoescape=True)
    env.filters["bool"] = bool
    template = env.get_template("bash_toolbox.sh.j2")

    return template.render(
        toolbox_docker_enabled=docker_enabled,
        toolbox_haproxy_enabled=haproxy_enabled,
    )


def test_toolbox_omits_optional_families_by_default() -> None:
    toolbox = render_toolbox()

    assert 'export PATH="/opt/toolbox/bin:$PATH"' in toolbox
    assert "/etc/skel/.bash_toolbox" in toolbox
    assert "alias s='sudo'" in toolbox
    assert "alias bp='bp'" in toolbox
    assert "# >->-> Git <-<-<" in toolbox
    assert "# >->-> Docker <-<-<" not in toolbox
    assert "# >->-> HAProxy <-<-<" not in toolbox
    assert "docker-cleanup()" not in toolbox
    assert "alias hpc=" not in toolbox


def test_toolbox_includes_enabled_docker_family() -> None:
    toolbox = render_toolbox(docker_enabled=True)

    assert "# >->-> Docker <-<-<" in toolbox
    assert "docker-cleanup()" in toolbox
    assert 'docker_cleanup "$@"' in toolbox
    assert "docker_cleanup.sh" not in toolbox
    assert "table {{.ID}}\\t{{.Names}}\\t{{.Image}}\\t{{.Status}}\\t{{.RunningFor}}" in toolbox
    assert "# >->-> HAProxy <-<-<" not in toolbox


def test_toolbox_includes_enabled_haproxy_family() -> None:
    toolbox = render_toolbox(haproxy_enabled=True)

    assert "# >->-> HAProxy <-<-<" in toolbox
    assert "alias hpl='sudo journalctl -u haproxy'" in toolbox
    assert "alias hpc='sudo haproxy -c -f /etc/haproxy/haproxy.cfg -f /etc/haproxy/conf.d'" in toolbox
    assert "# >->-> Docker <-<-<" not in toolbox
