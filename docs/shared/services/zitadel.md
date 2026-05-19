# ZITADEL

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
