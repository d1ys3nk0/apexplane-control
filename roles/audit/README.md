# audit

This role installs baseline audit tooling and configuration.

## Features
- Include common security checks.
- Gather effective SSH configuration.
- Remember whether Docker service unit exists.
- Probe critical service status.
- Probe apt-daily-upgrade timer status.
- Get current local users from /home.
- Detect unauthorized local users.
- Stat critical security files.
- Stat /tmp directory.
- Audit Docker daemon configuration.

## Configuration
| Variable | Default |
| --- | --- |
| `audit_ssh_port` | `22` |
| `audit_ssh_users` | `[]` |
| `audit_admin_users` | `[]` |
| `audit_service_users` | `[]` |
| `audit_disk_threshold` | `90` |
| `audit_sysctl_params` | `<complex>` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.audit
```
