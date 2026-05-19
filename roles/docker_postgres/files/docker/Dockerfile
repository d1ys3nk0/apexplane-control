ARG POSTGRES_IMAGE
FROM ${POSTGRES_IMAGE}

RUN apt-get update && apt-get install -y --no-install-recommends \
    brotli \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

ARG WALG_VERSION
RUN set -ex \
    && curl -fsSL "https://github.com/wal-g/wal-g/releases/download/v${WALG_VERSION}/wal-g-pg-ubuntu-24.04-$(dpkg --print-architecture).tar.gz" \
    | tar xzf - -C /usr/local/bin/ \
    && mv /usr/local/bin/wal-g-pg-ubuntu-24.04-$(dpkg --print-architecture) /usr/local/bin/wal-g \
    && chmod +x /usr/local/bin/wal-g

ENV WALG_COMPRESSION_METHOD=brotli
ENV AWS_S3_FORCE_PATH_STYLE=true
