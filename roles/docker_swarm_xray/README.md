# docker_swarm_xray

This role runs Xray as a Docker Swarm service.

## Features
- Render a structured Xray `config.json` from role variables.
- Support HTTP proxy, VLESS REALITY inbound, VLESS WebSocket inbound, VLESS REALITY outbound, and freedom outbound entries.
- Publish inbound ports through Swarm ingress.
- Validate the rendered Xray config with the pinned container image before updating the service.
- Store the rendered config as an immutable hash-named Docker config.
- Optionally publish a small HTTP redirect fallback service for public port 80.
- Use start-first rolling updates with rollback on update failure.
- Verify the Swarm service and wait for published ports.

## Configuration
| Variable | Default |
| --- | --- |
| `docker_swarm_xray_image_name` | `teddysun/xray` |
| `docker_swarm_xray_image_tag` | `<required>` |
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
| `docker_swarm_xray_fallback_enabled` | `false` |
| `docker_swarm_xray_fallback_service_name` | `xray-fallback` |
| `docker_swarm_xray_fallback_image_name` | `nginx` |
| `docker_swarm_xray_fallback_image_tag` | `<required>` |
| `docker_swarm_xray_fallback_image_full` | `<derived>` |
| `docker_swarm_xray_fallback_redirect_host` | `~` |
| `docker_swarm_xray_fallback_port` | `80` |
| `docker_swarm_xray_fallback_config_filename` | `/etc/nginx/conf.d/default.conf` |
| `docker_swarm_xray_fallback_mem_res` | `32M` |
| `docker_swarm_xray_fallback_mem_lim` | `128M` |
| `docker_swarm_xray_fallback_cpu_res` | `0.05` |
| `docker_swarm_xray_fallback_cpu_lim` | `0.25` |

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
      docker_swarm_xray_fallback_enabled: true
      docker_swarm_xray_fallback_redirect_host: www.microsoft.com
```

VLESS WebSocket entry behind an HTTP reverse proxy:

```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.docker_swarm_xray
      docker_swarm_xray_inbounds:
        - type: vless
          tag: vless-ws-in
          port: 10080
          network: ws
          security: none
          users:
            - id: REPLACE_WITH_VAULT_XRAY_USER_ID
          ws:
            path: /api/live/ws/REPLACE_WITH_SECRET_PATH_SUFFIX
      docker_swarm_xray_outbounds:
        - type: vless
          tag: vless-reality-out
          address: xray-next.example.net
          port: 443
          id: REPLACE_WITH_VAULT_XRAY_EXIT_USER_ID
          reality:
            server_name: www.microsoft.com
            password: REPLACE_WITH_VAULT_XRAY_EXIT_PUBLIC_KEY
            short_id: REPLACE_WITH_VAULT_XRAY_EXIT_SHORT_ID
            spider_x: /
```

For `http` inbounds, `port` is the Swarm-published port and `xray_port` defaults to `1080`. For `vless` inbounds, `port` is also the Swarm-published port and `xray_port` defaults to the same value. Set `tag` explicitly when routing rules need stable names. Swarm ingress publishing does not support role-level host bind addresses, so every inbound is published through the Swarm routing mesh.

For `vless` inbounds, omitted transport settings keep the original VLESS REALITY behavior: `network: raw`, `security: reality`, and a required `reality` mapping. Set `network: ws`, `security: none`, and `ws.path` for VLESS WebSocket inbounds behind an HTTP reverse proxy. WebSocket users do not receive a default `flow`; define one explicitly only when the selected transport supports it.

When `docker_swarm_xray_fallback_enabled` is true, the role also publishes `docker_swarm_xray_fallback_port` through Swarm ingress and serves a redirect to `https://{{ docker_swarm_xray_fallback_redirect_host }}`. The redirect host must be a hostname without a scheme or path.
