# base_autoupdates

This role configures unattended package updates.

## Features
- Run automatic security updates tasks.
- Install automatic update tooling.
- Configure unattended upgrades periodic schedule.
- Configure apt daily upgrade timer override directory.
- Configure unattended upgrades maintenance window.
- Restart apt daily upgrade timer after maintenance window change.
- Configure unattended upgrades package blacklist.
- Configure unattended upgrades policy.
- Configure needrestart restart policy.
- Ensure unattended-upgrades service is enabled.
- Ensure apt daily upgrade timer is enabled.
- Disable unattended upgrades when requested.

## Configuration
| Variable | Default |
| --- | --- |
| `base_autoupdates_enabled` | `true` |
| `base_autoupdates_automatic_reboot_enabled` | `false` |
| `base_autoupdates_maintenance_window` | `''` |
| `base_autoupdates_needrestart_mode` | `l` |
| `base_autoupdates_package_blacklist` | Docker and container runtime packages |

`base_autoupdates_package_blacklist` defaults to Docker and container runtime packages to avoid unattended Docker upgrades causing service restarts and production downtime on single-node hosts. Override the list if a consumer has a different maintenance model.

`base_autoupdates_needrestart_mode` defaults to `l`, so `needrestart` reports services that need restart instead of restarting them automatically. Set it to `a` only when automatic service restarts are acceptable.

`base_autoupdates_automatic_reboot_enabled` controls host reboot after unattended upgrades and defaults to `false`. Package blacklisting, service restart policy, and host reboot policy are separate safeguards.

When `base_autoupdates_enabled` is `false`, the role disables the APT periodic unattended-upgrade schedule and stops/disables `apt-daily-upgrade.timer`. It does not uninstall packages or remove role-managed config files.

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.base_autoupdates
```
