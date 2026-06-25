# docker_minio

This role runs MinIO in a standalone Docker container.

## Features
- Create MinIO directories.
- Install scripts.
- Start MinIO container.

## Configuration
Set these required inputs before applying the role: `docker_minio_root_pass`, `docker_minio_root_user`, `docker_minio_site_region`.

| Variable | Default |
| --- | --- |
| `docker_minio_ci_mode` | `<derived>` |
| `docker_minio_debug_mode` | `<derived>` |
| `docker_minio_nolog` | `<derived>` |
| `docker_minio_image_name` | `minio/minio` |
| `docker_minio_image_tag` | `<required>` |
| `docker_minio_image_full` | `<derived>` |
| `docker_minio_mem_res` | `1000M` |
| `docker_minio_mem_lim` | `1500M` |
| `docker_minio_mem_swp` | `2000M` |
| `docker_minio_root_pass` | `~` |
| `docker_minio_root_user` | `~` |
| `docker_minio_site_region` | `~` |
| `docker_minio_mc_alias` | `local` |
| `docker_minio_bucket_names` | `[]` |

## Usage
```yaml
---

- hosts: all
  roles:
    - role: apexplane.control.docker_minio
      vars:
        docker_minio_root_pass: <value>
        docker_minio_root_user: <value>
        docker_minio_site_region: <value>
```

## Operations
### Shell

```sh
docker exec -it minio bash

mc alias list
mc alias set local http://127.0.0.1:9000 "<MINIO_ROOT_USER>" "<MINIO_ROOT_PASSWORD>"
mc admin user list local
```

### Create Bucket User

```sh
export MINIO_BUCKET="<BUCKET>"
export MINIO_USER="<MINIO_USER>"
export MINIO_PASS="<MINIO_PASSWORD>"

mc mb "local/${MINIO_BUCKET}"
mc admin user add local "${MINIO_USER}" "${MINIO_PASS}"
```

Create a read/write bucket policy:

```sh
cat >"/tmp/${MINIO_BUCKET}-rw.json" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetBucketLocation", "s3:ListBucket"],
      "Resource": ["arn:aws:s3:::${MINIO_BUCKET}"]
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": ["arn:aws:s3:::${MINIO_BUCKET}/*"]
    }
  ]
}
JSON

mc admin policy create local "${MINIO_BUCKET}-rw" "/tmp/${MINIO_BUCKET}-rw.json"
mc admin policy attach local "${MINIO_BUCKET}-rw" --user "${MINIO_USER}"
```
