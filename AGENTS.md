# Agent Instructions

This repository contains reusable Ansible roles shared by infrastructure playbook repositories.

## Before Acting

- Keep work inside this repository unless the user explicitly asks otherwise.
- Treat role defaults, tasks, templates, tests, and local checks as the source of truth for shared role behavior.
- Do not introduce secrets into docs, examples, tasks, logs, or tests.
- Keep this repository project-agnostic: do not mention, reference, depend on, or encode knowledge of specific consuming projects in docs, variables, defaults, tasks, templates, scripts, tests, examples, comments, or other tracked files.
- Do not mention real consuming project names in shared roles, shared docs, tests, fixtures, examples, comments, or local automation. Use generic consumers, synthetic names, or role-specific terminology instead.
- Do not add committed allowlists, denylists, fixtures, or tests that encode consuming project names for enforcement; use generic contracts and explicit review/search verification instead.

## Change Rules

- Keep roles focused on the desired state they enforce.
- Design roles with low coupling and SOLID-style boundaries: each role must own one cohesive responsibility, expose explicit role-prefixed inputs, depend on other roles only through documented external contracts, and keep optional integrations opt-in instead of assuming another role is present.
- When editing any file, proactively fix clear, low-risk inconsistencies and obviously suboptimal behavior in that same file, including outdated names or references, stale comments, type or validation drift, obsolete wording, local convention mismatches, and tests that make refactoring harder by pinning internals or configurable values. Do this without asking when the fix stays within the touched file or directly affected tests and does not change public behavior, role contracts, data, architecture, or operational meaning; summarize the extra fixes in the final response.
- Do not put repository-history cleanup in shared roles. Historical removals and migrations belong in consuming project migration playbooks named `playbooks/<cluster>/_YYMMDDHHMMSS_slug.yml`.
- Actively remove outdated or deprecated code, variables, aliases, docs, tests, and behavior encountered during work when removal is safe.
- Do not add or keep backward-compatibility shims, fallback-to-old-contract logic, deprecated variable aliases, legacy role/tag/task/file aliases, or compatibility mappings for renamed config keys. Hard cuts are the default: rename or remove the old contract directly, update all references in the same change, and put old deployed-state cleanup in consuming project migrations.
- If a hard cut may be unsafe, pause and ask whether to proceed with hard-cut removal plus consuming project migrations or add explicitly temporary backward compatibility.
- Operational DR/failover fallback behavior is allowed only when it represents desired infrastructure behavior, not compatibility with an old contract.
- Define user-provided role inputs in the role's `defaults/main.yml`; define dynamic or derived role variables in `vars/main.yml`. (See `test_repository_role_variable_contracts_pass` in `tests/static/test_ansible_role_variable_contracts.py`.)
- Put reusable or complex task conditions in dynamic role variables under `vars/main.yml`, then reference those variables directly from `when:` clauses.
- Name task files included directly from a role's `tasks/main.yml` as `setup*.yml` for setup, `verify.yml` for post-setup health/readiness checks, and `validate.yml` for input validation.
- Prefer single-line YAML scalar values when the resulting line is at most 120 characters, especially for short Jinja expressions and validation messages.
- Give required variables `~` defaults and validate them in `tasks/validate.yml`. (See `test_repository_role_variable_contracts_pass` in `tests/static/test_ansible_role_variable_contracts.py`.)
- Use `no_log: '{{ <role_name>_nolog }}'` for sensitive values, with `<role_name>_nolog` defined from `<role_name>_ci_mode` and `<role_name>_debug_mode`. Define those dynamic mode variables in `vars/main.yml` from the `CI` and `DEBUG` environment variables.
- Prefer Ansible modules and collection plugins over `ansible.builtin.command` or `ansible.builtin.shell` when a suitable module exists.
- After starting or restarting a systemd service, verify it with `systemctl is-active <unit>` in a non-changing task so crashes, restart-limit failures, and port conflicts fail fast.
- After starting a long-running Docker container, verify it with `community.docker.docker_container_info` and require `State.Running`. If the container exposes or listens on a known port, also wait for that port before continuing.
- For Docker-managed resource names in shared roles, prefer hyphens over underscores by default, including volumes, networks, containers, and similar named resources.
- Name roles that create Docker Swarm services with the `docker_swarm_` prefix. Name roles that start standalone Docker containers with the `docker_` prefix.
- Docker Swarm services should use `node.hostname` placement constraints only when the service depends on host bind mounts such as host directories, files, or sockets.
- Role tasks, templates, and handlers must not reference `gv_`, `iv_`, or `vv_` variables directly; map those values through role-prefixed defaults. (See `test_repository_role_variable_contracts_pass` in `tests/static/test_ansible_role_variable_contracts.py`.)
- Playbook repository variables in `variables/**` must start with `_`, `gv_`, `iv_`, `vv_`, `ansible_`, or an existing role prefix. Keep this contract in `tests/static/test_ansible_variable_scopes.py`.
- Tests must prevent bugs and make refactoring easy: they should fail only when final desired behavior, a documented public contract, schema validation, or rendered output is broken.
- Do not add or keep tests that assert current configurable values from role inputs, defaults, inventories, or consuming project variables, including domains, routes, hosts, certificate names, ports, usernames, database names, endpoints, feature toggles, thresholds, and timeouts. Invalid config should be rejected by explicit role validation or runtime checks, not by tests that cement today’s settings.
- Do not add or keep tests that pin private implementation details such as task names, task order, helper variable names, source filenames, template filenames, script filenames, or internal helper function layout unless that detail is explicitly documented as a public contract.

## Checks

- Use repository wrappers instead of one-off commands.
- Always run `task check` after any repository change, including documentation-only changes, before handing off.
- Do not hand off with failing tests, lint errors, or unresolved warnings. Resolve all check failures and warnings first; if a warning cannot be resolved, stop and explain the blocker instead of treating the task as done.
- Keep automated convention checks in `tests/static/`. Each `test_*` function must enforce a convention documented in `docs/development/conventions.md` and must be referenced from that document. (See `test_repository_role_variable_contracts_pass` in `tests/static/test_ansible_role_variable_contracts.py`.)
- Do not add Python pytest coverage for role behavior, rendered templates, shell scripts, or workflow regressions. Enforce role behavior through validation tasks where practical; use future Molecule coverage for Ansible role testing.
- When a convention or pattern should persist, assess whether it can be governed by a simple pytest check. If yes, add the pytest check automatically without asking, keep it focused on observable behavior or documented contracts rather than incidental implementation structure, and update `docs/development/conventions.md` in the same change.
