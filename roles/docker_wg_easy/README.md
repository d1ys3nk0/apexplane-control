# docker_wg_easy

This role runs wg-easy as a standalone Docker container.

## Features

- Creates a dedicated Docker bridge network for the wg-easy container.
- Stores wg-easy state under a host directory mounted at `/etc/wireguard`.
- Publishes the WireGuard UDP port publicly and binds the web UI port to a configurable host address.
- Supports wg-easy v15 unattended first-run setup with role-owned `no_log` for bootstrap credentials.
- Reconciles the container without first-run credentials after the wg-easy database exists so secrets are not retained in Docker inspect output.
- Verifies that the container is running and that the web UI port is ready.

## Configuration

Set these required inputs before first apply: `docker_wg_easy_init_username`, `docker_wg_easy_init_password`, and `docker_wg_easy_init_host`.

| Variable | Default |
| --- | --- |
| `docker_wg_easy_image_name` | `ghcr.io/wg-easy/wg-easy` |
| `docker_wg_easy_image_tag` | `<required>` |
| `docker_wg_easy_image_full` | `<derived>` |
| `docker_wg_easy_container_name` | `wg-easy` |
| `docker_wg_easy_data_dir` | `/opt/wg-easy/wireguard` |
| `docker_wg_easy_modules_dir` | `/lib/modules` |
| `docker_wg_easy_network_name` | `wg-easy` |
| `docker_wg_easy_network_driver` | `bridge` |
| `docker_wg_easy_network_subnet` | `10.42.42.0/24` |
| `docker_wg_easy_network_gateway` | `10.42.42.1` |
| `docker_wg_easy_network_ipv4_address` | `10.42.42.42` |
| `docker_wg_easy_wireguard_port` | `51820` |
| `docker_wg_easy_web_port` | `51821` |
| `docker_wg_easy_web_host` | `0.0.0.0` |
| `docker_wg_easy_web_publish_host` | `127.0.0.1` |
| `docker_wg_easy_insecure` | `true` |
| `docker_wg_easy_disable_ipv6` | `true` |
| `docker_wg_easy_init_username` | `~` |
| `docker_wg_easy_init_password` | `~` |
| `docker_wg_easy_init_host` | `~` |
| `docker_wg_easy_init_port` | `51820` |
| `docker_wg_easy_init_dns` | `[]` |
| `docker_wg_easy_init_ipv4_cidr` | `10.8.0.0/24` |
| `docker_wg_easy_init_ipv6_cidr` | `fdcc:ad94:bacf:61a3::/64` |
| `docker_wg_easy_init_allowed_ips` | `[]` |
| `docker_wg_easy_mem_res` | `128M` |
| `docker_wg_easy_mem_lim` | `256M` |
| `docker_wg_easy_mem_swp` | `512M` |

The role always passes `INIT_IPV4_CIDR` and `INIT_IPV6_CIDR` together because wg-easy v15 treats those settings as one setup group. Set `docker_wg_easy_disable_ipv6: true` when the deployment should not issue functional IPv6 client routing.

## Usage

```yaml
- role: apexplane.control.docker_wg_easy
  vars:
    docker_wg_easy_init_username: admin
    docker_wg_easy_init_password: "<vaulted password>"
    docker_wg_easy_init_host: vpn.example.com
    docker_wg_easy_init_allowed_ips:
      - 10.0.0.0/8
```
