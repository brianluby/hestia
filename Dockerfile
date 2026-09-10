# syntax=docker/dockerfile:1
# Canonical Hestia image/build path: one Dockerfile, named stages.
#   docker build --target base .            minimal OS utilities + mise (61Q7E8F)
#   docker build --target fixture-tools .   base + fixture mise toolchain (WGHQ2GW)
#   docker build --target agent .           fixture-tools + the omp agent (XJVWF4K)
# `docker build .` builds the last stage (agent).
#
# Pinned inputs (verified 2026-09-09; evidence in docs/evidence.md):
#   base  debian:bookworm-slim, pinned by OCI index digest
#         sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171
#         (linux/arm64 manifest sha256:6bd27d44e6c32a66bbd72d7cb2b76a8ae3497ec2e5274a81abd1b37f6013fa1f)
#   mise  v2026.9.4 linux-arm64 tarball; sha256 below is the GitHub release-API
#         asset digest (no standalone checksum assets are published), AND the
#         tarball is verified against its SLSA v1 provenance (A5H3NY9 decision):
#         the provenance is fetched at build time from GitHub's public
#         attestations API keyed by that digest and verified with cosign,
#         pinning the signing identity to jdx/mise workflows via the GitHub
#         Actions OIDC issuer. cosign itself is pinned by its release-API
#         digest — the documented root anchor of this chain.
#
# Targets linux/arm64 (the available Apple Silicon host) and enforces the
# platform on the base pull, so a non-ARM builder fails clearly instead of
# resolving the multi-arch index to a foreign rootfs around the arm64 mise
# tarball; no multi-arch support is claimed. By construction the images
# contain no GUI, no agent supervisor, no host sockets and no credentials.
# Startup installs nothing; toolchains are declared image layers built
# explicitly.
FROM --platform=linux/arm64 debian:bookworm-slim@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171 AS base

ARG MISE_VERSION=v2026.9.4
ARG MISE_SHA256=18303fdb59095acf0c50b0d23819b87182516988f9eb2ec016b52f8814916904
ARG COSIGN_VERSION=v3.1.3
ARG COSIGN_SHA256=c5d324e091826b0d7a78eb16fef316450b4eb9aaec045611c08ba06f5e73220a

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      jq \
      xz-utils \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --create-home --uid 1000 --shell /bin/bash dev


# Verification chain (A5H3NY9 decision: SLSA): both binaries are pinned by
# their release-API digests; the mise tarball must additionally carry a valid
# SLSA v1 provenance from jdx/mise's release workflow (identity pinned to
# https://github.com/jdx/mise/.github/workflows/ via the GitHub Actions OIDC
# issuer), fetched anonymously from GitHub's attestations API keyed by the
# pinned digest. The provenance binds the artifact to the workflow that built
# it; the pinned digests bind which artifact and verifier this is. The version
# check then asserts the installed binary matches the pinned release, and any
# state mise created under /root in this layer is removed; MISE_DATA_DIR below
# intentionally applies only to later, dev-user layers.
RUN curl -sfL -o /tmp/mise.tar.gz \
      "https://github.com/jdx/mise/releases/download/${MISE_VERSION}/mise-${MISE_VERSION}-linux-arm64.tar.gz" \
 && curl -sfL -o /tmp/cosign \
      "https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-linux-arm64" \
 && echo "${MISE_SHA256}  /tmp/mise.tar.gz" | sha256sum --strict --check - \
 && echo "${COSIGN_SHA256}  /tmp/cosign" | sha256sum --strict --check - \
 && chmod +x /tmp/cosign \
 && curl -sfL "https://api.github.com/repos/jdx/mise/attestations/sha256:${MISE_SHA256}" \
      | jq '.attestations[].bundle | (if type == "string" then fromjson else . end) \
          | select((.dsseEnvelope.payload | @base64d | fromjson | .predicateType) == "https://slsa.dev/provenance/v1")' \
          > /tmp/mise-provenance.json \
 && test -s /tmp/mise-provenance.json \
 && /tmp/cosign verify-blob-attestation \
      --bundle /tmp/mise-provenance.json \
      --type "https://slsa.dev/provenance/v1" \
      --certificate-identity-regexp '^https://github\.com/jdx/mise/\.github/workflows/' \
      --certificate-oidc-issuer https://token.actions.githubusercontent.com \
      /tmp/mise.tar.gz \
 && tar -xzf /tmp/mise.tar.gz -C /tmp \
 && install -m 0755 /tmp/mise/bin/mise /usr/local/bin/mise \
 && rm -rf /tmp/mise /tmp/mise.tar.gz /tmp/cosign /tmp/mise-provenance.json \
 && mise --version | grep -qF "${MISE_VERSION#v} " \
 && rm -rf /root/.config/mise /root/.local/share/mise

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
# The fixture build/test runs here as the toolchain check; its source AND its
# build/test caches are removed in the same layer, so neither ships in the
# image (the check's GOCACHE/GOMODCACHE point at a throwaway directory rather
# than the dev home the runtime uses). GOTOOLCHAIN=local is the explicit
# no-download policy for Go: a mounted workspace whose go.mod declares a newer
# go/toolchain directive fails clearly instead of silently downloading and
# executing a different toolchain at runtime.
FROM base AS fixture-tools

ENV MISE_PARANOID=1 \
    GOTOOLCHAIN=local

# Workspace cache root (KSCDG1J): the disposable Linux build/dependency cache
# volume mounts here. Creating it dev-owned in the image means a fresh volume
# initializes with ownership the non-root runtime user can write to.
USER root
RUN mkdir -p /hestia/cache && chown dev:dev /hestia/cache
USER dev

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
 && env GOCACHE=/tmp/hestia-build-cache/build GOMODCACHE=/tmp/hestia-build-cache/mod \
    mise exec -- go build ./... \
 && env GOCACHE=/tmp/hestia-build-cache/build GOMODCACHE=/tmp/hestia-build-cache/mod \
    mise exec -- go test ./... \
 && cd / \
 && rm -rf /tmp/fixture-src /tmp/hestia-build-cache

# XJVWF4K — optional agent layer: omp (oh-my-pi, TG7VZBV decision; AWS Bedrock
# only this phase). Installed through mise like every other declared tool and
# verified against the pinned release-API digest of omp-linux-arm64; the
# binary must report the pinned version. The provider restriction
# (agent/omp/config.yml: everything except bedrock disabled) ships root-owned
# at /opt/hestia/omp — workspace policy, not runtime-user preference (FA5H9TR).
# The generated Compose file loads it via PI_CONFIG_FILES: omp merges config
# overlays after the user's own config and fails to start when a configured
# overlay is missing, so the policy wins every merge and is fail-closed. The
# file lives outside ~/.omp precisely so the writable state mount never hides
# it and omp's settings writes (atomic tmp+rename onto ~/.omp/agent/config.yml)
# never touch it — binding it read-only into the state tree made every such
# rename fail with EBUSY. No credentials enter the image: bedrock
# authenticates through the standard AWS credential chain supplied at runtime.
# omp's durable state (~/.omp: sessions, resumable via --resume, settings,
# project-scoped memory) is bind-mounted from the workspace's state directory
# by the generated Compose file, never baked.
FROM fixture-tools AS agent

ARG OMP_VERSION=v18.1.16
ARG OMP_SHA256=d8612389c7af3cf3b69609c9149bff3cf07dcb65774b231d9dc4966b176b9720

USER root
# ~/.omp (and agent/, where omp keeps its agent.db database) must be
# dev-writable: omp extracts its pi_natives addon into ~/.omp/natives, opens
# ~/.omp/agent/agent.db at startup, and persists settings there. The policy
# config is copied as root into a root-owned directory, so the runtime user
# can neither edit nor replace it and no read-only bind is required.
RUN printf '"github:can1357/oh-my-pi" = "%s"\n' "${OMP_VERSION#v}" >>/home/dev/.config/mise/config.toml \
 && mkdir -p /opt/hestia/omp /home/dev/.omp/agent \
 && chown dev:dev /home/dev/.omp /home/dev/.omp/agent
COPY agent/omp/config.yml /opt/hestia/omp/config.yml
USER dev
RUN mise install --yes \
 && omp_bin="$(mise where github:can1357/oh-my-pi)/omp" \
 && test -x "$omp_bin" \
 && omp --version | grep -qF "${OMP_VERSION#v}" \
 && echo "${OMP_SHA256}  $omp_bin" | sha256sum --strict --check -
RUN omp --version && echo "agent layer ok"
