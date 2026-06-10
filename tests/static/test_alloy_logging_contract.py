from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
ALLOY_CONFIG_TEMPLATE = REPO_ROOT / "roles" / "alloy" / "templates" / "config.alloy.j2"
