# haproxy_alb

This role configures HAProxy as an application load balancer with existing PEM certificates.

## Features
- Configure self-signed SSL certificate.
- Find HAProxy ALB backend fragments.
- Store desired HAProxy ALB backend fragment paths.
- Remove unmanaged HAProxy ALB backend fragments.
- Update HAProxy system backend fragment.
- Update HAProxy local backend fragment.
- Update HAProxy backend fragments per target group.
- Update HAProxy throttle backend fragments.
- Upload HAProxy whitelist files.
- Update HAProxy frontend config.
- Route ACME HTTP-01 challenge requests to the configured local challenge backend.
- Validate existing HAProxy PEM certificates when `haproxy_alb_certs` is configured.
- Additional focused setup tasks for the same role-owned desired state.

## Configuration
Set this required input before applying the role: `haproxy_alb_self_signed_cert_domain`.

| Variable | Default |
| --- | --- |
| `haproxy_alb_crowdsec_enabled` | `false` |
| `haproxy_alb_crowdsec_body_limit` | `51200` |
| `haproxy_alb_crowdsec_spoa_port` | `9000` |
| `haproxy_alb_stats_port` | `8404` |
| `haproxy_alb_prometheus_exporter_port` | `8405` |
| `haproxy_alb_acme_enabled` | `true` |
| `haproxy_alb_acme_port` | `40404` |
| `haproxy_alb_redirect_all_http` | `false` |
| `haproxy_alb_whitelists` | `{}` |
| `haproxy_alb_whitelists_enforced` | `[]` |
| `haproxy_alb_throttles` | `[]` |
| `haproxy_alb_throttle_table_size` | `100k` |
| `haproxy_alb_throttle_deny_status` | `429` |
| `haproxy_alb_trusted_proxy_cidrs` | `<complex>` |
| `haproxy_alb_self_signed_cert_domain` | `~` |
| `haproxy_alb_certs` | `{}` |
| `haproxy_alb_target_groups` | `{}` |
| `haproxy_alb_routes` | `[]` |
| `haproxy_alb_auth_whitelist_cidrs` | `[]` |
| `haproxy_alb_auth` | `[]` |
| `haproxy_alb_userlists` | `{}` |
| `haproxy_alb_default_target_group` | `''` |
| `haproxy_alb_default_target_host` | `''` |
| `haproxy_alb_default_target_port` | `80` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.haproxy_alb
      vars:
        haproxy_alb_self_signed_cert_domain: <value>
```
