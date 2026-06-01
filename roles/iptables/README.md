# iptables

This role installs managed iptables configuration.

## Features
- Gather service facts.
- Create directories.
- Create iptables service file.
- Update script.
- Update rules.
- Activate new rules.
- Service is started and enabled.

## Configuration
Set these required inputs before applying the role: `iptables_ssh_cidr`, `iptables_vpc_cidr`.

| Variable | Default |
| --- | --- |
| `iptables_private_ports` | `[]` |
| `iptables_public_ports` | `[]` |
| `iptables_ssh_cidr` | `~` |
| `iptables_vpc_cidr` | `~` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.iptables
      vars:
        iptables_ssh_cidr: <value>
        iptables_vpc_cidr: <value>
```
