# Contributing

Run the local checks before opening a change:

```sh
uv run pre-commit run --hook-stage pre-commit --all-files
uv run pytest tests/static tests/unit
uv run ansible-galaxy collection build
```

Keep roles project-agnostic. Consumer-specific naming, topology, secrets, inventories, and migration history belong in the consuming playbook repository.
