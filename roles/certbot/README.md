# certbot

This role installs Certbot in a Python virtualenv and configures DNS-based certificate issuance helpers.

## Features
- Install Certbot under `/opt/certbot` by default.
- Issue configured non-wildcard certificates through HTTP-01 when needed.
- Validate HTTP-01 certificate domains through public DNS immediately before issuance.
- Optionally install the NIC.ru DNS authenticator plugin.
- Write NIC.ru credentials with root-only permissions.
- Install a `certonly dns-nicru` wrapper for explicit operator-driven issuance.
- Optionally install a HAProxy deploy hook that publishes renewed lineages as combined PEM files.
- Optionally spread changed HAProxy PEM files to remote HAProxy hosts after local validation and reload.
- Install and start a systemd timer for certificate renewal.

## Configuration
Set `certbot_enabled` and `certbot_dns_nicru_enabled` to `true` before applying the NIC.ru workflow. When NIC.ru is enabled, set `certbot_email` and all `certbot_dns_nicru_*` credential, scope, service, and zone inputs.

| Variable | Default |
| --- | --- |
| `certbot_enabled` | `false` |
| `certbot_install_dir` | `/opt/certbot` |
| `certbot_package_name` | `certbot` |
| `certbot_http_certs` | `{}` |
| `certbot_http_port` | `40404` |
| `certbot_http_dns_wait_retries` | `3` |
| `certbot_http_dns_wait_delay` | `10` |
| `certbot_dns_nicru_enabled` | `false` |
| `certbot_dns_nicru_package_version` | `1.0.3` |
| `certbot_dns_nicru_credentials_dir` | `/etc/letsencrypt/.secrets` |
| `certbot_dns_nicru_credentials_path` | `{{ certbot_dns_nicru_credentials_dir }}/nicru.ini` |
| `certbot_dns_nicru_propagation_seconds` | `300` |
| `certbot_dns_nicru_client_id` | `~` |
| `certbot_dns_nicru_client_secret` | `~` |
| `certbot_dns_nicru_username` | `~` |
| `certbot_dns_nicru_password` | `~` |
| `certbot_dns_nicru_scope` | `~` |
| `certbot_dns_nicru_service` | `~` |
| `certbot_dns_nicru_zone` | `~` |
| `certbot_email` | `~` |
| `certbot_server` | `https://acme-v02.api.letsencrypt.org/directory` |
| `certbot_rsa_key_size` | `4096` |
| `certbot_haproxy_deploy_hook_enabled` | `false` |
| `certbot_haproxy_cert_dir` | `/etc/ssl/haproxy` |
| `certbot_haproxy_cert_owner` | `haproxy` |
| `certbot_haproxy_cert_group` | `haproxy` |
| `certbot_haproxy_spread_targets` | `[]` |
| `certbot_haproxy_spread_ssh_user` | `''` |
| `certbot_haproxy_spread_ssh_private_key_file` | `~` |
| `certbot_haproxy_spread_ssh_dir` | `{{ certbot_install_dir }}/ssh` |
| `certbot_haproxy_spread_ssh_private_key_path` | `{{ certbot_haproxy_spread_ssh_dir }}/haproxy-spread` |
| `certbot_haproxy_spread_ssh_known_hosts_path` | `{{ certbot_haproxy_spread_ssh_dir }}/known_hosts` |
| `certbot_haproxy_spread_ssh_connect_timeout` | `10` |
| `certbot_haproxy_spread_ssh_strict_host_key_checking` | `accept-new` |
| `certbot_haproxy_spread_wildcards_only` | `true` |
| `certbot_renew_timer_enabled` | `true` |
| `certbot_renew_on_calendar` | `*-*-* 00,12:00:00` |
| `certbot_renew_randomized_delay_sec` | `1h` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.certbot
      vars:
        certbot_enabled: true
        certbot_dns_nicru_enabled: true
        certbot_email: admin@example.com
        certbot_dns_nicru_client_id: <value>
        certbot_dns_nicru_client_secret: <value>
        certbot_dns_nicru_username: <value>
        certbot_dns_nicru_password: <value>
        certbot_dns_nicru_scope: <value>
        certbot_dns_nicru_service: <value>
        certbot_dns_nicru_zone: example.com
```

Configure non-wildcard certificates for automatic HTTP-01 issuance:

```yaml
certbot_http_certs:
  app_example: app.example.com
```

Enable the HAProxy deploy hook only on hosts where HAProxy should consume the renewed PEM files:

```yaml
certbot_haproxy_deploy_hook_enabled: true
```

Configure HAProxy spread targets on an issuer host when changed wildcard PEM files should be pushed to remote HAProxy hosts:

```yaml
certbot_haproxy_deploy_hook_enabled: true
certbot_haproxy_spread_ssh_user: iac
certbot_haproxy_spread_ssh_private_key_file: /path/on/controller/iac-certbot.prd
certbot_haproxy_spread_targets:
  - name: app01
    host: 192.0.2.10
    port: 55555
```

Issue the first certificate explicitly after the role has configured the host:

```sh
sudo /opt/certbot/certonly dns-nicru wildcard-example -d '*.example.com'
```
