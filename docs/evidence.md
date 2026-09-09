# Evidence log

[Milestone 1](milestone-1.md) · [Architecture](architecture.md) · [README](../README.md)

Observed results only. Each entry records platform, actions and outcomes;
requirements are tracked pass/fail/not-run per the Milestone 1 spec. Intentions
live in the spec, not here.

| ID | Status | Evidence |
| --- | --- | --- |
| M1-01 | partial | Base image and fixture-toolchain layer verified (below): canonical Dockerfile with named stages, pinned inputs, non-root, offline startup, real fixture build/test in-container. Selected agent layer remains (blocked on `TG7VZBV`). |
| M1-02 | partial | Scoped mounts verified (below): identical-path source bind, metadata-only worktree bind, no socket/home exposure, host/container agreement. Persistent state mounts and concurrency follow (`KSCDG1J`, `24GJSHY`). |
| M1-03 | pass (fixture scope) | Non-root writes, artifact separation and cache/state classification verified (below). Agent-state mounts remain (`XJVWF4K`). |
| M1-04 | partial | Identity helper verified with 16/16 tests on 2026-09-09 ([identity](../identity/README.md)); container-resource usage pending. |
| M1-05 | partial | Absolute and relative worktree links resolve in-container; stage/diff without pointer rewriting verified (below). Unsupported layouts fail clearly. Full concurrent workloads follow in Milestone 3. |
| M1-06 | not run | Lifecycle/persistence proof pending (`24GJSHY`). |
| M1-07 | not run | Blocked on the human agent decision (`TG7VZBV`). |
| M1-08 | not run | Cache clearing pending (`HE2GM6N`). |
| M1-09 | partial | Failed-download behavior, missing-tool errors and trust gating verified for the image (below); other failure classes pending. |

## Base image — 61Q7E8F, 2026-09-09

Host: macOS 25.6.0 arm64, Docker server 29.5.2 (linux/aarch64), docker CLI
29.8.0.

- **Base image:** `debian:bookworm-slim` pinned by OCI index digest
  `sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171`
  (digest from `docker pull`/RepoDigests; linux/arm64 manifest digest
  `sha256:6bd27d44e6c32a66bbd72d7cb2b76a8ae3497ec2e5274a81abd1b37f6013fa1f`
  from `docker manifest inspect`).
- **mise:** `v2026.9.4` (latest release, published 2026-09-09). The release
  publishes no standalone checksum assets, so the pinned sha256
  `18303fdb59095acf0c50b0d23819b87182516988f9eb2ec016b52f8814916904` is the
  GitHub release-API asset digest (served over TLS, computed by GitHub). The
  tarball was downloaded on-host and matched that digest before pinning, and
  the build re-verifies it with `sha256sum --strict --check`. Stronger SLSA
  attestation verification exists upstream and remains an open choice.
- **Build:** cold `--no-cache` build 13 s; cached rebuild 0.6 s. Image
  `sha256:caca07509a9296b332fda830fa5b76966ef7279cbc2a076316ada920130b43b3`,
  `linux/arm64`, 145,774,378 bytes, default user `dev` (uid 1000).
- **Offline startup:** `docker run --rm --network none` printed uid 1000,
  mise `2026.9.4 linux-arm64`, git `2.39.5`, curl `7.88.1`, wrote and removed
  a file in `/home/dev` — a shell starts and reports tools with no network and
  no downloads. Warm container start 128 ms.
- **Failed build safety:** a build against the same tag with a wrong
  `MISE_SHA256` failed at the checksum step; the existing image ID was
  unchanged and the source tree had no modifications (only the new, untracked
  Dockerfile).
- **Exclusions by construction:** no GUI, no agent supervisor, no host Docker
  socket, no credentials or login state.

Only `linux/arm64` is exercised; no multi-arch or Windows support is claimed.

## Fixture toolchain layer — WGHQ2GW, 2026-09-09

Host: macOS 25.6.0 arm64, Docker server 29.5.2. Stage `fixture-tools` on top
of the verified base stage; one Dockerfile, two named targets.

- **Build:** `docker build --target fixture-tools .` — 17 s. Image
  `sha256:3031b761d8a98917f6298b6ee3cbceb47776dae67d07d9012b5cda94eef0fcc2`,
  `linux/arm64`, 227,971,940 bytes, default user `dev`. The base target
  rebuilds to the identical base image ID (one canonical build path).
- **Toolchain:** go 1.27.1 (from the fixture's `mise.toml` pin) installed by
  `mise install` at build time only; the global toolchain config is
  root-owned, readable but not modifiable by the runtime user. The fixture
  build/test ran inside the build (`go build ./...`, `go test ./...` →
  `ok example.com/hestia-synthetic/greet`); its source was removed in the
  same layer and does not ship in the image.
- **Startup installs nothing:** `docker run --rm --network none` →
  `mise exec -- go version` → `go1.27.1 linux/arm64` with no downloads.
- **Missing tool fails clearly:** `mise exec -- node` →
  `mise ERROR "node" couldn't exec process` with non-zero exit.
- **Trust gating (deliberate trust):** mise 2026.9.4 normal mode auto-trusts
  a project's active config — observed directly: a never-trusted mounted
  `mise.toml`'s task executed unchallenged. The image therefore sets
  `MISE_PARANOID=1`. Verified cycle with a mounted config: untrusted →
  blocked (`Config files in /demo/mise.toml are not trusted. Trust them with
  'mise trust'.`); after `mise trust` → task runs; after editing the file →
  blocked again (content-bound); after re-trust → new content runs. The
  image's own global config stays usable without prompting. mise documents
  that paranoid mode also disables trust sharing across git worktrees —
  relevant to the worktree mount work (`JP73P2D`).

A macOS `/tmp` bind mount silently produced an empty directory in the
container (path not in Docker Desktop file sharing); mount proofs must use
shared paths — noted for the mount-planning ticket.

## Scoped workspace mounts — JP73P2D, 2026-09-09

Host: macOS 25.6.0 arm64, Docker server 29.5.2, fixture-tools image
`sha256:3031b761...fcc2`. `tests/workspace-mounts.test.sh` passed 20/20.

- **Generated Compose file**: binds the checkout's canonical path at its
  identical in-container path; linked worktrees additionally bind the common
  Git directory (metadata only, main source never mounted); project name is
  the workspace id; no home/repos mount, socket or credentials.
- **Agreement**: `git status --porcelain=v2` identical host vs container;
  host-written and container-written marker files each visible from the other
  side.
- **Worktrees**: for both the absolute (`wt-abs`) and relative (`wt-rel`)
  gitdir layouts, `git rev-parse --git-common-dir` resolved in-container and
  `git add`/`git diff --cached` worked with the `.git` pointer files
  byte-identical before and after — no pointer rewriting.
- **Ownership**: host uid 501 vs container uid 1000 triggers git's dubious
  -ownership refusal; scoped `GIT_CONFIG_*` `safe.directory` entries for
  exactly the mounted paths (honored by git 2.39.5 in the image) resolve it
  without blanket trust.
- **Exposure**: from a worktree container the main checkout's source is not
  visible (its `.git` metadata is, by design); `/var/run/docker.sock` absent;
  host paths outside the declared binds are invisible.
- **Failures**: missing path, dangling `gitdir:` pointer and non-checkout all
  fail with clear errors; failed generation writes no file; the fixture's
  captured snapshot still compared clean after the probes (no mutation).

## Writes, caches and artifact separation — KSCDG1J, 2026-09-09

Host: macOS 25.6.0 arm64, Docker server 29.5.2; image rebuilt with a
dev-owned `/hestia/cache` (`sha256:df7e77d2...e05e`). Extended
`tests/workspace-mounts.test.sh` passed 29/29.

- **Effective ownership (this runtime):** the non-root container user
  (uid 1000 `dev`) reads and writes the VirtioFS-mounted host source and the
  mounted state/cache paths directly; copying the host UID is not used and no
  host-side chown exists anywhere in the helpers (recursive host chown as a
  "repair" is ruled out by construction, per ADR-001).
- **Artifact separation:** a real in-container `go build ./... && go test ./...`
  on the mounted fixture source (after one deliberate `mise trust` of the
  repo, exercising the paranoid default) passed and left `git status
  --porcelain=v2` byte-identical; its artifacts went only to the
  workspace-scoped `linux-caches` volume (`GOCACHE`/`GOMODCACHE`), verified
  populated afterwards. A native host `mise exec -- go build/test` on the same
  source also passed and also left the tree unchanged — host and container
  outputs live in disjoint caches (host `~/Library/Caches` vs the volume), so
  they cannot overwrite each other through the shared tree.
- **Caches vs durable data:** disposable = the `linux-caches` Compose volume
  only; durable = the identity-recorded state directory; source/Git = host
  storage never written by builds. Nothing mounts over mise's install
  directories, so image toolchain updates cannot be hidden by old state.
- **State failures:** an unwritable state directory fails generation with
  `state directory exists but is not writable: <path> — fix its
  ownership/permissions...`; a state directory recorded for a different
  checkout is refused before any file is written.
