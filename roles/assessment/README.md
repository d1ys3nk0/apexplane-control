# assessment

This role collects host, service, container, Swarm, HTTP endpoint, and log assessment data.

## Features
- Run custom commands.
- Scan systemd journal logs.
- Scan Docker container logs.
- Scan Docker Swarm service logs.
- Run custom assessment commands.
- Inspect Docker containers.
- Gather recent Docker container logs.
- Gather recent systemd journal logs.
- Gather recent Docker Swarm service logs.
- Inspect Docker Swarm services.
- Verify Docker Swarm global services run on every active node.
- Verify Docker Swarm replicated services have an exact desired and running replica count.

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

Use `assessment_swarm_replicated_services` entries as mappings with `name` and `replicas`.

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.assessment
```
