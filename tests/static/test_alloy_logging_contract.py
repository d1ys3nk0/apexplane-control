from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
ALLOY_CONFIG_TEMPLATE = REPO_ROOT / "roles" / "alloy" / "templates" / "config.alloy.j2"


def test_alloy_file_log_targets_are_explicit() -> None:
    template = ALLOY_CONFIG_TEMPLATE.read_text(encoding="utf-8")

    assert '__path__ = "/var/log/*.log"' not in template
    assert '__path__ = "/var/log/syslog"' in template
    assert '__path__ = "/var/log/auth.log"' in template
    assert '__path__ = "/var/log/kern.log"' in template
    assert 'loki.source.journal "journal_logs"' in template
