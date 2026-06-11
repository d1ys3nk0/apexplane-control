# docker_swarm_xray

This role runs Xray as a Docker Swarm service.

## Features
- Render a structured Xray `config.json` from role variables.
- Support HTTP proxy, VLESS REALITY inbound, VLESS REALITY outbound, and freedom outbound entries.
- Publish inbound ports through Swarm ingress.
- Validate the rendered Xray config with the pinned container image before updating the service.
- Store the rendered config as an immutable hash-named Docker config.
- Use start-first rolling updates with rollback on update failure.
- Verify the Swarm service and wait for published ports.

## Configuration
| Variable | Default |
| --- | --- |
| `docker_swarm_xray_image_name` | `teddysun/xray` |
| `docker_swarm_xray_image_tag` | `26.6.1` |
| `docker_swarm_xray_image_full` | `<derived>` |
| `docker_swarm_xray_enabled` | `true` |
| `docker_swarm_xray_service_name` | `xray` |
| `docker_swarm_xray_config_filename` | `/etc/xray/config.json` |
| `docker_swarm_xray_loglevel` | `warning` |
| `docker_swarm_xray_inbounds` | `[]` |
| `docker_swarm_xray_outbounds` | `[]` |
| `docker_swarm_xray_routing` | `{}` |
| `docker_swarm_xray_mem_res` | `128M` |
| `docker_swarm_xray_mem_lim` | `1G` |
| `docker_swarm_xray_cpu_res` | `0.1` |
| `docker_swarm_xray_cpu_lim` | `1.0` |
| `docker_swarm_xray_replicas` | `1` |
| `docker_swarm_xray_update_parallelism` | `1` |
| `docker_swarm_xray_update_delay` | `10s` |
| `docker_swarm_xray_update_monitor` | `30s` |

## Usage
HTTP proxy to a VLESS REALITY next hop:

```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.docker_swarm_xray
      docker_swarm_xray_inbounds:
        - type: http
          tag: http-in
          port: 3128
      docker_swarm_xray_outbounds:
        - type: vless
          tag: vless-reality-out
          address: xray-next.example.net
          port: 443
          id: REPLACE_WITH_VAULT_XRAY_USER_ID
          reality:
            server_name: www.microsoft.com
            password: REPLACE_WITH_VAULT_XRAY_REALITY_PASSWORD
            short_id: REPLACE_WITH_VAULT_XRAY_REALITY_SHORT_ID
            spider_x: /
```

Public VLESS REALITY server to direct internet:

```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.docker_swarm_xray
      docker_swarm_xray_inbounds:
        - type: vless
          tag: vless-reality-in
          port: 443
          users:
            - id: REPLACE_WITH_VAULT_XRAY_USER_ID
          reality:
            target: www.microsoft.com:443
            server_names:
              - www.microsoft.com
            private_key: REPLACE_WITH_VAULT_XRAY_REALITY_PRIVATE_KEY
            short_ids:
              - REPLACE_WITH_VAULT_XRAY_REALITY_SHORT_ID
      docker_swarm_xray_outbounds:
        - type: freedom
          tag: direct-out
```

For `http` inbounds, `port` is the Swarm-published port and `xray_port` defaults to `1080`. For `vless` inbounds, `port` is also the Swarm-published port and `xray_port` defaults to the same value. Set `tag` explicitly when routing rules need stable names. Swarm ingress publishing does not support role-level host bind addresses, so every inbound is published through the Swarm routing mesh.
