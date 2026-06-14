# iam

This role manages local administrative, service, and root account state.

## Features
- Configure root user.
- Configure provision user.
- Configure provision user PAM resource limits.
- Configure admin users.
- Configure service users.
- Reconcile managed authorized SSH keys.
- Remove unmanaged users.
- Create a group for admins.
- Grant sudo access without password to the group.
- Create admin accounts.
- Generate missing admin ssh keys.
- Apply admin .bashrc.
- Enable lingering for admin accounts.
- Get current local home users before IAM cleanup.
- Additional focused setup tasks for the same role-owned desired state.

## Configuration
| Variable | Default |
| --- | --- |
| `iam_admin_group` | `wheel` |
| `iam_admin_linger_enabled` | `false` |
| `iam_cleanup_mode` | `true` |
| `iam_interactive_mode` | `<derived>` |
| `iam_master_pass` | `~` |
| `iam_master_salt` | `~` |
| `iam_provision_user_name` | `iac` |
| `iam_provision_user_groups` | `[]` |
| `iam_provision_user_authorized_key_files` | `[]` |
| `iam_provision_user_private_key_file` | `~` |
| `iam_provision_user_public_key_file` | `~` |
| `iam_provision_user_sudo_commands` | `['ALL']` |
| `iam_admin_users` | `[]` |
| `iam_service_users` | `[]` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.iam
```
