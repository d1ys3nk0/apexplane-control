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
