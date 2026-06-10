# Development Conventions

## Automated

- Target repositories must follow ApexPlane Control structure, requirements, inventory, global-variable, role-override, and YAML scalar conventions; checked by `tests/static/test_toolkit_repo_sync.py::test_role_variable_overrides_must_match_role_defaults`, `toolkit/tests/static/test_role_variable_overrides.py::test_target_role_variable_overrides_match_apc_role_defaults`.

## Manual

- Do not add or keep tests that assert a specific file contains a specific literal string. Prefer tests of behavior, callable logic, structured schemas, rendered outputs, or broad static code-style and repository-shape conventions.
- Review target repository exceptions manually and keep project-specific conventions in the target repository's local `docs/development/conventions.md`.
