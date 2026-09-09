# syntax=docker/dockerfile:1
# Canonical Hestia image/build path: one Dockerfile, named stages.
#   docker build --target base .            minimal OS utilities + mise (61Q7E8F)
#   docker build --target fixture-tools .   base + fixture mise toolchain (WGHQ2GW)
# `docker build .` builds the last stage (fixture-tools).
#
# Pinned inputs (verified 2026-09-09; evidence in docs/evidence.md):
#   base  debian:bookworm-slim, pinned by OCI index digest
#         sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171
#         (linux/arm64 manifest sha256:6bd27d44e6c32a66bbd72d7cb2b76a8ae3497ec2e5274a81abd1b37f6013fa1f)
#   mise  v2026.9.4 linux-arm64 tarball; sha256 below is the GitHub release-API
#         asset digest (no standalone checksum assets are published)
#
# Targets linux/arm64 (the available Apple Silicon host); no multi-arch support
# is claimed. By construction the images contain no GUI, no agent supervisor,
# no host sockets and no credentials. Startup installs nothing; toolchains are
# declared image layers built explicitly.
FROM debian:bookworm-slim@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171 AS base

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

# WGHQ2GW — fixture toolchain layer: the synthetic fixture's declared mise
# tools, installed only during this explicit build step; startup installs or
# upgrades nothing. Tools live in this image layer, outside any persistent
# state mount. Only the COPYed build-context declaration above is part of the
# image's toolchain. MISE_PARANOID=1 makes runtime trust deliberate: mise's
# normal mode auto-trusts a project's active config (observed 2026-09-09 with
# mise 2026.9.4: an untrusted mounted mise.toml's task ran unchallenged), so
# workspaces default to paranoid mode, where every non-global config needs an
# explicit, content-bound `mise trust` before its tools/tasks/hooks apply.
# The fixture build/test runs here as the toolchain check; its source is
# removed in the same layer and never ships in the image.
FROM base AS fixture-tools

ENV MISE_PARANOID=1

# The global toolchain config stays root-owned: the runtime user reads it but
# cannot modify the image-declared toolchain. The check-out source below is
# chowned so the non-root build step can remove it again in the same layer.
COPY fixtures/synthetic/mise.toml /home/dev/.config/mise/config.toml
COPY --chown=dev:dev fixtures/synthetic/go.mod /tmp/fixture-src/
COPY --chown=dev:dev fixtures/synthetic/cmd /tmp/fixture-src/cmd
COPY --chown=dev:dev fixtures/synthetic/greet /tmp/fixture-src/greet

RUN mise install --yes \
 && mise exec -- go version \
 && cd /tmp/fixture-src \
 && mise exec -- go build ./... \
 && mise exec -- go test ./... \
 && cd / \
 && rm -rf /tmp/fixture-src
