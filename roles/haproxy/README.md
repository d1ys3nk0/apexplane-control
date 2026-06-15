# haproxy

This role configures HAProxy logging support.

## Features
- Install HAProxy.
- Create HAProxy config fragment directory.
- Create systemd override directory.
- Deploy HAProxy systemd override.
- Configure HAProxy logging.
- Enable HAProxy service.
- Restart HAProxy after systemd override changes.
- Ensure HAProxy log directory exists.
- Remove previous managed HAProxy rsyslog configuration.
- Deploy HAProxy rsyslog configuration.
- Deploy HAProxy logrotate configuration.

## Configuration
| Variable | Default |
| --- | --- |
| `haproxy_log_dir` | `/var/log/haproxy` |
| `haproxy_log_traffic_file` | `<derived>` |
| `haproxy_log_admin_file` | `<derived>` |
| `haproxy_rsyslog_user` | `syslog` |
| `haproxy_rsyslog_group` | `adm` |
| `haproxy_rsyslog_stop_after_local0` | `true` |
| `haproxy_rsyslog_stop_after_local1` | `true` |
| `haproxy_logrotate_frequency` | `daily` |
| `haproxy_logrotate_rotate` | `14` |
| `haproxy_logrotate_compress` | `true` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.haproxy
```
