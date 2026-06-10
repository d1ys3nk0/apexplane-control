from __future__ import annotations

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
HAPROXY_ALB_DIR = REPO_ROOT / "roles" / "haproxy_alb"
FE_WEB_TEMPLATE = HAPROXY_ALB_DIR / "templates" / "haproxy" / "fe_web.cfg.j2"
MAIN_TEMPLATE = HAPROXY_ALB_DIR / "templates" / "haproxy" / "haproxy.cfg.j2"
