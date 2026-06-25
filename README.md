# ApexPlane Control

ApexPlane Control is an Ansible-based IaC management framework with reusable roles and shared operational tooling for Linux infrastructure.

## Install

Install the collection from Git. This is the default mode for consuming repositories and uses committed code from the configured ref:

```sh
ansible-galaxy collection install git+https://github.com/d1ys3nk0/apexplane-control.git,v1.0.0
```

Or add it to a consumer repository `requirements.sample.yml`:

```yaml
---

collections:
  - name: https://github.com/d1ys3nk0/apexplane-control.git
    type: git
    version: v1.0.0
```

For local Control framework debugging, generate the consumer repository's local `requirements.yml` from a local checkout instead of Git:

```yaml
---

collections:
  - name: /path/to/apexplane-control
    type: dir
```

This lets `ansible-galaxy collection install -r requirements.yml` copy the current checkout, including uncommitted changes, into the consumer repository's installed collection path. Consumer wrappers should create local `requirements.yml` only when it does not already exist, so a selected source is preserved until the file is removed.

Use roles by fully qualified collection name:

```yaml
---

- name: Configure hosts
  hosts: all
  roles:
    - role: apexplane.control.base_bootstrap
    - role: apexplane.control.base_packages
```

## Checks

```sh
task check
uv run pytest tests/static
uv run ansible-lint roles
uv run ansible-galaxy collection build
```

## Layout

- `docs/`: framework, role authoring, shared consumer docs, and contract documentation.
- `docs/development/conventions.md`: convention source of truth for static pytest checks.
- `docs/shared/`: canonical shared docs linked by consumer repositories from GitHub.
- `roles/`: Ansible collection roles.
- `tests/static/`: convention checks referenced from `docs/development/conventions.md`. (See `test_repository_role_variable_contracts_pass` in `tests/static/test_ansible_role_variable_contracts.py`.)

## Role Authoring

See [docs/role-contracts.md](docs/role-contracts.md) for role input rules, including optional feature gating.

See [docs/port-conventions.md](docs/port-conventions.md) for role port defaults and observability port conventions.
