# MinIO Administration

## Shell

```sh
docker exec -it minio bash

mc alias list
mc alias set local http://127.0.0.1:9000 "<MINIO_ROOT_USER>" "<MINIO_ROOT_PASSWORD>"
mc admin user list local
```

## Create Bucket User

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
