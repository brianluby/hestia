# syntax=docker/dockerfile:1
# 61Q7E8F — canonical Hestia base image: minimal OS utilities + mise, non-root.
#
# Pinned inputs (verified 2026-09-09; evidence in docs/evidence.md):
#   base  debian:bookworm-slim, pinned by OCI index digest
#         sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171
#         (linux/arm64 manifest sha256:6bd27d44e6c32a66bbd72d7cb2b76a8ae3497ec2e5274a81abd1b37f6013fa1f)
#   mise  v2026.9.4 linux-arm64 tarball; sha256 below is the GitHub release-API
#         asset digest (no standalone checksum assets are published)
#
# Targets linux/arm64 (the available Apple Silicon host); no multi-arch support
# is claimed. By construction the base contains no GUI, no agent supervisor,
# no host sockets and no credentials. Startup installs nothing; toolchains are
# declared image layers built explicitly (see board ticket WGHQ2GW).
FROM debian:bookworm-slim@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171

ARG MISE_VERSION=v2026.9.4
ARG MISE_SHA256=18303fdb59095acf0c50b0d23819b87182516988f9eb2ec016b52f8814916904

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      xz-utils \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --create-home --uid 1000 --shell /bin/bash dev

ADD https://github.com/jdx/mise/releases/download/${MISE_VERSION}/mise-${MISE_VERSION}-linux-arm64.tar.gz /tmp/mise.tar.gz

RUN echo "${MISE_SHA256}  /tmp/mise.tar.gz" | sha256sum --strict --check - \
 && tar -xzf /tmp/mise.tar.gz -C /tmp \
 && install -m 0755 /tmp/mise/bin/mise /usr/local/bin/mise \
 && rm -rf /tmp/mise /tmp/mise.tar.gz \
 && mise --version

ENV MISE_DATA_DIR=/home/dev/.local/share/mise \
    PATH=/home/dev/.local/share/mise/shims:$PATH

USER dev
WORKDIR /home/dev
CMD ["/bin/bash"]
