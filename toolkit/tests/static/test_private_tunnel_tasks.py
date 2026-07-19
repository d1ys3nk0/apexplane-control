from __future__ import annotations

from typing import cast

import yaml
from apc_target_static import target_repo_root


REPO_ROOT = target_repo_root()
ROOT_TASKFILE = REPO_ROOT / "Taskfile.yml"
TUNNEL_TASKFILE_SUFFIX = "apexplane/control/toolkit/tunnel.yml"
SERVICE_CONTRACTS = {
    "dockhand": (3000, 3000, "/"),
    "haproxy": (8404, 8404, "/_stats;norefresh"),
    "traefik": (1080, 1080, "/dashboard/"),
    "wg-easy": (51821, 51821, "/"),
}


def test_private_tunnel_task_names_and_fixed_service_contracts() -> None:
    data = yaml.safe_load(ROOT_TASKFILE.read_text(encoding="utf-8"))
    assert isinstance(data, dict)
    includes = data["includes"]
    assert isinstance(includes, dict)

    tunnel_includes = {
        str(name): cast("dict[str, object]", include)
        for name, include in includes.items()
        if isinstance(include, dict) and str(include.get("taskfile", "")).endswith(TUNNEL_TASKFILE_SUFFIX)
    }
    assert tunnel_includes

    for name, include in tunnel_includes.items():
        variables = include["vars"]
        assert isinstance(variables, dict)
        variables = cast("dict[str, object]", variables)
        service = variables["SERVICE"]
        assert isinstance(service, str)
        assert service in SERVICE_CONTRACTS
        local_port, remote_port, url_path = SERVICE_CONTRACTS[service]
        assert name == (f"{variables['REALM']}:{variables['PLATFORM']}:{variables['CLUSTER']}:{service}")
        assert variables["LOCAL_PORT"] == local_port
        assert variables["REMOTE_PORT"] == remote_port
        assert variables["URL_PATH"] == url_path
