# fail2ban

This role configures Fail2Ban defaults.

## Features
- Install fail2ban.
- Enable and start fail2ban.
- Deploy fail2ban config.
- Restart fail2ban.

## Configuration
This role does not define user-facing defaults in `defaults/main.yml`.

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.fail2ban
```
