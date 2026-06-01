# base_packages

This role configures package sources and installs baseline packages.

## Features
- Configure custom Ubuntu repository.
- Install essential packages.
- Install snap packages.

## Configuration
| Variable | Default |
| --- | --- |
| `base_packages_ubuntu_deb_repo` | `http://archive.ubuntu.com/ubuntu` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.base_packages
```
