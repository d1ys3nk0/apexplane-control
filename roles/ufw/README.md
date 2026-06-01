# ufw

This role configures UFW firewall rules.

## Features
- Gather service facts.
- Set default forward policy to ACCEPT.
- Generate user IPv4 rules.
- Generate empty IPv6 rules.
- Install after rules.
- Enable UFW.

## Configuration
Set these required inputs before applying the role: `ufw_ssh_cidr`, `ufw_vpc_cidr`.

| Variable | Default |
| --- | --- |
| `ufw_private_ports` | `[]` |
| `ufw_public_ports` | `[]` |
| `ufw_docker_ports` | `[]` |
| `ufw_docker_subnets` | `[]` |
| `ufw_ssh_cidr` | `~` |
| `ufw_vpc_cidr` | `~` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.ufw
      vars:
        ufw_ssh_cidr: <value>
        ufw_vpc_cidr: <value>
```
