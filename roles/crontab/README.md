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
| `crontab_yes_mode` | `<derived>` |
| `crontab_jobs` | `{}` |
| `crontab_spool_dir` | `/var/spool/cron/crontabs` |

Changed crontab reconciliation prompts by default in interactive live runs and requires typing exactly `yes`. Set `YES=1` or `YES=true` to preapprove replacement. Set `INTERACTIVE=0` or `INTERACTIVE=false` to fail instead of prompting when approval is required and `YES` is not set.

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.crontab
```
