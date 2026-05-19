# Contributing

Run the local checks before opening a change:

```sh
task check
uv run ansible-galaxy collection build
```

Keep roles project-agnostic. Consumer-specific naming, topology, secrets, inventories, and migration history belong in the consuming playbook repository.
