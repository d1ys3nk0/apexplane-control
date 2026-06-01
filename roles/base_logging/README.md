# base_logging

This role configures base rsyslog logging.

## Features
- Configure systemd journald SystemMaxUse.
- Restart systemd-journald.
- Install rsyslog.
- Detect existing rsyslog imudp module load.
- Remember existing rsyslog imudp module load.
- Deploy base rsyslog UDP configuration.
- Ensure rsyslog is enabled and running.
- Apply rsyslog handler before dependent roles.

## Configuration
| Variable | Default |
| --- | --- |
| `base_logging_journald_system_max_use` | `100M` |
| `base_logging_rsyslog_enabled` | `true` |
| `base_logging_rsyslog_udp_enabled` | `true` |
| `base_logging_rsyslog_udp_address` | `127.0.0.1` |
| `base_logging_rsyslog_udp_port` | `514` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.base_logging
```
