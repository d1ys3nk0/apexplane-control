# haproxy_alb

This role configures HAProxy as an application load balancer. HAProxy reads existing PEM certificates from `/etc/ssl/haproxy`; certificate issuance and deployment are owned by Certbot or another external certificate manager.

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
- Generate a per-request HAProxy UUID and forward it to backends as `X-Request-ID`.
- Set or delete route-specific response headers.
- Route ACME HTTP-01 challenge requests to the configured local challenge backend.
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
| `haproxy_alb_tunnel_timeout` | `1h` |
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
| `haproxy_alb_target_groups` | `{}` |
| `haproxy_alb_routes` | `[]` |
| `haproxy_alb_auth_whitelist_cidrs` | `[]` |
| `haproxy_alb_auth` | `[]` |
| `haproxy_alb_userlists` | `{}` |
| `haproxy_alb_default_target_group` | `''` |
| `haproxy_alb_default_target_host` | `''` |
| `haproxy_alb_default_target_port` | `80` |

Routes may set `restricted_cidrs` as a list of IPv4 CIDR strings. Matching requests from other source addresses are denied with `403`. When a restricted route also sets `prefix_whitelist`, matching path prefixes remain reachable from any source address. Routes may also set `response_headers` as a mapping of header name to value and `response_header_deletes` as a list of header names to delete from responses selected for that route.

HAProxy generates one UUID per request and forwards it to backends as `X-Request-ID`. Application logs and tracing can use this header as the request correlation identifier.

Auth rules may set `userlist_skip_cidrs` as a list of IPv4 CIDR strings. Matching requests bypass basic auth for that rule's `userlist`.

Auth rules may set `frame_parent_whitelist` as a list of HTTPS origins. Exact origins such as `https://app.example.test` and leading-wildcard origins such as `https://*.example.test` bypass basic auth only for iframe navigations from matching parents and same-origin subresources loaded by that framed page.

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.haproxy_alb
      vars:
        haproxy_alb_self_signed_cert_domain: <value>
```
