# Shared Role Contracts

Shared roles must be reusable across playbook repositories with different inventories, variables, realms, platforms, and topology.

## Variables

- Every role input must use the role prefix, for example `docker_postgres_pg_port`.
- Required inputs get `~` defaults and validation in `tasks/validate.yml`.
- Role tasks, templates, and handlers must not reference consuming-repository `gv_`, `iv_`, or `vv_` variables directly.
- Optional topology policy must be passed as explicit booleans such as `<role_name>_enabled`; service roles must not expose consumer inventory enums such as `<role_name>_swarm_mode`.
- Grouped optional feature inputs must derive `<feature>_requested` and `<feature>_enabled` in `vars/main.yml`, validate that the booleans are equal in `tasks/validate.yml`, and gate feature behavior on `<feature>_enabled`.
- Sensitive inputs must be protected with `no_log: '{{ <role_name>_nolog }}'`.

## Side Effects

- Roles enforce reusable desired state only.
- Historical cleanup for a consuming repository belongs in timestamped project migrations.
- Roles that start or restart services must verify readiness immediately after the change.
- Docker roles must verify long-running containers are running and wait for known exposed ports where relevant.

## Compatibility

- Do not keep deprecated variable aliases, role aliases, task aliases, file aliases, compatibility maps, or fallback-to-old-contract logic.
- Break contract deliberately by renaming or removing the old contract, updating all references, and putting deployed-state cleanup in consuming project migrations.
