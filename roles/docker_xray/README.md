# docker_xray

This role runs Xray as a standalone Docker container.

## Features

- Renders a structured Xray `config.json` from role variables.
- Supports VLESS WebSocket inbounds, transparent `dokodemo-door` tunnel inbounds, and VLESS REALITY outbounds.
- Runs Xray in the host network namespace for reverse-proxy and TPROXY use cases.
- Optionally installs a systemd-managed TPROXY rules service.
- Validates the rendered Xray config with the pinned container image before updating the runtime config.
- Verifies that the container is running and inbound ports are ready.

## Configuration

| Variable | Default |
| --- | --- |
| `docker_xray_image_name` | `teddysun/xray` |
| `docker_xray_image_tag` | `<required>` |
| `docker_xray_image_full` | `<derived>` |
| `docker_xray_container_name` | `xray` |
| `docker_xray_config_dir` | `/opt/xray` |
| `docker_xray_config_filename` | `/etc/xray/config.json` |
| `docker_xray_network_mode` | `host` |
| `docker_xray_inbounds` | `[]` |
| `docker_xray_outbounds` | `[]` |
| `docker_xray_tproxy_enabled` | `false` |
| `docker_xray_tproxy_source_cidrs` | `[]` |
| `docker_xray_tproxy_bypass_cidrs` | `<reserved IPv4 ranges>` |

## Usage

```yaml
- role: apexplane.control.docker_xray
  vars:
    docker_xray_inbounds:
      - type: vless
        tag: vless-ws-in
        listen: 127.0.0.1
        port: 10080
        network: ws
        security: none
        users:
          - id: REPLACE_WITH_VAULT_XRAY_USER_ID
        ws:
          path: /ws
      - type: tunnel
        tag: wireguard-tproxy-in
        listen: 127.0.0.1
        port: 10081
    docker_xray_outbounds:
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
    docker_xray_tproxy_enabled: true
    docker_xray_tproxy_source_cidrs:
      - 10.42.42.42/32
```
