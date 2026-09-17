# Workspace mounts

[ADR-001](../docs/architecture.md) · Tickets `JP73P2D` `KSCDG1J` `24GJSHY` `HE2GM6N` `XJVWF4K` · [Mount tests](../tests/workspace-mounts.test.sh) · [Lifecycle tests](../tests/workspace-lifecycle.test.sh) · [Cache-clear tests](../tests/workspace-cache-clear.test.sh)

`workspace/workspace-compose.sh` generates a scoped Compose definition for one
checkout. It is a helper, not a Hestia command: the output is an ordinary
Compose file for `docker compose -f ... run workspace ...`.

## Usage

```sh
workspace/workspace-compose.sh [--image IMG] [--out FILE] <checkout-path>
docker compose -f <file> run --rm workspace <command>   # one-off command
workspace/workspace-lifecycle.sh start <file>           # persistent workspace
```

The generated service runs `sleep infinity` when started, so it stays
attachable; `compose run` overrides that for one-off commands.

## Fixture walkthrough

Run from the Hestia repository root in Bash on the exercised Apple Silicon
Mac with Docker/Compose running, host Git and mise available, and host Go
1.27.1 already installed through mise. Builds require network access. This
uses only synthetic source and a fresh directory under Docker-shared `$HOME`.
The fixture helper itself builds/tests on the host; its narrowly scoped
`MISE_TRUSTED_CONFIG_PATHS` deliberately trusts only this new synthetic tree.

```sh
set -euo pipefail
docker build --target fixture-tools -t hestia-fixture:walkthrough .
demo="$(mktemp -d "$HOME/hestia-demo-XXXXXXXX")"
fixture="$(TMPDIR="$demo" MISE_TRUSTED_CONFIG_PATHS="$demo" \
  fixtures/bin/make-fixture.sh | sed -n 's/^fixture ready: //p')"
compose="$demo/workspace.yml"
HESTIA_STATE_ROOT="$demo/state" workspace/workspace-compose.sh \
  --image hestia-fixture:walkthrough --out "$compose" "$fixture/repo"
workspace/workspace-lifecycle.sh validate "$compose"
workspace/workspace-lifecycle.sh start "$compose"
workspace/workspace-lifecycle.sh attach "$compose" bash -c \
  'mise trust && mise exec -- go build ./... && mise exec -- go test ./...'
# Finish active work before replacing the container.
workspace/workspace-lifecycle.sh recreate "$compose"
workspace/workspace-lifecycle.sh attach "$compose" bash -c \
  'mise trust && mise exec -- go build ./... && mise exec -- go test ./...'
fixtures/bin/fixture-snapshot.sh compare "$fixture/repo" "$fixture/snapshots/00-created"
workspace/workspace-lifecycle.sh stop "$compose"
```

For an interactive shell, use `workspace/workspace-lifecycle.sh attach "$compose"`
while running. Inspect a real repository's mise configuration before trusting it;
the explicit `mise trust` above is for this known fixture and is repeated after
recreation. The stopped runtime, cache volume and `$demo` remain available.
`fixture-tools` installs the fixture's pinned Go only: it does not discover or
install arbitrary mounted repositories' tools. This walkthrough proves neither
agent authentication nor Argus/Windows support; credentials are a separate
runtime concern below.

## Lifecycle

`workspace/workspace-lifecycle.sh` wraps the operations explicitly:

| Command | Behavior |
| --- | --- |
| `validate <file>` | Read-only preflight: recorded identity, Compose config and image present locally |
| `start <file>` | Preflight, then create and start detached |
| `attach <file> [cmd...]` | Shell (or command) in the running workspace |
| `stop <file>` | Stop; container, volumes and state retained |
| `remove-runtime <file>` | Remove the container; volumes and state retained |
| `recreate <file>` | Preflight before stopping/removing runtime, then start again — fails if the replacement container ID is not different |
| `clear-caches <file>` | Preflight, then remove only this workspace's `linux-caches` volume (name and declaration verified) and restart; durable state and source untouched |

The helper never runs `down -v`, prunes, or touches source, and the only volume it ever removes is the workspace's own `linux-caches` (via `clear-caches`, identity-verified).
All commands reject non-Hestia project names. `validate`, `start`, `recreate`
and `clear-caches` check durable identity, Compose config and local image before
mutation; a failed preflight leaves the existing runtime and caches alone.
`remove-runtime` also checks durable identity. These checks do not promise
recovery from a later Docker runtime failure.

Limits: recreation interrupts running processes — finish active work first
(`recreate` stops the workspace itself). Warm startup requires the image to
be present locally; startup never downloads or installs (preflight tells you
to build/pull explicitly). If the durable state directory
is lost, the workspace regenerates its `identity.record` on the next
generation; if a container disappears unexpectedly, `start` recreates it.
Published-port conflict validation arrives with project services; the
current workspace publishes no ports.

## What gets bound

- The checkout's canonical path (symlink-resolved) is bind-mounted at the
  identical path inside the container, so host tools and the container see the
  same source at the same location — host edits appear inside and container
  edits outside, and Git status/diff agree.
- When the checkout is a linked worktree, the common Git directory is bound at
  its identical path too: required metadata only. The main checkout's source
  is never mounted alongside (a worktree container sees its own tree plus the
  shared `.git` metadata, nothing else). Both absolute and relative gitdir
  links resolve because the host layout is preserved exactly; no Git pointers
  are rewritten.
- The Compose project name is the checkout's workspace id from
  [identity](../identity/README.md); Compose namespaces containers, networks
  and volumes from it, with no fixed container names.
- Durable workspace state lives in `HESTIA_STATE_ROOT/<workspace-id>`
  (default `~/.local/share/hestia/<workspace-id>`), bound at its identical
  path. Before generating, the directory's recorded identity is checked
  (identity helper `--state-dir`): state recorded for a different checkout is
  refused, and an unwritable state directory fails with an actionable error.
- Disposable Linux build/dependency caches live in a workspace-scoped Compose
  volume at `/hestia/cache` (`GOCACHE`, `GOMODCACHE`); the image pre-creates
  the directory dev-owned so a fresh volume is writable by the non-root user.
  Nothing mounts over mise's install directories, so image toolchain updates
  cannot be hidden by old state.
- Nothing else: no home or repository-collection mount, no host Docker socket,
  no credentials — by construction, asserted in tests.

Host and container UIDs differ, so the generated file sets git's
`safe.directory` through protected environment configuration, scoped to
exactly the mounted paths — no blanket trust.

## Failure behavior

Missing paths, non-checkouts, dangling or out-of-place `.git` pointers and
unreadable metadata fail with a clear error before anything is written; a
failed generation leaves no partial Compose file and never mutates the
checkout.

## Agent layer (omp)

The optional `agent` image target (`docker build --target agent .`) adds omp
(oh-my-pi) on top of `fixture-tools`, installed through mise and verified
against the pinned release digest. The provider policy
(`agent/omp/config.yml`: every built-in provider disabled except bedrock,
which uses the standard AWS credential chain) is baked root-owned at
`/opt/hestia/omp/config.yml` — outside the writable state tree — and loaded
as a config overlay via `PI_CONFIG_FILES`. omp merges global → project →
overlay → runtime overrides; a missing or malformed overlay fails startup.
The overlay shadows user settings without breaking omp's atomic settings
writes, unlike the superseded read-only bind over `~/.omp/agent/config.yml`.
It is not a security boundary against control of the process environment or
runtime overrides. Generate with `--image hestia-agent:<tag>` after explicitly
building that tag with the `agent` target.

omp's durable state — sessions (`--resume`), the `agent.db` database, its own
`~/.omp/agent/config.yml` settings (model selection, theme), memory, logs and
extracted natives — lives under `~/.omp`, which the generated Compose file
binds from the workspace state directory
(`<state-root>/<workspace-id>/omp`), outside source and build context. It
survives stop/remove-runtime/recreate like all durable state; `clear-caches`
never touches it.

Real AWS credential-chain authentication, agent-assisted work and native
session resume remain unverified; persisted settings/database/marker checks
are not that acceptance. Without AWS credentials, omp reports missing auth
while shell/source remain usable. Supply scoped credentials and any required
region/profile at runtime, separately from the image and generated Compose;
a profile name alone does not supply credentials inside the container. Git
authentication is separate. Never put credential values in images, generated
Compose, tracked files or logs; environment-supplied secrets are not hidden
from container inspection. `mise trust` is required per container and after
config changes; `~/.omp/natives` is extracted on first use into durable state.

## Limits

One writer per checkout at a time: host and container share the working tree
and index (ADR-001). Worktrees share Git metadata and are not mutually
untrusted boundaries. Full concurrent worktree workloads follow in
Milestone 3. Persistence and lifecycle are implemented, not concurrency proof.

## Verified

The [evidence log](../docs/evidence.md) records macOS arm64 fixture builds,
mount/write/worktree checks, lifecycle/cache preservation and omp
state/settings/overlay checks, including later review fixes. These are not
real AWS authentication or native-session-resume evidence. Fixtures must live
on Docker-shared paths on macOS (home, not the unshared `/tmp` path observed
in the recorded runtime). No broader platform support is established.
