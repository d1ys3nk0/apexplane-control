# base_swap

This role configures host swap.

## Features
- Calculate desired swap size.
- Calculate desired swap size in bytes.
- Inspect swap file.
- Inspect active swap devices.
- Calculate current swap state.
- Disable swap file before resizing.
- Remove incorrectly sized swap file.
- Create swap file.
- Inspect swap file signature.
- Configure swap file permissions.
- Additional focused setup tasks for the same role-owned desired state.

## Configuration
| Variable | Default |
| --- | --- |
| `base_swap_fstab_options` | `sw` |
| `base_swap_max_size_mb` | `4096` |
| `base_swap_path` | `/swapfile` |
| `base_swap_size_ratio` | `0.5` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.base_swap
```
