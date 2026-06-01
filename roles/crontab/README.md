# crontab

This role renders a managed user crontab.

## Features
- Store managed crontab users.
- Reconcile managed user crontab.
- Render desired user crontab content.
- Compare managed user crontab.
- Store crontab reconciliation plan.
- Store changed managed crontab.
- Refuse changed crontab reconciliation in non-interactive mode.
- Report changed crontab reconciliation in check mode.
- Confirm changed crontab reconciliation.
- Install managed user crontab.
- Additional focused setup tasks for the same role-owned desired state.

## Configuration
| Variable | Default |
| --- | --- |
| `crontab_interactive_mode` | `<derived>` |
| `crontab_jobs` | `{}` |
| `crontab_spool_dir` | `/var/spool/cron/crontabs` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.crontab
```
