# base_hardening

This role applies baseline SSH, auditd, and sysctl hardening.

## Features
- Run SSH tasks.
- Run logind tasks.
- Run sysctl tasks.
- Run host audit tasks.
- Install audit tooling.
- Configure user process persistence after logout.
- Ensure auditd service is enabled.
- Ensure SSH drop-in directory exists.
- Deploy managed SSH hardening drop-in.
- Ensure SSH include directive is present.
- Restart SSH.
- Configure sysctl.
- Additional focused setup tasks for the same role-owned desired state.

## Configuration
Set these required inputs before applying the role: `base_hardening_limits_user`.

| Variable | Default |
| --- | --- |
| `base_hardening_limits_user` | `~` |
| `base_hardening_user_process_persistence_enabled` | `false` |
| `base_hardening_ssh_port` | `22` |
| `base_hardening_ssh_users` | `[]` |
| `base_hardening_sysctl_config` | `<complex>` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.base_hardening
      vars:
        base_hardening_limits_user: <value>
```
