# iam

This role manages local administrative, service, and root account state.

## Features
- Configure root user.
- Configure admin users.
- Configure service users.
- Reconcile managed authorized SSH keys.
- Remove unmanaged users.
- Create a group for admins.
- Grant sudo access without password to the group.
- Create admin accounts.
- Generate missing admin ssh keys.
- Apply admin .bashrc.
- Get current home users before IAM cleanup.
- Additional focused setup tasks for the same role-owned desired state.

## Configuration
| Variable | Default |
| --- | --- |
| `iam_admin_group` | `wheel` |
| `iam_cleanup_mode` | `true` |
| `iam_interactive_mode` | `<derived>` |
| `iam_master_pass` | `''` |
| `iam_master_salt` | `''` |
| `iam_admin_users` | `[]` |
| `iam_service_users` | `[]` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.iam
```
