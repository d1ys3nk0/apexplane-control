# Development Conventions

## Automated

- Target repositories must follow ApexPlane Control structure, requirements, inventory, global-variable, role-override, and YAML scalar conventions; checked by `tests/static/test_toolkit_repo_sync.py::test_shared_conventions_report_consumer_repository_failures`, `tests/static/test_toolkit_repo_sync.py::test_role_variable_overrides_must_match_role_defaults`, `toolkit/tests/static/test_role_variable_overrides.py::test_target_role_variable_overrides_match_apc_role_defaults`.

## Manual

- Review target repository exceptions manually and keep project-specific conventions in the target repository's local `docs/development/conventions.md`.
