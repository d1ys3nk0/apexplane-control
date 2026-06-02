# Migration Playbooks

Migration playbooks handle one-time repository-history cleanup for consuming infrastructure repositories. They are similar to application database migrations: each host records the successful migration timestamps and skips any migration whose timestamp is already in the host state.

## Naming

- Put migrations under `playbooks/<cluster>/`.
- Name files `_YYMMDDHHMMSS_slug.yml`, for example `_260513184216_base_packages.yml`.
- Keep the timestamp unique and monotonically increasing within the cluster.
- Use a short lowercase slug with underscores.
- Add a new migration for new cleanup behavior; do not edit already-applied migrations except to fix a broken, unreleased change.

## Execution

- `task apc:migrate -- apply [realm] [platform] [cluster]` previews pending migrations in dry/check mode. Omitted target arguments are treated as `all`.
- `DRY=0 task apc:migrate -- apply [realm] [platform] [cluster]` applies pending migrations before the target playbook is run separately with `task apc:run --`.
- `task apc:migrate --` stores per-host state on the remote host under `/var/lib/ansible-*/state.json`.
- Remote state uses `migrate_tags` as the authoritative list of applied migration timestamps. The `migrate_tag` value is kept only as a latest-timestamp summary for operator readability and legacy conversion.
- Migration runs append changed-line entries to `log/<realm>-<cluster>-migrate.log` only when the run contains changed results; full Ansible run logs are temporary and timestamped changed-log files are not created.
- Missing host state means no migrations have been applied, so all migrations for that cluster are pending for that host.
- If a host has legacy state with only `migrate_tag`, migrations with timestamps less than or equal to that value are treated as applied. During the next non-dry migration run, the wrapper materializes those selected migration timestamps into `migrate_tags`.
- Migrations update remote state only when `DRY=0` or `DRY=false` is set and the migration playbook succeeds. Dry/check mode never writes migration state.
- `T=<tags>` belongs to `task apc:run --`; migration playbooks always run all their tasks.

## Cleanup

- `task apc:migrate -- clean [realm] [platform] [cluster]` removes migration files whose selected-scope hosts all have the exact migration timestamp recorded in `migrate_tags`.
- Omitted cleanup target arguments are treated as `all`; scoped cleanup may remove a cluster migration file once the selected scope has applied it.
- Hosts with legacy `migrate_tag`-only state are treated as having applied migration timestamps less than or equal to that value until a non-dry migration run materializes `migrate_tags`.
- Missing or incomplete selected-scope state keeps the migration file in place.

## Modes

- Use migrations for obsolete conffiles, renamed files, deprecated directories, and other one-time state left by old role behavior.
- Do not put repository-history cleanup into shared roles unless the cleanup is genuinely reusable desired state.
- Destructive or sensitive cleanup must fail before changing state when `INTERACTIVE=0` or `INTERACTIVE=false`.
