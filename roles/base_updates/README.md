# base_updates

This role runs baseline package update tasks.

## Features
- Update apt packages.

## Configuration
| Variable | Default |
| --- | --- |
| `base_updates_autoclean` | `true` |
| `base_updates_autoremove` | `true` |
| `base_updates_cache` | `true` |
| `base_updates_upgrade` | `safe` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.base_updates
```
