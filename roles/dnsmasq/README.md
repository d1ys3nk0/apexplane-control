# dnsmasq

This role configures dnsmasq, resolver integration, and local health checks.

## Features
- Run dnsmasq service tasks.
- Run dnsmasq health checks.
- Run local resolver tasks.
- Install dnsmasq packages.
- Create dnsmasq config directory.
- Deploy dnsmasq configuration.
- Serve exact records as local-only DNS data without forwarding unresolved record types upstream.
- Ensure dnsmasq service is enabled and running.
- Restart dnsmasq after configuration changes.
- Read eth0 DNS resolver from netplan.
- Set local DNS resolver for eth0 interface.
- Additional focused setup tasks for the same role-owned desired state.

## Configuration

Each `dnsmasq_exact_records` entry returns the configured A or AAAA record and treats its name as local-only for every query type. Each `dnsmasq_health_checks` entry requires exactly the configured address from the matching A or AAAA query and no response records from the other address family.

| Variable | Default |
| --- | --- |
| `dnsmasq_bind_addresses` | `[]` |
| `dnsmasq_config_dir` | `/etc/dnsmasq.d` |
| `dnsmasq_config_path` | `<derived>` |
| `dnsmasq_exact_records` | `[]` |
| `dnsmasq_health_check_server` | `''` |
| `dnsmasq_health_checks` | `[]` |
| `dnsmasq_local_resolver` | `''` |
| `dnsmasq_upstream_servers` | `[]` |
| `dnsmasq_wildcard_records` | `[]` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.dnsmasq
```
