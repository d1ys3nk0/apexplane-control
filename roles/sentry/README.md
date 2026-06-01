# sentry

This role contains Sentry role defaults and entrypoint tasks.

## Features
- Provides the role entrypoint for reusable Ansible desired state.

## Configuration
This role does not define user-facing defaults in `defaults/main.yml`.

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.sentry
```
