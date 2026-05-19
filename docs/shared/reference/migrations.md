# Migration Playbooks

Migration playbooks handle one-time repository-history cleanup for consuming infrastructure repositories. They are similar to application database migrations: each host records the newest successful migration timestamp and skips older migrations on future runs.

## Naming

- Put migrations under `playbooks/<cluster>/`.
- Name files `_YYMMDDHHMMSS_slug.yml`, for example `_260513184216_base_packages.yml`.
- Keep the timestamp unique and monotonically increasing within the cluster.
- Use a short lowercase slug with underscores.
- Add a new migration for new cleanup behavior; do not edit already-applied migrations except to fix a broken, unreleased change.

## Execution

- `task apc:migrate -- apply [realm] [platform] [cluster]` previews pending migrations in dry/check mode. Omitted target arguments are treated as `all`.
- `DRY=0 task apc:migrate -- apply [realm] [platform] [cluster]` applies pending migrations before the target playbook is run separately with `task apc:run --`.
- `task apc:migrate --` stores per-host state in `tmp/cleanup.json` using `inventory_hostname` as the key and the latest successful migration timestamp as the value.
- Missing host state means no migrations have been applied, so all migrations for that cluster are pending for that host.
- Migrations update `tmp/cleanup.json` only when `DRY=0` or `DRY=false` is set and the migration playbook succeeds.
- `T=<tags>` belongs to `task apc:run --`; migration playbooks always run all their tasks.

## Cleanup

- `task apc:migrate -- clean [realm] [platform] [cluster]` removes migration files whose selected-scope hosts have all applied the migration timestamp.
- Omitted cleanup target arguments are treated as `all`; scoped cleanup may remove a cluster migration file once the selected scope has applied it.
- Missing or incomplete selected-scope state keeps the migration file in place.

## Modes

- Use migrations for obsolete conffiles, renamed files, deprecated directories, and other one-time state left by old role behavior.
- Do not put repository-history cleanup into shared roles unless the cleanup is genuinely reusable desired state.
- Destructive or sensitive cleanup must fail before changing state when `INTERACTIVE=0` or `INTERACTIVE=false`.
