ARG POSTGRES_IMAGE
FROM ${POSTGRES_IMAGE}

RUN apt-get update && apt-get install -y --no-install-recommends \
    brotli \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

ARG WALG_BINARY_URL
RUN set -ex \
    && curl -fsSL "${WALG_BINARY_URL}" -o /usr/local/bin/wal-g \
    && chmod +x /usr/local/bin/wal-g

ENV WALG_COMPRESSION_METHOD=brotli
ENV AWS_S3_FORCE_PATH_STYLE=true
