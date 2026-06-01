# preflight

This role validates baseline host prerequisites before other roles run.

## Features
- Provides the role entrypoint for reusable Ansible desired state.

## Configuration
Set these required inputs before applying the role: `preflight_cluster_name`, `preflight_cluster_realm`, `preflight_cluster_platform`, `preflight_region`, `preflight_vpc_cidr`, `preflight_zone`.

| Variable | Default |
| --- | --- |
| `preflight_cluster_platform_map` | `{}` |
| `preflight_cluster_name_list` | `[]` |
| `preflight_cluster_realm_list` | `[]` |
| `preflight_cluster_name` | `~` |
| `preflight_cluster_realm` | `~` |
| `preflight_cluster_platform` | `~` |
| `preflight_region` | `~` |
| `preflight_target_hosts` | `[]` |
| `preflight_vpc_addr` | `''` |
| `preflight_vpc_cidr` | `~` |
| `preflight_zone` | `~` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.preflight
      vars:
        preflight_cluster_name: <value>
        preflight_cluster_realm: <value>
        preflight_cluster_platform: <value>
        preflight_region: <value>
        preflight_vpc_cidr: <value>
        preflight_zone: <value>
```
