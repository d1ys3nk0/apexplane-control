# base_autoupdates

This role configures unattended package updates.

## Features
- Run automatic security updates tasks.
- Install automatic update tooling.
- Configure unattended upgrades periodic schedule.
- Configure apt daily upgrade timer override directory.
- Configure unattended upgrades maintenance window.
- Restart apt daily upgrade timer after maintenance window change.
- Configure unattended upgrades policy.
- Configure needrestart to auto-restart services.
- Ensure unattended-upgrades service is enabled.
- Ensure apt daily upgrade timer is enabled.

## Configuration
| Variable | Default |
| --- | --- |
| `base_autoupdates_automatic_reboot_enabled` | `false` |
| `base_autoupdates_maintenance_window` | `''` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.base_autoupdates
```
