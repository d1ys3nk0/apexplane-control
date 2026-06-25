# Ansible Conventions

## ApexPlane Control

- ApexPlane Control is consumed as the `apexplane.control` collection from generated `requirements.yml`.
- Use the Git-backed `requirements.sample.yml` entry for normal work:

  ```yaml
  ---

  collections:
    - name: https://github.com/d1ys3nk0/apexplane-control.git
      type: git
      version: main
  ```

- For local Control framework debugging, generate `requirements.yml` with an `APEXPLANE_CONTROL_PATH` value that points at the local checkout:

  ```yaml
  ---

  collections:
    - name: /path/to/apexplane-control
      type: dir
  ```

  This installs the current local checkout, including uncommitted framework changes, into the consumer repository collection path. Consumer wrappers should create local `requirements.yml` only when it does not already exist, so a selected source is preserved until the file is removed.
- Keep project-specific values in `variables/**`.
- Keep reusable role behavior in `apexplane-control`.
- Put repository-history removals, migrations, and legacy cleanup in timestamped project migration playbooks named `playbooks/<cluster>/_YYMMDDHHMMSS_slug.yml`.
- When a change implies cleanup of previous role behavior, add a new migration playbook for each affected cluster. Do not edit an already-applied migration except to fix a broken, unreleased change.
- Keep setup/update playbooks focused on desired state; run `task apc:migrate -- apply` before `task apc:run --` when pending migrations should be previewed or applied.
- Use `*_cleanup_mode` only for pruning unmanaged non-data state. Use `*_fresh_mode` for deleting or overwriting role-owned files, folders, or generated config that will be recreated in the same run.
- Prefer Ansible modules and collection plugins over `ansible.builtin.command` or `ansible.builtin.shell` when a suitable module exists.

## Task Layout

Prefer these role task files when relevant:

- `main.yml`: entrypoint.
- `validate.yml`: the single role task file for configuration and user-input validation.
- `setup_*.yml`: setup task files included directly from `tasks/main.yml`, for example `setup_install.yml`, `setup_config.yml`, or `setup_postgresql.yml`; feature domain entrypoints use `<domain>.yml`, for example `postgres.yml` or `docker.yml`, and focused subdomain files use `<domain>_<subdomain>.yml` when included by that domain entrypoint, for example `docker_secrets.yml`.

## Variables

- Roles must not depend directly on unprefixed global variables from `variables`.
- Define role-prefixed variables, then map global values into them where needed.
- Define user-provided role inputs in the role's `defaults/main.yml`.
- Define dynamic or derived role variables in `vars/main.yml`; keep `defaults/main.yml` limited to values expected to be passed by a caller.
- Derive deterministic lists, maps, and other dynamic values in `vars/main.yml` when task files need the value more than once; avoid repeated task-side `set_fact` accumulation for the same derived value.
- Put reusable or complex task conditions in dynamic role variables under `vars/main.yml`, then reference those variables directly from `when:` clauses.
- For grouped optional feature inputs, derive both `<feature>_requested` and `<feature>_enabled` in `vars/main.yml`: requested means any grouped input is set, enabled means every required grouped input is set. Validate that the booleans are equal in `tasks/validate.yml`, and gate feature tasks/templates on `<feature>_enabled`.
- Give required variables `~` defaults and validate them in `tasks/validate.yml`.
- Use `vv_` only for vault variables in `variables/**/_vault.yml`.
- Use `gv_` for shared global variables in `variables/**/_global.yml`.
- Use neutral `gv_*` names for project global variables. Consuming Ansible repositories should manage one app or system, so redundant app namespaces after `gv_` are not needed.
- Use `iv_` for custom inventory metadata in `inventories/**`; map it to `gv_` aliases in `variables/_global.yml` when roles need global-style access.
- Variables in `variables/**` must start with `_`, `gv_`, `iv_`, `vv_`, `ansible_`, or an existing role prefix. Use `_` for private helper variables.
- Every variables file except `_global.yml` and `_vault.yml` should use this top-level section order: private `_` helper variables, `# Ansible`, then `# Role: <role_name>` groups.
- A `gv_` variable may be used for values with one or more real references outside the definition line.
- For standard shared-role ports, use the numeric port directly and add an inline service comment when helpful.
- For non-standard project ports that intentionally override role defaults, define a `gv_*_port` variable and map it into the relevant role variable.
- `cluster_name`, `cluster_realm`, and `target_hosts` are wrapper-provided runtime variables and are allowed as explicit exceptions.
- When a role needs cluster identity metadata, name the role inputs `<role_name>_cluster_name`, `<role_name>_cluster_realm`, and `<role_name>_cluster_platform`.
- Add a `# Role: <role_name>` comment before each role variable group.
- Use `~` instead of `null` and empty strings for empty YAML values.

## Security

- Use `no_log: '{{ <role_name>_nolog }}'` for sensitive values, with `<role_name>_nolog` defined from `<role_name>_ci_mode` and `<role_name>_debug_mode`.
- Define dynamic `<role_name>_ci_mode`, `<role_name>_debug_mode`, and `<role_name>_nolog` variables in `vars/main.yml`; derive the mode variables from the `CI` and `DEBUG` environment variables.
- Do not commit real passwords, tokens, access keys, or private keys into docs, examples, tasks, logs, or tests.

## YAML Style

- YAML files start with `---` followed by a blank line.
- Use 2-space indentation.
- Quote file modes as strings, for example `'0644'`.
- Quote Jinja values in YAML scalars, for example `'{{ var }}'`.
- Keep task names imperative and specific.
