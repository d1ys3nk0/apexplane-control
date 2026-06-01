# docker_swarm_zitadel

This role deploys ZITADEL as a Docker Swarm service and can provision PostgreSQL resources.

## Features
- Deploy Zitadel swarm service from Docker Swarm manager.
- Configure Zitadel PostgreSQL resources.
- Ensure Zitadel swarm service is started.
- Create Zitadel user.
- Create Zitadel database.

## Configuration
Set these required inputs before applying the role: `docker_swarm_zitadel_domain`, `docker_swarm_zitadel_masterkey`, `docker_swarm_zitadel_pg_base`, `docker_swarm_zitadel_pg_user`, `docker_swarm_zitadel_pg_pass`, `docker_swarm_zitadel_pg_host`.

| Variable | Default |
| --- | --- |
| `docker_swarm_zitadel_enabled` | `true` |
| `docker_swarm_zitadel_service_name` | `zitadel` |
| `docker_swarm_zitadel_domain` | `~` |
| `docker_swarm_zitadel_http_listen_port` | `8080` |
| `docker_swarm_zitadel_http_public_port` | `18080` |
| `docker_swarm_zitadel_image_name` | `ghcr.io/zitadel/zitadel` |
| `docker_swarm_zitadel_image_tag` | `v4.15.0` |
| `docker_swarm_zitadel_image_full` | `<derived>` |
| `docker_swarm_zitadel_masterkey` | `~` |
| `docker_swarm_zitadel_mem_res` | `500M` |
| `docker_swarm_zitadel_mem_lim` | `750M` |
| `docker_swarm_zitadel_pg_admin_pass` | `''` |
| `docker_swarm_zitadel_pg_admin_user` | `''` |
| `docker_swarm_zitadel_pg_base` | `~` |
| `docker_swarm_zitadel_pg_user` | `~` |
| `docker_swarm_zitadel_pg_pass` | `~` |
| `docker_swarm_zitadel_pg_host` | `~` |
| `docker_swarm_zitadel_pg_port` | `5432` |
| `docker_swarm_zitadel_pg_ssl` | `disable` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.docker_swarm_zitadel
      vars:
        docker_swarm_zitadel_domain: <value>
        docker_swarm_zitadel_masterkey: <value>
        docker_swarm_zitadel_pg_base: <value>
        docker_swarm_zitadel_pg_user: <value>
        docker_swarm_zitadel_pg_pass: <value>
        docker_swarm_zitadel_pg_host: <value>
```

## Operations
The `docker_swarm_zitadel` role manages only the long-running Docker Swarm runtime service. It expects the configured PostgreSQL database to already be initialized and set up before the service starts.

For a new empty database, run ZITADEL initialization manually from a Swarm manager before applying the runtime service. If the PostgreSQL role inputs already provisioned the database and service user, bootstrap the ZITADEL schemas with the service credentials:

```sh
docker run --rm \
  -e ZITADEL_DATABASE_POSTGRES_HOST='<postgres-host>' \
  -e ZITADEL_DATABASE_POSTGRES_PORT='<postgres-port>' \
  -e ZITADEL_DATABASE_POSTGRES_DATABASE='<postgres-database>' \
  -e ZITADEL_DATABASE_POSTGRES_USER_USERNAME='<postgres-user>' \
  -e ZITADEL_DATABASE_POSTGRES_USER_PASSWORD='<postgres-password>' \
  -e ZITADEL_DATABASE_POSTGRES_USER_SSL_MODE='<postgres-ssl-mode>' \
  ghcr.io/zitadel/zitadel:<zitadel-version> \
  init schema
```

Then run setup once before the first runtime start. Run setup again before deploying a new ZITADEL version:

```sh
docker run --rm \
  -e ZITADEL_DATABASE_POSTGRES_HOST='<postgres-host>' \
  -e ZITADEL_DATABASE_POSTGRES_PORT='<postgres-port>' \
  -e ZITADEL_DATABASE_POSTGRES_DATABASE='<postgres-database>' \
  -e ZITADEL_DATABASE_POSTGRES_USER_USERNAME='<postgres-user>' \
  -e ZITADEL_DATABASE_POSTGRES_USER_PASSWORD='<postgres-password>' \
  -e ZITADEL_DATABASE_POSTGRES_USER_SSL_MODE='<postgres-ssl-mode>' \
  -e ZITADEL_EXTERNALDOMAIN='<external-domain>' \
  -e ZITADEL_EXTERNALPORT='443' \
  -e ZITADEL_EXTERNALSECURE='true' \
  -e ZITADEL_TLS_ENABLED='false' \
  -e ZITADEL_FIRSTINSTANCE_ORG_NAME='<org-name>' \
  -e ZITADEL_FIRSTINSTANCE_ORG_HUMAN_USERNAME='<admin-email>' \
  -e ZITADEL_FIRSTINSTANCE_ORG_HUMAN_PASSWORD='<admin-password>' \
  -e ZITADEL_FIRSTINSTANCE_ORG_HUMAN_PASSWORDCHANGEREQUIRED='false' \
  ghcr.io/zitadel/zitadel:<zitadel-version> \
  setup --masterkey '<masterkey>' --init-projections=true
```

Do not add `init`, `setup`, or `start-from-init` to the Swarm service. The runtime service uses `start` so it fails fast when the database is not ready instead of silently performing bootstrap work during normal deploys.
