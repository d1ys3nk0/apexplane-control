# base_bootstrap

This role applies baseline host locale, time, network, system, and service settings.

## Features
- Run system tasks.
- Run system service tasks.
- Run system network tasks.
- Run system locale tasks.
- Run system time and timezone tasks.
- Stop and disable configured installed system services.
- Generate locale.
- Set locale.
- Read eth0 MTU from netplan.
- Set MTU for eth0 interface.
- Read eth0 DNS resolver from netplan.
- Additional focused setup tasks for the same role-owned desired state.

## Configuration
Set these required inputs before applying the role: `base_bootstrap_cluster_realm`, `base_bootstrap_fqdn_ext`, `base_bootstrap_fqdn_int`.

| Variable | Default |
| --- | --- |
| `base_bootstrap_cluster_realm` | `~` |
| `base_bootstrap_disabled_services` | `[]` |
| `base_bootstrap_dns_resolver` | `''` |
| `base_bootstrap_dns_resolver_checks` | `[]` |
| `base_bootstrap_fqdn_ext` | `~` |
| `base_bootstrap_fqdn_int` | `~` |
| `base_bootstrap_mtu` | `''` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.base_bootstrap
      vars:
        base_bootstrap_cluster_realm: <value>
        base_bootstrap_fqdn_ext: <value>
        base_bootstrap_fqdn_int: <value>
```
