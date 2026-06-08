# audit

This role runs baseline host audit checks through the toolbox audit script.

## Features
- Run `/opt/toolbox/bin/audit_host` with role-provided audit settings.
- Install a daily quiet audit cron job.
- Write only current audit issues to the configured cron log path.

## Configuration
| Variable | Default |
| --- | --- |
| `audit_ssh_port` | `22` |
| `audit_ssh_users` | `[]` |
| `audit_admin_users` | `[]` |
| `audit_service_users` | `[]` |
| `audit_disk_threshold` | `90` |
| `audit_critical_systemd_units` | `[fail2ban, auditd, unattended-upgrades, docker]` |
| `audit_inactive_systemd_units` | `[]` |
| `audit_running_systemd_unit_file_states` | `[enabled, enabled-runtime]` |
| `audit_systemd_log_since_journal` | `5 minutes ago` |
| `audit_log_error_regex` | `<regex>` |
| `audit_log_ignore_regex` | `<regex>` |
| `audit_log_match_limit` | `20` |
| `audit_cron_enabled` | `true` |
| `audit_cron_hour` | `4` |
| `audit_cron_minute` | `0` |
| `audit_cron_log_path` | `/var/log/audit-host-issues.log` |
| `audit_sysctl_params` | `<complex>` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.toolbox
    - role: apexplane.control.audit
```

## Operations
Run the `toolbox` role before this role so `/opt/toolbox/bin/audit_host` exists. The audit role fails clearly when the script is missing.

The role runs the script during Ansible execution and installs `/etc/cron.d/audit-host` when `audit_cron_enabled` is true. The cron job uses `CRON_TZ=UTC`, runs at `audit_cron_hour:audit_cron_minute`, and executes:

```sh
/opt/toolbox/bin/audit_host --quiet > /var/log/audit-host-issues.log
```

Quiet mode prints only found issues to stdout. Each cron run replaces the log file, so a clean run leaves the file empty.
