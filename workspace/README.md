# Workspace mounts

[ADR-001](../docs/architecture.md) · Ticket `JP73P2D` · [Tests](../tests/workspace-mounts.test.sh)

`workspace/workspace-compose.sh` generates a scoped Compose definition for one
checkout. It is a helper, not a Hestia command: the output is an ordinary
Compose file for `docker compose -f ... run workspace ...`.

## Usage

```sh
workspace/workspace-compose.sh [--image IMG] [--out FILE] <checkout-path>
docker compose -f <file> run --rm workspace <command>
```

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

## Limits

One writer per checkout at a time: host and container share the working tree
and index (ADR-001). Worktrees share Git metadata and are not mutually
untrusted boundaries. Full concurrent worktree workloads follow in
Milestone 3; persistent state mounts and lifecycle behavior are separate
tickets.

## Verified

2026-09-09, macOS 25.6.0 arm64 (Docker server 29.5.2, fixture-tools image):
`tests/workspace-mounts.test.sh` passed 29/29 — including host/container
status agreement, edits visible in both directions, staging inside containers
for both worktree link layouts without pointer changes, no sibling source or
Docker socket visible, out-of-bind paths invisible, clear no-mutation
failures, a real in-container `go build`/`go test` on mounted source that
leaves the tree byte-identical (artifacts only in the cache volume), a native
host build on the same source with the same result, unwritable-state and
state-mismatch rejections. Fixtures must live on Docker-shared paths on macOS (home, not
`/tmp`, which mounts empty — see the [evidence log](../docs/evidence.md)).
