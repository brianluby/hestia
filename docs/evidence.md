# Evidence log

[Milestone 1](milestone-1.md) · [Architecture](architecture.md) · [README](../README.md)

Observed results only. Each entry records platform, actions and outcomes;
requirements are tracked pass/fail/not-run per the Milestone 1 spec. Intentions
live in the spec, not here.

| ID | Status | Evidence |
| --- | --- | --- |
| M1-01 | pass (fixture scope) | Final canonical agent image, integrity checks and actual build/tests: [successor receipt](m1-apple-silicon-evidence-v2.md). |
| M1-02 | pass (fixture scope) | Scoped mounts and host/container edits; historical mount suite and final native edit visibility in the successor receipt. |
| M1-03 | pass (fixture scope) | Non-root writes, artifact separation and scoped native-state persistence. |
| M1-04 | pass (fixture scope) | Historical 19/19 identity checks; final project identity retained through recreation. |
| M1-05 | pass (fixture scope) | Historical 31/31 mount checks with absolute/relative worktree staging; full concurrency has separate acceptance. |
| M1-06 | pass (fixture scope) | New container IDs, exact source/Git/index and selected native-state equality before resumed work; repeated build/tests. |
| M1-07 | pass (LiteLLM fixture) | Real authenticated native omp edits, explicit saved JSONL resume and recalled context. Bedrock remains unverified. |
| M1-08 | pass (fixture scope) | Scoped own-cache clearing/regeneration and durable source/Git/state preservation in the historical receipt. |
| M1-09 | pass (applicable fixture cases) | Recorded source/metadata/state/identity/tool/download failures plus real denied auth and fresh-handoff recovery. No published ports; actual expiry/automatic refresh not tested. |

Current Apple Silicon M1A acceptance is recorded in the
[native LiteLLM successor receipt](m1-apple-silicon-evidence-v2.md) and
[result JSON](m1-apple-silicon-result-v2.json). The
[earlier partial receipt](m1-apple-silicon-evidence.md) remains unchanged.
Historical foundation 101/101 and final LiteLLM 34/34 stub checks are distinguished
from real provider inference. Argus, Bedrock authentication and Windows/WSL2
remain unverified; Milestone 1 is incomplete.

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
  GitHub release-API asset digest (served over TLS, computed by GitHub).
  Per the A5H3NY9 decision (SLSA), the build additionally verifies the
  tarball's SLSA v1 provenance: fetched anonymously from GitHub's
  attestations API keyed by that digest, verified with cosign v3.1.3
  (pinned by its release-API digest
  `c5d324e091826b0d7a78eb16fef316450b4eb9aaec045611c08ba06f5e73220a`),
  with the signing identity pinned to
  `https://github.com/jdx/mise/.github/workflows/` via the GitHub Actions
  OIDC issuer. Remaining trust anchor, stated honestly: the cosign and mise
  digest pins come from the GitHub release API over TLS — GitHub remains the
  root of this chain.
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

## Workspace lifecycle — 24GJSHY, 2026-09-09

Host: macOS 25.6.0 arm64, Docker server 29.5.2, fixture-tools image.
`tests/workspace-lifecycle.test.sh` passed 14/14 on a fresh fixture
(`workspace/workspace-lifecycle.sh` over a generated Compose file).

- **Start/attach:** `start` brings the workspace up detached
  (`command: sleep infinity` in the generated service); `attach` runs a
  shell or command in the running container via `compose exec`.
- **Durable write:** a marker written through the attached container landed
  in the workspace state directory on the host.
- **Stop/start:** `stop` retained the container; the next `start` reused the
  identical container ID — the workspace stays attachable across stops.
- **Recreate:** stop → remove-runtime → start produced a different container
  ID (verified, and the helper fails if it ever does not); the durable state
  marker survived, the fixture's captured snapshot still compared clean
  (source bytes, index/tree, HEAD/branch, status incl. untracked all
  unchanged), the `linux-caches` volume survived, and a real
  `go build`/`go test` (after one deliberate `mise trust`) passed inside the
  replacement container.
- **Safety:** the helper refuses Compose projects whose name is not a Hestia
  workspace id; it contains no `down -v`, no prune, no volume deletion and no
  source deletion. Recovery and offline-startup limits are documented in
  `workspace/README.md` (warm startup needs the image locally; startup never
  downloads).

## Scoped cache clearing — HE2GM6N, 2026-09-09

Host: macOS 25.6.0 arm64, Docker server 29.5.2. `workspace-lifecycle.sh
clear-caches` over a generated workspace; `tests/workspace-cache-clear.test.sh`
passed 10/10 on a fresh fixture.

- **Target identity before removal:** the command removes exactly
  `<workspace-id>_linux-caches` and only after verifying that the Compose file
  itself declares a `linux-caches` volume; a workspace without one, a missing
  file and any non-Hestia project are refused. No global prune, no other
  volumes, no state directories.
- **Clearing:** stops the workspace (finish active work), removes the runtime
  and the volume, restarts — the fresh volume initializes empty from the
  image's dev-owned `/hestia/cache` (verified: no `go/build` dir afterwards).
- **Preservation:** source bytes, index/tree, HEAD/branch and full status
  (snapshot compare) and the durable state directory (marker + identity
  record) were unchanged across the clear.
- **Regeneration:** a second in-container `go build`/`go test` (after one
  deliberate `mise trust`) passed with the caches rebuilt into the fresh
  volume.

## SLSA verification of mise — JBTHN9J, 2026-09-09

Host: macOS 25.6.0 arm64, Docker server 29.5.2. Decision source: A5H3NY9
(user chose SLSA over API-digest-only).

- **Provenance:** GitHub's attestations API for the pinned tarball digest
  returns two attestations; the SLSA v1 provenance
  (`https://slsa.dev/provenance/v1`) lists every release asset including
  `mise-v2026.9.4-linux-arm64.tar.gz`, with builder
  `jdx/mise/.github/workflows/release.yml@refs/tags/v2026.9.4` and the
  release workflow as external parameters.
- **Verifier:** cosign v3.1.3 —
  `verify-blob-attestation --bundle <sigstore bundle> --type
  https://slsa.dev/provenance/v1 --certificate-identity-regexp
  ^https://github\.com/jdx/mise/\.github/workflows/
  --certificate-oidc-issuer https://token.actions.githubusercontent.com`.
  The raw predicate-type URI is required: the `slsaprovenance` shorthand
  maps to the older v0.2 URI and rejects v1; slsa-verifier v2.7.1 cannot
  verify this provenance at all (its builder-ID parser rejects tag refs).
- **Verified behavior:** positive case `Verified OK` (rc 0); a single
  flipped byte in the tarball → rc 1; a different (legitimately signed)
  asset from the same release → rc 1; a build with a wrong MISE_SHA256 pin
  fails. All probes ran anonymously in a clean debian container — no GitHub
  authentication is needed at build time.
- **Build:** cold `--no-cache` fixture-tools build 32 s, image
  `sha256:da4e08c28c50...b46d`, 173,134,062 bytes (down ~40 MB: the mise and
  cosign downloads moved into the verification RUN, so neither ships as a
  dead layer). All four suites pass against this image (19/29/18/12).
- **Trust anchor:** cosign and mise pins derive from the GitHub release API
  over TLS; the provenance is fetched from GitHub's attestations API at
  build time. GitHub is the root of the chain — an explicit, documented
  limitation, not a claim of independence from it.

## Full-review fixes — 2026-09-09, commit a868bfa reviewed

All five reproduced findings from the full repository review
([archive](reviews/2026-09-09-full-review-a868bfa.md)) were fixed and
regression-tested:

- **AG2HKSM (P1):** every lifecycle Compose invocation now passes
  `-p "$project"`; an ambient `COMPOSE_PROJECT_NAME` override can no longer
  redirect operations to a foreign project (regression: a foreign project's
  running container survives the override).
- **G2ADH4M (P2):** snapshots hash raw working-tree bytes — NUL-delimited
  enumeration, `hash-object --no-filters`, explicit symlink and
  missing-file handling, propagated failures. Regressions: non-ASCII content
  changes, LF→CRLF flips under `*.txt text eol=lf`, symlink retargets and
  tracked-file deletions all fail comparison (previously compared clean).
- **Q6ZE1W0 (P2):** lifecycle commands revalidate the durable identity
  against the saved Compose file before reusing state or touching a working
  container (read-only check; a tampered record fails validate and start).
- **GGGET9D (P2):** daemon preflight plus error-propagating existence and
  running queries — an unreachable DOCKER_HOST fails commands instead of
  reporting a successful stop.
- **QAPTN0Y (P2):** a relative `HESTIA_STATE_ROOT` is rejected with a clear
  error before any state or file is written (its meaning would differ between
  the generator's and the Compose file's directories).

Suites after the fixes: fixture-snapshot 7/7, identity 19/19, mounts 31/31,
lifecycle 23/23, cache-clear 12/12 — 92 checks on macOS 25.6.0 arm64
(Docker server 29.5.2), image `sha256:da4e08c28c50...b46d` unchanged.

## omp agent layer — XJVWF4K, 2026-09-10 (implementation slice)

Host: macOS 25.6.0 arm64, Docker server 29.5.2. Image target `agent` on
`fixture-tools`; `tests/workspace-agent.test.sh` passed 16/16, all other
suites re-run green (snapshot 7, identity 19, mounts 31, lifecycle 23,
cache-clear 12 — 108 checks total).

- **Install:** omp v18.1.16 via mise (`github:can1357/oh-my-pi`); the
  installed binary hashes to the pinned release-API digest
  `d8612389c7af...b9720` and reports `omp/18.1.16`. Image
  `sha256:ff3e01283e46...f721`, 256,553,123 bytes.
- **Provider policy:** `agent/omp/config.yml` (everything except bedrock
  disabled) ships root-owned in the image and is bound read-only over the
  state mount in generated Compose files — byte-identical to the repo
  template at runtime and not writable by the dev user (asserted).
  (Superseded by FA5H9TR below: the read-only bind broke omp's atomic
  settings writes; the policy now rides at `/opt/hestia/omp/config.yml`.)
- **Empirical omp layout fixes applied during integration:** `~/.omp` and
  `~/.omp/agent` must be dev-writable (omp extracts `pi_natives` into
  `~/.omp/natives` and opens `~/.omp/agent/agent.db` at startup — both
  initially broke under root-owned dirs, diagnosed via strace).
- **State scoping:** `~/.omp` binds from `<state-root>/<workspace-id>/omp`;
  `agent.db`, markers and sessions persist across `recreate` (asserted) and
  are host-visible; `clear-caches` never touches them; source/Git state
  compared clean after all probes.
- **Missing auth (M1-09 slice):** with no AWS credentials, `omp -p hi` exits
  1 with `No models available. Use /login or set an API key environment
  variable. Then use /model to select a model.` while `git status` and the
  shell remain usable in the same container (asserted).
- **Per-container behaviors observed:** `mise trust` of the mounted repo is
  required once per container under the paranoid default (re-trust after
  recreation verified); omp resolves through mise shims, so untrusted local
  mise config blocks invocation until trusted.
- **Not yet done (the ticket's remaining leg):** real AWS credential-chain
  login, an agent-assisted fixture change, and session resume across
  recreation with a real session — deliberately left for the user-driven
  interactive step; no credentials exist in any image, Compose output or log.

## omp settings persistence — FA5H9TR, 2026-09-10

Host: macOS 25.6.0 arm64, Docker server 29.5.2. Agent image rebuilt as
`hestia-agent:2026-09-10`, `sha256:9c7150a7fefd…`, 256,554,658 bytes; omp
v18.1.16 re-verified against the pinned release digest at build. All suites
green: agent 24, snapshot 7, identity 19, mounts 31, lifecycle 23,
cache-clear 12 — 116 checks total.

- **Root cause (omp v18.1.16 source):** `Settings#writeYamlAtomically`
  creates `config.yml.<pid>.<uuid>.tmp` in `~/.omp/agent/` then renames onto
  `config.yml`. Renaming onto the old read-only bind mount failed with EBUSY
  and the rejection was unhandled — every settings write crashed.
- **Mechanism (omp v18.1.16 source):** config layers merge global → project
  → overlay → runtime overrides (`#rebuildMerged`); overlays come from
  `PI_CONFIG_FILES`; a missing or malformed overlay is a hard startup error
  (fail-closed); `omp config get <key>` reports the effective merged value
  without needing credentials.
- **New enforcement:** policy baked root-owned at `/opt/hestia/omp/config.yml`
  (root-owned directory, so neither edit nor rename-over is possible — no
  bind required); Compose sets `PI_CONFIG_FILES: /opt/hestia/omp/config.yml`;
  nothing is bound inside `~/.omp`, which is fully dev-writable.
- **Observed in containers:** with the overlay, `omp config get
  disabledProviders` lists everything except bedrock; after writing
  `disabledProviders: []` into the user's `~/.omp/agent/config.yml` the
  effective value is unchanged (overlay shadows user config); without the
  overlay env the same probe returns `[]` (control — proves the probe
  detects a real leak, and documents the boundary: whoever controls the omp
  process environment can bypass the policy, as they could against the
  read-only bind too). `omp models ls` is auth-driven (empty without
  credentials either way) and therefore NOT usable as a policy probe.
- **Settings persistence:** omp's atomic tmp+rename write onto
  `~/.omp/agent/config.yml` succeeds (asserted); content is host-visible in
  `<state-root>/<workspace-id>/omp/agent/config.yml` and survives `recreate`
  (asserted).
- **Policy guarantees kept and asserted:** byte-identical to the repo
  template, not writable, directory not writable (no rename-over), overlay
  wired in the generated Compose file, re-enable attempt shadowed.
- No credentials exist in any image, Compose output or log.

## Lifecycle review fixes — 2026-09-16

Host: macOS 27.0 (26A428), arm64; Docker client 29.8.1, server 29.5.2
through Colima. Based on the existing FA5H9TR overlay correction.
The suites and path smoke checks used existing images:

- Fixture: `sha256:da4e08c28c507e8a9cd5913f15f2fda2fb2fa01dc9a836b4af2dea884edb46d1`.
- Agent: `sha256:9c7150a7fefd9b35463199896bc080ff37e64100ea0821332d651761b112b026`.

Observed commands (all exit 0):

- `bash tests/workspace-agent.test.sh`: 24 passed, 0 failed.
- `bash tests/workspace-lifecycle.test.sh`: 32 passed, 0 failed.

Before the fix, Compose decoded an apostrophe in a checkout path correctly,
but lifecycle validation passed the doubled YAML apostrophe to the identity
helper and failed with `not a directory`. Lifecycle now reverses the
generator's apostrophe and dollar escaping for checkout and bind paths.
A direct disposable-workspace smoke check used both characters in checkout
and state paths: validate, start, container read of host source, recreate
with a different container ID, and another source read all passed. Its
containers, network, cache volume and temporary files were removed.

Replacement preflight now checks identity, Compose validity and local image
availability before start, recreation or cache clearing. Regression checks
confirm that recreate and clear-caches reject a missing replacement image
without changing the running container, durable marker or cache volume.
This is not rollback for failures that occur after successful preflight.

Authenticated Bedrock acceptance remains blocked: this environment has no
AWS CLI, credential environment, selected profile/region, or standard shared
AWS config/credentials files. No credential contents were read or logged.
Agent checks above prove unauthenticated behavior and filesystem/settings
persistence, not a native interactive settings change, authenticated agent
work or real-session resume. Those still require scoped runtime access and
the user-driven acceptance journey.

The agent image also passed a direct escaped-path runtime smoke check:
`pwd` inside the container exactly matched the host checkout containing a
literal apostrophe and dollar sign, and `omp --version` reported
`omp/18.1.16`, both before and after recreation with a different container
ID. No authenticated model call was attempted. The initial smoke assertion
against `docker compose config --format json` was invalid because that
serialization retains doubled dollars; the actual container path was used
for verification instead. All resources from this smoke check were removed.

Documentation checks: local file links in the six changed Markdown documents
resolve; the fixture walkthrough passes `bash -n`, and its fixture-output
selector matches the helper. The exact walkthrough block then passed under
`bash -c` (exit 0): tagged Docker build, fixture creation, generation,
validation, start, attached trust/build/test, recreation with a different
container ID, re-trust/build/test, clean snapshot comparison and stop.
The build used cached layers and produced the fixture digest above; this
does not establish a fresh download/provenance check. Docker emitted its
legacy-builder deprecation warning. The first harness invocation supplied
the script over stdin, which Compose exec consumed; the complete successful
run used `bash -c` instead. Synthetic directories, containers, networks and
cache volumes from both attempts were removed; the built image tag remains.

## Review fixes re-verified — 2026-10-08

Host: macOS 27.0 arm64, Colima `default` profile (macOS Virtualization.Framework,
vmType `vz`, mountType `virtiofs`; Docker client 29.8.2, server 29.5.2
linux/aarch64, driver overlayfs; both builds used the legacy builder, which
emitted only its deprecation warning). The VM was restarted first: guest
`exec` and `/var/lib/docker` writes were failing with EIO (`colima ssh` could
not run a binary), so *every* Docker operation failed before the restart.
`colima delete` was deliberately not used — that VM also holds unrelated
images and volumes.

- **Builds**, both from the canonical Dockerfile and fresh:
  `--target fixture-tools -t hestia-fixture-tools:2026-09-09` in 34 s →
  `sha256:85ca52d20159…f0d9`, linux/arm64, user `dev`, 175,488,126 bytes. The
  mise SLSA provenance verification is part of one layer of this build and it
  completed; the in-image fixture build/test printed
  `ok example.com/hestia-synthetic/greet`. `--target agent -t
  hestia-agent:2026-09-10` → `sha256:164236feb712…ae8d`, 258,907,713 bytes.
- **Suites, all exit 0:** mounts 42/42, lifecycle 32/32, cache-clear 12/12,
  agent 24/24, identity 20/20, fixture-snapshot 7/7 — 137 checks. These are
  this run's counts, not the historical totals above.
- **Agent state mounts are data, not omp-specific wiring.** The new mounts
  checks covered `--state NAME[:CONTAINER_PATH]` (default
  `omp:/home/dev/.omp`) and `--env NAME=VALUE`: default output unchanged (3
  binds main, 4 worktree), explicit `--state` replacing the default bind,
  state directories created under the workspace state directory, container
  path overrides, and rejection of names that would escape the state
  directory, relative container paths, and generator-owned variable names.
  `workspace-lifecycle.sh validate` accepted a two-state file (identity
  revalidation unaffected) and still refused a tampered record.
- **One regression, caught by the suite.** Emitting the bind target quoted
  (`target: '/home/dev/.omp'`) broke the agent suite's unquoted `grep`; the
  assertion now accepts optional quotes. Mounts and agent were re-run green
  after the fix, and no other suite assumed the unquoted form.
- **Not run in this work:** a real provider authentication, an assisted change
  or a session resume — the runs above exercised the unauthenticated legs only.
  Provider acceptance itself is recorded separately by the base's native
  LiteLLM fixture proof (`docs/m1-apple-silicon-evidence-v2.md`); Bedrock
  authentication remains pending.

Both suite runs used synthetic fixture storage under `$HOME/.cache` only;
their preserved host artifacts were left on disk for inspection, and no
hestia containers or cache volumes remained afterwards (the `*_linux-caches`
volumes still present date from 2026-09-09/09-10/10-03).

### BuildKit re-check, same host, later the same day

buildx v0.38.0 (Homebrew) / BuildKit v0.30.0 became available on the Colima
`docker` driver, so both targets were rebuilt from the unchanged Dockerfile
with `docker buildx build --platform linux/arm64 --load` to probe tags:
fixture-tools `sha256:a5db334aed17…` (175,489,649 bytes) and agent
`sha256:753390ca2841…` (258,909,681 bytes) — linux/arm64, user `dev`, within
~2 kB of the legacy-builder sizes above. (BuildKit exports a manifest list, so
the digest it records is the manifest-list digest; the agent digest is from a
post-lint-fix rebuild that was a cache hit on unchanged layers.)

Running both probe images with `--network none` re-confirmed the offline
contract on the new builder: uid 1000, mise `2026.9.4 linux-arm64`,
`go1.27.1 linux/arm64`, `omp/18.1.16`, and `/opt/hestia/omp/config.yml` still
`root:root`.

`docker buildx build --check` reports exactly one finding and **exits 1** on it:
`FromPlatformFlagConstDisallowed` at the pinned `FROM --platform=linux/arm64`.
Keeping the constant is deliberate — the mise and cosign downloads in that
file are arm64-only, and deriving the base platform from a build argument is
what previously let the base and those downloads disagree — so the rule is now
skipped by a `# check=…` directive beside it, with the reason in the comment.
After that, `--check` is clean (rc 0) for both targets, and the build output is
unchanged. The probe tags were removed; the `2026-09-09`/`2026-09-10` tags
still point at the legacy-builder images recorded above, and the next real
build will replace them under BuildKit.

## PiG harness layer — 2026-10-08

Host: macOS 27.0 arm64, Colima `default` (Docker client 29.8.2, server 29.5.2
linux/aarch64, BuildKit v0.30.0). PiG ("Pi in Go",
[github.com/MichaelKinsy/PiG](https://github.com/MichaelKinsy/PiG), MIT) is a
second optional harness on the same fixture journey. Nothing here claims
acceptance for it, and nothing about M1-07 moves.

- **Pin and verification.** Release `v0.4.1` (published 2026-10-05), asset
  `pig-0.4.1-linux-arm64.tar.gz`, 28,950,232 bytes, sha256
  `e1768bbfce29b784d76001eb47ebd989f05ed042fbe81ad8629816e181fa5ac8`. The
  digest was taken from the GitHub release API and cross-checked twice:
  downloading the tarball reproduced it, and upstream's own `SHA256SUMS` asset
  lists the same value. No cosign or SLSA attestation is published for these
  assets (only an update signature), so the trust anchor is the GitHub release
  API over TLS — recorded here rather than implied.
- **Build.** `docker build --platform linux/arm64 --target pig` →
  `hestia-pig:2026-10-08`, `sha256:87e86741816b…`, 205,598,331 bytes,
  linux/arm64, default user `dev`. `docker buildx build --check --target pig .`
  reports no warnings. The stage is a sibling of the agent stage placed before
  it, so `docker build .` still builds the agent image.
- **Offline binary.** `docker run --rm --network none` as uid 1000 printed
  `pig --version` = `0.4.1+1.0.3` and
  `pig version`: pig 0.4.1, upstream pi 1.0.3, go1.27.1, linux/arm64, build
  `3ee745c8cda3c1a9a8d71112c140790c4d64d78d` — the release's target commit.
  `/usr/local/bin/pig` is root-owned, mode 0755, 60,096,672 bytes; the layer
  needs no Node.js.
- **Workspace.** A Compose file generated for a fixture checkout with
  `--image hestia-pig:2026-10-08 --state pig` binds the checkout, the state
  directory and `<state>/pig` → `/home/dev/.pig` (three binds plus the cache
  volume). `validate` and `start` passed; inside the running container as dev,
  the working directory was the checkout and `pig --version` printed
  `0.4.1+1.0.3`; a marker written to `~/.pig` appeared on the host at
  `<state>/pig/probe.txt` owned by `dev`; the fixture snapshot still compared
  clean, so source and Git state were untouched. `stop` and `remove-runtime`
  retained state and volumes, and the container, network and cache volume were
  removed afterwards (smoke artifacts kept under
  `$HOME/.cache/hestia-pig-smoke` for inspection).
- **Not run:** PiG authentication (`/login` or provider keys in the
  environment), an agent-assisted change, and session persistence or resume.
  This layer ships no provider policy, unlike the omp layer: PiG documents no
  config overlay to anchor one outside the user-writable tree, and it states
  that it does not sandbox model output, tools or shell commands — the
  container is the boundary. Selecting a policy mechanism for PiG remains an
  open choice.

## PR #29 review remediation — 2026-10-09

Host: macOS 27.0.1 arm64, Colima, Docker 29.5.2 server. Five findings came back
from the PR's reviewers (Codex, CodeRabbit, Copilot).

- **Agent-state exposure (Codex, P1).** `--state` selects the bound agent
  directory, but the workspace state directory is still bound at its identical
  path, so a workspace reaches every agent tree under it — a PiG container can
  read a sibling `omp` tree. Not changed structurally: that bind is load-bearing
  (`tests/workspace-cache-clear.test.sh` writes `<state>/marker.txt` through the
  container, runbook step 5 reads `$STATE/tester-marker.txt` inside one), and
  separating identity/general state from agent-private state moves paths across
  the lifecycle helper, the runbook and three suites. Documented in the
  generator header and the workspace reference, with ADR-003's one-variant-per-
  checkout model named as the bound; the structural split is decision ticket
  W9JPBGQ.
- **Temporary record leak (CodeRabbit).** Real, and the earlier fix was
  incomplete: cleanup ran only after a successful link, so the race-loser path
  reached `fail` first and left `identity.record.XXXXXX` behind. An `EXIT` trap
  now covers every path; the new regression test fails on the previous code
  (`identity.record.TWXDcD` left behind) and passes now.
- **Unvalidated names (CodeRabbit).** Real: `--state`/`--env` names were checked
  only by the line-based charset `grep`, so a name containing a newline reached
  directory creation, bind paths and YAML keys. Both now pass the shared value
  check first.
- **Colliding targets (CodeRabbit).** Real: a `--state` target could repeat the
  checkout, the Git metadata, the state directory or another state target. The
  duplicate shapes fail loudly in the loader (`target /home/dev/.omp already
  mounted as services.workspace.volumes[2]`); the ancestor shapes — a target
  hiding what sits underneath it — are the ones Compose cannot see at all.
  Targets are validated before any state directory is created, comparing the
  emitted container paths — the first
  attempt resolved host paths instead, which was wrong: a `target` names a path
  inside the container, so a host symlink spelling (`/var` → `/private/var` on
  macOS) is a distinct destination there and must not be refused. A second
  review round caught that, and that the cache volume's `/hestia/cache` was
  missing from the reserved set.
- **Image-owned paths (Codex, second re-review).** A state target could also sit
  on or above a path the image owns — `/home/dev`, mise's toolchain and config,
  `/usr/local/bin`, `/opt/hestia/omp` — where a bind hides what is underneath
  and starts a workspace that cannot run its own tools. Those paths are now
  reserved in both directions (a target may neither repeat one nor be its
  ancestor), with tests covering five of them plus the valid shapes.
- **Test gap (Momus).** The `stop` branch reporting that no workspace container
  exists was only checked by hand; the lifecycle suite now asserts both its
  message and its exit status.
- **Installed skill typo (Copilot).** Fixed in `.claude/skills/epiq/SKILL.md`,
  which means a future `epiq_skill_install` reports the file as differing rather
  than identical — accepted deliberately.

Suites after the fixes, all exit 0, no skips, on the rebased tree: identity
22/22, fixture-snapshot 7/7, mounts 57/57, lifecycle 33/33, cache-clear 12/12,
agent 30/30, litellm 34/34, aws 9/9, concurrency 21/21 — 225 checks. The
litellm, aws and concurrency suites are the base's own and grew with it (agent
and litellm are larger here than before the rebase); they matter here because
the new target validation runs on every generation, including theirs.

## Follow-up review of that remediation — 2026-10-13

Host: macOS 27.0.0 arm64, Colima, Docker 29.5.2 server. Reviewing the four
`GF5Y28N` commits found the reserved-path guard incomplete, plus two smaller
holes.

- **Reserved paths were still reachable, silently.** The comparison used the
  emitted target string, while Compose cleans a target before mounting it.
  `--state x:/home/dev/.omp/../../../usr/local/bin` passed every check, and
  `docker compose config` then printed `target: /usr/local/bin` — a bind over the
  installed binaries, the exact failure the reservation exists to prevent.
  Targets with a `.` or `..` segment, with a doubled `/`, or equal to the
  container root (the ancestor of every reserved path, which the prefix
  comparison cannot see) are now refused before anything is written. Measured
  afterwards: those four refused, `x:/home/dev/.a..b` and `x:/home/dev/.omp/`
  still accepted, and the emitted file byte-identical to the previous generator
  for a valid invocation.
- **How loud the other shapes are (evidence correction).** The entry above said a
  colliding target was accepted by `config` and failed at `up`. Measured, the
  duplicate shapes are rejected by `docker compose config` itself
  (`target /home/dev/.omp already mounted as services.workspace.volumes[2]`) and
  the daemon rejects a `/` destination (`destination can't be '/'`); the
  ancestor — hiding — shapes are the ones nothing but the generator can see. The
  entry above is corrected accordingly, and the generator now refuses all of
  them earlier and with its own message.
- **Leftover-record window.** The `EXIT` trap was armed after the temporary file
  had been written and chmodded, so a failure in that window (ENOSPC, chmod
  denied) still left `identity.record.XXXXXX` in the state directory. The trap
  is armed immediately after `mktemp` now.
- **One name per emitted path.** `/opt/hestia/omp` and `/hestia/cache` were
  spelled both in the reserved list and in the emitted file; each is one
  variable now, so a later change cannot leave the reservation stale.
- **Fixture path spelling (test).** The mounts suite's collision probe compared
  the fixture path as written; it now resolves it with `pwd -P`, which is what
  the generator emits, so the probe cannot go vacuous on a host whose home
  traverses a symlink.

Suites after this follow-up, all exit 0, on this tree: identity 22/22,
fixture-snapshot 7/7, mounts 62/62 (five new checks: four refused spellings and
the no-file assertion), lifecycle 33/33, cache-clear 12/12, agent 30/30,
litellm 34/34, aws 9/9, concurrency 21/21 — 230 checks. As above, litellm's real
endpoint acceptance and aws authenticated inference are not run here.

## Second follow-up: PR #30 review findings — 2026-10-14

Host: Linux x86_64 cloud container, bash 5.2.21, no Docker daemon. Findings from
PR #30's reviewers (Codex, CodeRabbit, momus).

- **Trailing slash slipped past the ancestor check (Codex, CodeRabbit).** Real:
  `--state x:/usr/local/` exited 0 and emitted the bind, because the ancestor
  pattern became `/usr/local//*`, which does not match `/usr/local/bin`; the
  loader then mounts it at `/usr/local`. Same for `/home/dev/` over the mise
  toolchain. `state_target` now drops trailing slashes (the root keeps its
  own), so the comparison and the emitted file both use the cleaned path.
  Measured: `/usr/local/`, `/usr/local//`, `/home/dev/`, `/opt/hestia/omp/` and
  a `/home/dev/.one` + `/home/dev/.one/` pair refused; `/home/dev/.slash/`
  accepted and emitted as `target: '/home/dev/.slash'`. The default
  invocation's output is byte-identical to before.
- **"Refused before anything is written" was not true (Codex).** On a fresh
  `HESTIA_STATE_ROOT`, the identity helper ran before target validation and
  left the state directory and `identity.record` behind (reproduced: a refused
  `x:/usr/local/bin` left `<root>/<id>/identity.record`). The identity check now
  runs after every target is accepted; measured, the same refusal leaves the
  fresh root absent.
- **Untested boundary (momus).** The mounts suite gains nine checks for the two
  cases above: four trailing-slash reserved targets, the trailing-slash
  duplicate, no file written, a free trailing-slash target accepted and emitted
  clean, and a refusal on a fresh state root writing neither state nor file.

Verification on this host: identity 22/22 and fixture-snapshot 7/7, exit 0. The
mounts suite skips without Docker, so its nine new checks were run in isolation
against the generator and a scratch repository: 9/9. The full mounts suite and
the other Docker-backed suites were not run here.

## nono sandbox CLI layer — 2026-10-24 (implementation slice, not built)

nono ([github.com/nolabs-ai/nono](https://github.com/nolabs-ai/nono),
Apache-2.0) is added as a shared `nono` stage between `fixture-tools` and both
agent stages. Everything below was observed in a Linux x86_64 cloud session
(kernel 6.18.44, no Docker daemon), **not** on the Apple Silicon host: no
image containing this stage has been built, and nothing here is arm64 runtime
evidence.

- **Pin.** Release `v0.80.0` (tag commit `8bb041356d48`, binary dated
  2026-10-13), asset `nono-v0.80.0-aarch64-unknown-linux-gnu.tar.gz`, sha256
  `d2a24c8c37714f85c829b5586ffd81fc2acf336c95372d881ba62140884f22cb`. The
  downloaded tarball reproduced that digest and upstream's `SHA256SUMS.txt`
  lists the same value. It contains one file, `nono` (27,067,552 bytes, ELF
  aarch64), whose dynamic needs (`libc`, `libm`, `libgcc_s`, `libpthread`,
  `libdl`, `libutil`; symbols up to `GLIBC_2.18`) are all in bookworm-slim.
- **Provenance — not yet verified.** Upstream's `release.yml` builds the
  artifacts and attests them with `actions/attest` v4.2.2; a separate,
  manually run `attest-release.yml` can re-attest downloaded release assets. The
  build therefore accepts only a SLSA v1 bundle whose certificate names
  `release.yml`. This session could reach neither the GitHub attestations API
  nor Rekor (403 from the session's network policy), so neither the bundle
  count nor the certificate identity has been observed. The first
  `--target nono` build on the Mac is the first real verification; it fails
  closed if no bundle verifies.
- **Loop logic.** The bundle-trying loop was run with a stub verifier: a
  second-of-two good bundle, a single bundle without a trailing newline (after
  a fix to the loop's `read`), no good bundle, and an empty list behaved as
  accept, accept, reject, reject. Every `RUN` step parses under `sh -n` after
  Docker-style line joining.
- **Container syscall policy.** moby `docker-v29.5.2`'s default seccomp profile
  (`vendor/github.com/moby/profiles/seccomp/default.json`) allows
  `landlock_create_ruleset`, `landlock_add_rule`, `landlock_restrict_self`,
  `seccomp` and `close_range` unconditionally, and `clone` without namespace
  flags. Whether the macOS runtime's VM kernel enables Landlock is unobserved.
- **Behavior (x86_64 binary, same release, digest checked against
  `SHA256SUMS.txt`).** `nono setup --check-only` reported built-in profiles and
  `Installation verified!`. `nono run --allow <dir>` read and wrote inside
  `<dir>` and got `Permission denied` reading a file elsewhere in `$HOME`.
  Upstream source fails closed when Landlock reports `NotEnforced` and
  continues on `PartiallyEnforced`. With `NONO_NO_UPDATE_CHECK=1`,
  `nono --version` created nothing under `$HOME`; without it, an earlier run had
  written `~/.local/state/nono/update-check.json`.
- **Workspace state.** `workspace-compose.sh --state omp --state
  nono:/home/dev/.local/state/nono` exited 0 and emitted both binds; no
  generator change was needed.
- **Not run:** any image build, `nono` inside a Hestia container on any
  platform, an agent started under nono, and nono rollback/audit behavior
  across recreation.

## nono configuration review — 2026-10-24

Same cloud host as above (Linux x86_64, kernel 6.18.44, no Docker), nono
v0.80.0 x86_64 binary, scratch `HOME`; not a Hestia container. Findings feed
[nono best practices](nono.md).

- `nono profile list`: nine built-in profiles, none for omp, pig or Hestia
  paths. registry.nono.sh was unreachable from this session.
- `nono why` against a profile using the `enterprise` network preset:
  `bedrock-runtime.us-west-2.amazonaws.com`, `bedrock.us-west-2.amazonaws.com`
  and `sts.us-west-2.amazonaws.com` DENIED; `x.bedrock-runtime.amazonaws.com`
  ALLOWED. The preset's suffixes do not cover regional Bedrock hosts.
- `nono run --profile <file>` with `workdir.access: "readwrite"` and no TTY
  printed "Skipping CWD prompt (non-interactive)"; writing the checkout failed
  with `Permission denied`, and the diagnostic reported no path denials. With
  `--allow-cwd` the same write succeeded.
- A profile with `environment.allow_vars: ["PATH", "HOME", "TERM", "AWS_*"]`
  passed `AWS_REGION` and removed `PI_CONFIG_FILES` and `GIT_CONFIG_COUNT`.
- Allowing the checkout and denying `$WORKDIR/.env` exited 1: "Landlock
  deny-overlap is not enforceable on Linux. Refusing to start with conflicting
  policy."
- The example `hestia-omp` profile validated. A real run wrote the checkout
  and `~/.omp`, could not read `~/.ssh`, and kept `PI_CONFIG_FILES`. `why`
  results are listed in the best-practices page; `why` did not apply
  `workdir` access.
- **Not run:** omp under nono, real provider traffic through nono's proxy,
  rollback/audit across recreation, and anything on arm64 or in a container.

## Opt-in Pi, Pi-Bolt and Claude Code stages — 2026-10-24 (not built)

Same cloud host (Linux x86_64, no Docker daemon). Three sibling stages on
`nono`: `pi`, `pi-bolt`, `claude-code`. No arm64 image was built.

- **Pins (linux-arm64).** Pi `v1.4.0` `pi-linux-arm64.tar.gz`
  `fa5829c7ef83ffeaebba015715c8306220f89b2aa8a00154efbba98dd5440156`, matching
  upstream's unsigned `SHA256SUMS`. Pi-Bolt `bolt-v1.0.2`
  `pi-bolt-linux-arm64.tar.xz`
  `acca0a2c070ea2664884350e5a3cbf2afbdada3b1966130ce025065796cfbeb3`, matching
  its `SHA256SUMS`, whose Ed25519 signature verified with OpenSSL 3.0.13
  against the repository's `keys/release.pub`. Claude Code `2.1.308` (npm
  `stable` dist-tag) `@anthropic-ai/claude-code-linux-arm64`, tarball sha256
  `e939ff4445b9942fe04af0f2892e7052b48c09609b1b340ce7ac47c87db8619f`; its
  sha512 matches the registry integrity, and both registry ECDSA signatures
  over `name@version:integrity` verified against npm's key
  `SHA256:DhQ8wR5APBvFHLF/+Tc+AYvPOdTpcIDqOhxsBHRwC7U`. No npm provenance
  attestation exists for it. `downloads.claude.ai` (the native installer's
  host) was unreachable from this session.
- **Binaries.** All three arm64 executables are glibc ELF needing only core
  libraries (highest symbol `GLIBC_2.17` for Pi and Pi-Bolt, `GLIBC_2.26` for
  Claude Code, which also needs `librt`), within bookworm's 2.36.
- **Install steps.** Each stage's `RUN` text, extracted from the Dockerfile
  with paths redirected into a scratch tree and x64 assets/digests
  substituted, exited 0: digest checked, tree extracted (`--no-same-owner`),
  binary linked, `--version` matched, state directory created, no temporary
  files left, nothing written to the build user's home. A wrong digest stops
  at the check. Through a `/usr/local/bin` symlink, Pi and Pi-Bolt resolve
  `process.execPath` to the install tree and load their model data.
- **Runtime observations (x64 builds).** With update checks off, `--version`
  wrote nothing under `HOME` for any of the three. Without
  `CLAUDE_CONFIG_DIR`, Claude Code wrote `~/.claude.json` beside `~/.claude`;
  with it set, everything stayed inside that directory. `claude doctor`
  fetched remote settings and policy limits into the config directory.
- **Generator.** `/opt/hestia` is now reserved whole. In isolation:
  `/opt/hestia`, `/opt/hestia/{omp,pi,pi-bolt,x}`, `/opt`, `/opt/hestia/` and
  `/usr/local/bin` refused; `pi`, `claude`, `omp`, `pig`,
  `nono:/home/dev/.local/state/nono` and `x:/opt/other` accepted (14/14). The
  default output is unchanged. Identity 22/22, fixture-snapshot 7/7; the
  mounts suite skips without Docker.
- **Not run:** any arm64 build, any agent inside a container, authentication,
  assisted work, and session persistence across recreation.
