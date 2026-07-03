# assessment

This role collects host, service, container, Swarm, HTTP endpoint, log, and host audit assessment data.

## Features
- Run custom commands.
- Scan systemd journal logs.
- Scan Docker container logs.
- Scan Docker Swarm service logs.
- Run the toolbox host audit script when host audit is enabled.
- Run custom assessment commands.
- Inspect Docker containers.
- Gather recent Docker container logs.
- Gather recent systemd journal logs.
- Gather recent Docker Swarm service logs.
- Inspect Docker Swarm services.
- Verify Docker Swarm global services run on expected active nodes.
- Verify Docker Swarm replicated services have an exact desired and running replica count.

Host audit is opt-in via `assessment_audit_enabled: true`. When enabled, the role runs the always-installed toolbox `audit_host` script (installed by the `toolbox` role) and fails clearly when the script is missing or not executable. The assessment role does not install the daily audit cron job; host audit runs only as part of the dedicated `assess` action.

## Configuration
| Variable | Default |
| --- | --- |
| `assessment_common_systemd_units` | `[]` |
| `assessment_systemd_units` | `<derived>` |
| `assessment_docker_containers` | `[]` |
| `assessment_docker_container_health_required` | `true` |
| `assessment_swarm_services` | `[]` |
| `assessment_swarm_global_services` | `[]` |
| `assessment_swarm_replicated_services` | `[]` |
| `assessment_tcp_ports` | `[]` |
| `assessment_http_endpoints` | `[]` |
| `assessment_commands` | `[]` |
| `assessment_journal_units` | `<derived>` |
| `assessment_docker_log_containers` | `<derived>` |
| `assessment_swarm_log_services` | `<derived>` |
| `assessment_log_since_journal` | `24 hours ago` |
| `assessment_log_since_docker` | `24h` |
| `assessment_log_error_regex` | `'(?i)\b(fatal\|panic\|critical\|crit\|error\|exception\|traceback)\b'` |
| `assessment_log_ignore_regex` | `'(?i)\b(no errors?\|0 errors?\|without errors?\|error=0)\b\|level=(debug\|info\|warn\|warning)'` |
| `assessment_log_match_limit` | `20` |
| `assessment_audit_enabled` | `false` |
| `assessment_audit_toolbox_script` | `/opt/toolbox/bin/audit_host` |
| `assessment_audit_ssh_port` | `22` |
| `assessment_audit_ssh_users` | `[]` |
| `assessment_audit_admin_users` | `[]` |
| `assessment_audit_service_users` | `[]` |
| `assessment_audit_disk_threshold` | `90` |
| `assessment_audit_critical_systemd_units` | `[fail2ban, auditd, unattended-upgrades, docker]` |
| `assessment_audit_inactive_systemd_units` | `[]` |
| `assessment_audit_running_systemd_unit_file_states` | `[enabled, enabled-runtime]` |
| `assessment_audit_systemd_log_since_journal` | `5 minutes ago` |
| `assessment_audit_log_error_regex` | `<regex>` |
| `assessment_audit_log_ignore_regex` | `<regex>` |
| `assessment_audit_log_match_limit` | `20` |
| `assessment_audit_sysctl_params` | `<complex>` |

Use `assessment_swarm_replicated_services` entries as mappings with `name` and `replicas`.
Use `assessment_swarm_global_services` entries as service-name strings for every active node or mappings with `name` and optional `node_role` set to `all`, `manager`, or `worker`.

Set `assessment_audit_ssh_users`, `assessment_audit_admin_users`, and `assessment_audit_service_users` to the host user allowlists before enabling host audit. The `audit_host` script flags every `/home` user outside `audit_service_users + audit_admin_users` as unauthorized, so empty allowlists fail the audit on any host with local users.

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.assessment
```

Run the `toolbox` role from `setup` so `/opt/toolbox/bin/audit_host` exists before enabling `assessment_audit_enabled` on the dedicated `assess` action.
