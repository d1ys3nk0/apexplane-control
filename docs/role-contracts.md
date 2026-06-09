# Shared Role Contracts

Shared roles must be reusable across playbook repositories with different realm, cluster, and environment names. A role may expose metadata variables for labels, rendered names, or validation, but it must not decide behavior by comparing those variables to literals such as `prd`, `stg`, `dev`, `app`, `dbs`, or `bal`.

Optional behavior must be controlled by explicit role inputs:

- use boolean flags or explicit values for optional behavior, for example `base_bootstrap_mtu` or `docker_swarm_pghero_enabled`;
- use non-empty credentials or endpoint variables for integrations that only make sense when configured, for example S3/WAL-G;
- for grouped optional feature inputs, derive `<feature>_requested` from any populated grouped input and `<feature>_enabled` from all required grouped inputs, validate that those booleans are equal, and gate behavior on `<feature>_enabled`;
- build realm-specific names in the consumer repository and pass the final value to the role when the role exposes them; do not expose configurable prefix inputs when a role owns a fixed storage key layout.

For storage-backed features, the role should run only when the explicit feature contract is selected and the complete role-owned storage contract is populated. For example, `docker_postgres` runs `docker_postgres_image_name` with `docker_postgres_image_tag` by default via derived `docker_postgres_image_full`, and builds and uses a `<docker_postgres_image_name>-walg:<docker_postgres_image_tag>` image only when `docker_postgres_walg_binary_url` is set; WAL-G backup configuration requires `docker_postgres_walg_backup_hostnames` plus non-empty `docker_postgres_walg_backup_path`, with matching S3 settings only when the path is S3-backed, while recovery uses the separate `docker_postgres_walg_recover_path` and `docker_postgres_walg_recover_s3_*` contract.

Consumer repositories own environment policy. They may map their local `cluster_name`, `cluster_realm`, inventory role, or other naming conventions to generic role inputs, but that mapping belongs outside this collection. When a role needs cluster identity metadata, name the inputs `<role_name>_cluster_name`, `<role_name>_cluster_realm`, and `<role_name>_cluster_platform`.
