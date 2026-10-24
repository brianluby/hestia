# syntax=docker/dockerfile:1
# check=skip=FromPlatformFlagConstDisallowed
# Canonical Hestia image/build path: one Dockerfile, named stages.
#   docker build --target base .            minimal OS utilities + mise (61Q7E8F)
#   docker build --target fixture-tools .   base + fixture mise toolchain (WGHQ2GW)
#   docker build --target nono .            fixture-tools + the nono sandbox CLI
#   docker build --target pig .             nono + the PiG harness (V5VWGS9)
#   docker build --target pi .              nono + upstream Pi (opt-in)
#   docker build --target pi-bolt .         nono + Pi-Bolt (opt-in, experimental)
#   docker build --target claude-code .     nono + Claude Code (opt-in)
#   docker build --target agent .           nono + the omp agent (XJVWF4K)
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
# The base pull is pinned to linux/arm64 (the available Apple Silicon host)
# and enforces it, so a non-ARM builder fails clearly instead of resolving the
# multi-arch index to a foreign rootfs around the arm64-only mise and cosign
# downloads below; no multi-arch support is claimed. That constant is why this
# file skips buildx's FromPlatformFlagConstDisallowed check (line above):
# taking the base platform from a build argument is exactly what would let the
# base and those downloads disagree again. By construction the images contain
# no GUI, no agent supervisor, no host sockets and no credentials. Startup
# installs nothing; toolchains are declared image layers built explicitly.
#
# cosign is pinned once here, before the first FROM, because two stages (base
# for mise, nono for nono) verify provenance with it; each stage re-declares
# the names to read this one pin.
ARG COSIGN_VERSION=v3.1.3
ARG COSIGN_SHA256=c5d324e091826b0d7a78eb16fef316450b4eb9aaec045611c08ba06f5e73220a

FROM --platform=linux/arm64 debian:bookworm-slim@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171 AS base

ARG MISE_VERSION=v2026.9.4
ARG MISE_SHA256=18303fdb59095acf0c50b0d23819b87182516988f9eb2ec016b52f8814916904
ARG COSIGN_VERSION
ARG COSIGN_SHA256

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

# nono — kernel-enforced sandbox CLI (github.com/nolabs-ai/nono), shared by
# both agent stages below so either harness can be started under it
# (`nono run --allow <path>... -- <command>`; an agent also needs its own state
# and network allowed, and no such profile ships). It is a tool, not a wrapper: nothing here
# changes how omp or pig start, and nono applies no policy until invoked. On
# Linux it enforces through Landlock (plus seccomp for its network proxy) and
# refuses to start the command when Landlock is not enforced at all; Docker
# 29.5.2's default seccomp profile allows the landlock_* syscalls. Whether
# the macOS runtime's VM kernel (Colima in the recorded runs) enables Landlock
# is not yet observed: `nono setup --check-only` inside the workspace reports
# it.
#
# Same verification chain as mise: the pinned digest of the release tarball
# (cross-checked 2026-10-24 against upstream's SHA256SUMS.txt for v0.80.0)
# must carry a SLSA v1 provenance signed by nono's release.yml workflow, the
# one that builds the artifacts. The identity is pinned to that file rather
# than the whole workflows/ prefix because upstream's attest-release.yml can
# re-attest already-published downloads, which says nothing about how they
# were built. The attestations API may return several bundles for one digest,
# so each is tried and one from release.yml must verify. cosign is fetched
# again here and removed in the same layer, as in base.
#
# NONO_NO_UPDATE_CHECK=1 turns off nono's daily update.nono.sh request (it
# sends an anonymous install UUID): this binary is pinned, and updating it is
# an explicit rebuild, not a runtime prompt. nono's durable state (audit
# logs, sessions, rollback snapshots) lives under ~/.local/state/nono and is
# disposable container storage unless a workspace binds it with
# `--state nono:/home/dev/.local/state/nono`. That directory is created
# dev-owned here, as ~/.omp is below, so a bind there does not leave Docker to
# create its parents root-owned.
FROM fixture-tools AS nono

ARG NONO_VERSION=v0.80.0
ARG NONO_SHA256=d2a24c8c37714f85c829b5586ffd81fc2acf336c95372d881ba62140884f22cb
ARG COSIGN_VERSION
ARG COSIGN_SHA256

ENV NONO_NO_UPDATE_CHECK=1

USER root
RUN curl -sfL -o /tmp/nono.tar.gz \
      "https://github.com/nolabs-ai/nono/releases/download/${NONO_VERSION}/nono-${NONO_VERSION}-aarch64-unknown-linux-gnu.tar.gz" \
 && curl -sfL -o /tmp/cosign \
      "https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-linux-arm64" \
 && echo "${NONO_SHA256}  /tmp/nono.tar.gz" | sha256sum --strict --check - \
 && echo "${COSIGN_SHA256}  /tmp/cosign" | sha256sum --strict --check - \
 && chmod +x /tmp/cosign \
 && curl -sfL "https://api.github.com/repos/nolabs-ai/nono/attestations/sha256:${NONO_SHA256}" \
      | jq -c '.attestations[].bundle | (if type == "string" then fromjson else . end) \
          | select((.dsseEnvelope.payload | @base64d | fromjson | .predicateType) == "https://slsa.dev/provenance/v1")' \
          > /tmp/nono-provenance.jsonl \
 && test -s /tmp/nono-provenance.jsonl \
 && verified=no \
 && while IFS= read -r bundle || [ -n "$bundle" ]; do \
      printf '%s\n' "$bundle" > /tmp/nono-provenance.json; \
      if /tmp/cosign verify-blob-attestation \
           --bundle /tmp/nono-provenance.json \
           --type "https://slsa.dev/provenance/v1" \
           --certificate-identity-regexp '^https://github\.com/nolabs-ai/nono/\.github/workflows/release\.yml@' \
           --certificate-oidc-issuer https://token.actions.githubusercontent.com \
           /tmp/nono.tar.gz; then verified=yes; break; fi; \
    done < /tmp/nono-provenance.jsonl \
 && test "$verified" = yes \
 && mkdir /tmp/nono \
 && tar -xzf /tmp/nono.tar.gz -C /tmp/nono \
 && install -m 0755 /tmp/nono/nono /usr/local/bin/nono \
 && rm -rf /tmp/nono /tmp/nono.tar.gz /tmp/cosign /tmp/nono-provenance.json /tmp/nono-provenance.jsonl \
 && nono --version | grep -qxF "nono ${NONO_VERSION#v}" \
 && install -d -o dev -g dev /home/dev/.local/state /home/dev/.local/state/nono
# Back to the runtime user, as in the pig stage: root-owned in /usr/local/bin,
# executable by dev but not replaceable by it.
USER dev

# V5VWGS9 — alternative harness layer: PiG ("Pi in Go", github.com/MichaelKinsy/PiG), a
# Go port of the Pi terminal coding agent — one native binary, no Node.js. A
# separate stage rather than a switch, so a workspace chooses its harness by
# image tag (`--image hestia-pig:<tag>`) and the agent layer stays the default
# build. Kept before the agent stage so `docker build .` still builds the last
# stage, the agent image, as the header documents.
#
# Installed from the pinned release archive rather than through mise: the
# github backend's asset matching for this naming (pig-<version>-linux-arm64)
# is not something this repository has verified, while a pinned sha256 is the
# anchor style already used for mise itself. 2026-10-05, v0.4.1: no cosign or
# SLSA bundle is published (only upstream's SHA256SUMS and an update signature),
# so the trust anchor is the GitHub release API over TLS that published this
# digest — the same honest limitation recorded for the base stage. The pinned
# value was cross-checked against upstream's own SHA256SUMS file.
#
# No provider policy ships here, unlike the omp layer: PiG authenticates
# through interactive /login or provider API keys in its environment, and it
# documents no config-overlay mechanism to anchor a policy outside the
# user-writable tree. That remains an open choice for whoever needs it; the
# restriction decision (TG7VZBV, bedrock-only) belongs to the omp integration.
# PiG runs with the permissions of the user who starts it and does not sandbox
# model output, tools or shell commands (its own SECURITY.md says so), which is
# exactly what this container boundary is for. Durable state is PiG's config
# root ~/.pig (or PIG_HOME, agent directory PIG_CODING_AGENT_DIR), which the
# generated Compose file binds with `--state pig` — never baked.
FROM nono AS pig

ARG PIG_VERSION=v0.4.1
ARG PIG_SHA256=e1768bbfce29b784d76001eb47ebd989f05ed042fbe81ad8629816e181fa5ac8

USER root
RUN curl -sfL -o /tmp/pig.tar.gz \
      "https://github.com/MichaelKinsy/PiG/releases/download/${PIG_VERSION}/pig-${PIG_VERSION#v}-linux-arm64.tar.gz" \
 && echo "${PIG_SHA256}  /tmp/pig.tar.gz" | sha256sum --strict --check - \
 && tar -xzf /tmp/pig.tar.gz -C /tmp \
 && install -m 0755 "/tmp/pig-${PIG_VERSION#v}-linux-arm64/pig" /usr/local/bin/pig \
 && rm -rf /tmp/pig.tar.gz "/tmp/pig-${PIG_VERSION#v}-linux-arm64" \
 && pig --version | grep -qF "${PIG_VERSION#v}+"
# Back to the runtime user: the image's default user must stay dev, and a
# root-owned /usr/local/bin binary is executable by it but not replaceable.
USER dev

# Opt-in Pi-family and Claude Code layers. Like pig, each is a sibling stage on
# nono, chosen by image tag; none changes the agent default. Each ships no
# provider policy (omp's overlay is omp-only), authenticates through its own
# login or runtime keys, and does not sandbox its tools: the container, and
# nono when invoked, are the boundary. Install trees are root-owned under
# /opt/hestia, which the generator reserves from state mounts; binaries are
# linked into /usr/local/bin. Version checks run before any state exists:
# with update checks off, `--version` writes nothing under HOME (observed
# 2026-10-24 on each release's x86_64 build).

# pi — upstream Pi (github.com/earendil-works/pi), the TypeScript agent the
# omp and PiG layers derive from, as its own release binary (Bun-compiled; no
# Node.js). The tarball is a directory: the binary finds its themes and assets
# beside its resolved path, so a symlink works (observed). The pinned digest
# was cross-checked 2026-10-24 against upstream's SHA256SUMS, which is
# unsigned and has no attestation: the trust anchor is GitHub's release
# hosting over TLS, as for pig. PI_SKIP_VERSION_CHECK=1 stops the startup
# version request; the pinned binary updates by rebuild, not `pi update`.
# Durable state is ~/.pi (settings, sessions, auth): generate with
# `--state pi`.
FROM nono AS pi

ARG PI_VERSION=v1.4.0
ARG PI_SHA256=fa5829c7ef83ffeaebba015715c8306220f89b2aa8a00154efbba98dd5440156

ENV PI_SKIP_VERSION_CHECK=1

USER root
RUN curl -sfL -o /tmp/pi.tar.gz \
      "https://github.com/earendil-works/pi/releases/download/${PI_VERSION}/pi-linux-arm64.tar.gz" \
 && echo "${PI_SHA256}  /tmp/pi.tar.gz" | sha256sum --strict --check - \
 && mkdir -p /opt/hestia/pi \
 && tar -xzf /tmp/pi.tar.gz -C /opt/hestia/pi --strip-components=1 --no-same-owner \
 && rm /tmp/pi.tar.gz \
 && ln -s /opt/hestia/pi/pi /usr/local/bin/pi \
 && pi --version | grep -qxF "${PI_VERSION#v}" \
 && install -d -o dev -g dev /home/dev/.pi
USER dev

# pi-bolt — Pi-Bolt (github.com/opensec-git/Pi-Bolt): a fork of Pi v1.4.0
# compiled ahead of time on a patched Bun/WebKit engine. Young despite its
# 1.x version (first release 2026-10-02), with a larger trusted base
# than Pi (an experimental compiler plus ~32k lines of engine patches), so it
# is an experiment beside pi, not a replacement. The pinned digest was
# cross-checked 2026-10-24 against the release's SHA256SUMS, whose Ed25519
# signature verified against the repository's keys/release.pub (the key is
# hosted with the code, so this binds the files to the project, not to an
# independent party). Same agent directory and checks as pi: ~/.pi, shared on
# purpose with Pi, so `--state pi` serves both images.
FROM nono AS pi-bolt

ARG PI_BOLT_VERSION=1.0.2
ARG PI_BOLT_SHA256=acca0a2c070ea2664884350e5a3cbf2afbdada3b1966130ce025065796cfbeb3

ENV PI_SKIP_VERSION_CHECK=1

USER root
RUN curl -sfL -o /tmp/pi-bolt.tar.xz \
      "https://github.com/opensec-git/Pi-Bolt/releases/download/bolt-v${PI_BOLT_VERSION}/pi-bolt-linux-arm64.tar.xz" \
 && echo "${PI_BOLT_SHA256}  /tmp/pi-bolt.tar.xz" | sha256sum --strict --check - \
 && mkdir -p /opt/hestia/pi-bolt \
 && tar -xJf /tmp/pi-bolt.tar.xz -C /opt/hestia/pi-bolt --strip-components=1 --no-same-owner \
 && rm /tmp/pi-bolt.tar.xz \
 && ln -s /opt/hestia/pi-bolt/pi /usr/local/bin/pi-bolt \
 && pi-bolt --version | grep -qF "(Pi-Bolt ${PI_BOLT_VERSION}, linux-arm64," \
 && install -d -o dev -g dev /home/dev/.pi
USER dev

# claude-code — Anthropic's Claude Code, the native linux-arm64 (glibc) build
# published as npm package @anthropic-ai/claude-code-linux-arm64 and fetched
# from the registry directly: one self-contained binary, no Node.js or npm in
# the image. Pinned to the `stable` dist-tag as of 2026-10-24. The tarball's
# sha256 was checked against the registry's sha512 integrity, and both
# registry ECDSA signatures over that integrity verified against npm's
# published key; no npm provenance attestation is published for it.
# DISABLE_AUTOUPDATER=1: the binary is root-owned and pinned, so updates are
# rebuilds. CLAUDE_CONFIG_DIR puts all state in one directory: without it
# Claude Code also writes ~/.claude.json beside ~/.claude (observed), which a
# `--state claude` bind would miss. Network traffic beyond the model API
# (telemetry, error reporting, remote settings) is left at Claude Code's
# defaults; CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 turns it off at runtime.
FROM nono AS claude-code

ARG CLAUDE_CODE_VERSION=2.1.308
ARG CLAUDE_CODE_SHA256=e939ff4445b9942fe04af0f2892e7052b48c09609b1b340ce7ac47c87db8619f

ENV CLAUDE_CONFIG_DIR=/home/dev/.claude \
    DISABLE_AUTOUPDATER=1

USER root
RUN curl -sfL -o /tmp/claude-code.tgz \
      "https://registry.npmjs.org/@anthropic-ai/claude-code-linux-arm64/-/claude-code-linux-arm64-${CLAUDE_CODE_VERSION}.tgz" \
 && echo "${CLAUDE_CODE_SHA256}  /tmp/claude-code.tgz" | sha256sum --strict --check - \
 && tar -xzf /tmp/claude-code.tgz -C /tmp --no-same-owner package/claude \
 && install -m 0755 /tmp/package/claude /usr/local/bin/claude \
 && rm -rf /tmp/claude-code.tgz /tmp/package \
 && claude --version | grep -qxF "${CLAUDE_CODE_VERSION} (Claude Code)" \
 && install -d -o dev -g dev /home/dev/.claude
USER dev

# XJVWF4K — optional agent layer: omp (oh-my-pi, TG7VZBV decision; AWS Bedrock
# by default, with a user-opted-in LiteLLM overlay below). Installed through
# mise like every other declared tool and
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
FROM nono AS agent

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

# AWCEX5Z — user-selected LiteLLM alternative, opt-in at attach only.
# Derive from the same provider list; the default Bedrock overlay is unchanged.
# No endpoint, model, credential or writable native settings are baked here.
# setupVersion 2 is omp 18.1.16's supported onboarding completion marker.
USER root
RUN sed '/^#/d; /^  - "litellm"$/d; /^setupVersion:/d; s/^disabledProviders:$/disabledProviders:\n  - "bedrock"/' \
      /opt/hestia/omp/config.yml > /opt/hestia/omp/litellm.yml \
 && printf 'setupVersion: 2\n' >> /opt/hestia/omp/litellm.yml \
 && chmod 0644 /opt/hestia/omp/litellm.yml
COPY agent/omp/litellm-session.sh /opt/hestia/omp/litellm-session.sh
USER dev
