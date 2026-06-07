# audit

This role installs baseline audit tooling and configuration.

## Features
- Include common security checks.
- Gather effective SSH configuration.
- Remember whether Docker service unit exists.
- Assert critical service units are installed.
- Discover installed service units and assert auto-started long-running services are active.
- Scan recent installed service journal logs for errors.
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
| `audit_critical_systemd_units` | `[fail2ban, auditd, unattended-upgrades, docker]` |
| `audit_running_systemd_unit_file_states` | `[enabled, enabled-runtime]` |
| `audit_systemd_log_since_journal` | `5 minutes ago` |
| `audit_log_error_regex` | `<regex>` |
| `audit_log_ignore_regex` | `<regex>` |
| `audit_log_match_limit` | `20` |
| `audit_sysctl_params` | `<complex>` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.audit
```
