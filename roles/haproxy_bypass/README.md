# haproxy_bypass

This role renders an HAProxy bypass configuration.

## Features
- Render HAProxy bypass proxy fragments.

## Configuration
| Variable | Default |
| --- | --- |
| `haproxy_bypass_endpoints` | `[]` |
| `haproxy_bypass_default_client_timeout` | `1h` |
| `haproxy_bypass_default_server_timeout` | `1h` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.haproxy_bypass
```
