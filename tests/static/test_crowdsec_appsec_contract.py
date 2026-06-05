from __future__ import annotations

from pathlib import Path
from typing import cast

import yaml


REPO_ROOT = Path(__file__).resolve().parents[2]
CROWDSEC_DIR = REPO_ROOT / "roles" / "crowdsec"


def _crowdsec_defaults() -> dict[str, object]:
    defaults = yaml.safe_load((CROWDSEC_DIR / "defaults" / "main.yml").read_text(encoding="utf-8"))
    assert isinstance(defaults, dict)
    return cast("dict[str, object]", defaults)


def test_crowdsec_default_collections_include_http_scanner_and_appsec_coverage() -> None:
    defaults = _crowdsec_defaults()
    collections = defaults["crowdsec_collections"]
    assert isinstance(collections, list)

    expected_collections = {
        "crowdsecurity/haproxy",
        "crowdsecurity/base-http-scenarios",
        "crowdsecurity/http-cve",
        "crowdsecurity/wordpress",
        "crowdsecurity/appsec-virtual-patching",
        "crowdsecurity/appsec-generic-rules",
    }

    assert expected_collections <= set(collections)


def test_crowdsec_appsec_acquisition_references_hub_config_without_shadowing_it() -> None:
    appsec_acquisition = (CROWDSEC_DIR / "templates" / "appsec.yaml.j2").read_text(encoding="utf-8")
    role_tasks = (CROWDSEC_DIR / "tasks" / "main.yml").read_text(encoding="utf-8")

    assert "appsec_configs:" in appsec_acquisition
    assert "- '{{ crowdsec_appsec_config }}'" in appsec_acquisition
    assert not (CROWDSEC_DIR / "templates" / "appsec-config.yaml.j2").exists()
    assert "src: appsec-config.yaml.j2" not in role_tasks
    assert "dest: /etc/crowdsec/appsec-configs/{{ crowdsec_appsec_config_filename }}" not in role_tasks


def test_crowdsec_spoa_bouncer_forwards_requests_to_appsec() -> None:
    defaults = _crowdsec_defaults()
    spoa_template = (CROWDSEC_DIR / "templates" / "crowdsec-spoa-bouncer.yaml.j2").read_text(encoding="utf-8")

    assert "crowdsec_appsec_url" in defaults
    assert "crowdsec_appsec_timeout" in defaults
    assert "crowdsec_spoa_hosts" in defaults
    assert "appsec_url: '{{ crowdsec_appsec_url }}'" in spoa_template
    assert "appsec_timeout: '{{ crowdsec_appsec_timeout }}'" in spoa_template
    assert "{% for crowdsec_spoa_host in crowdsec_spoa_hosts %}" in spoa_template
    assert "appsec:" in spoa_template
    assert "always_send: {{ crowdsec_spoa_host.appsec.always_send | bool | lower }}" in spoa_template
    assert "host: '*'" in (CROWDSEC_DIR / "defaults" / "main.yml").read_text(encoding="utf-8")
