# Synthetic build/test fixture

[Milestone 1](../docs/milestone-1.md) evidence stage 1A · Ticket `SKSJTMN` · [Architecture](../docs/architecture.md)

A small nonproprietary project plus the helpers that instantiate it in fresh,
uniquely named temporary storage. It exists so Hestia's image, mount, identity
and lifecycle work can be verified against a real build/test and real Git state
without ever using personal or employer repositories.

## Layout

- `synthetic/` — the template project: a Go module with a library, a command,
  and a test, declaring its toolchain in `mise.toml` (Go 1.27.1, pinned from
  `mise ls-remote go` on 2026-09-09).
- `bin/make-fixture.sh` — creates one fixture instance: a fresh root directory
  (unique `hestia-fixture-XXXXXXXX` name), the main checkout with one commit
  plus staged, unstaged and untracked changes, two linked worktrees (`wt-abs`
  with Git's default absolute gitdir link, `wt-rel` with relative links), a real
  `go build`/`go test` run through mise, and a first snapshot. Everything the
  run prints lands in the instance's `FIXTURE.txt`.
- `bin/fixture-snapshot.sh` — records the durable state of a fixture checkout
  (working-tree blob hashes for every tracked and untracked file, index listing
  and tree, HEAD commit/tree/branch, full porcelain v2 status, worktree list),
  or compares current state against an earlier snapshot and fails on drift.

## Use

```sh
fixtures/bin/make-fixture.sh                     # prints the instance root
fixtures/bin/fixture-snapshot.sh capture <repo-dir> <out-dir>
fixtures/bin/fixture-snapshot.sh compare <repo-dir> <snapshot-dir>
```

Cleanup is always exactly `rm -rf <instance-root>`: every resource the fixture
creates — repositories, worktrees, branches, snapshots — lives under that root,
so cleanup can only touch what this fixture made.

## Verified

2026-09-09, macOS 25.6.0 arm64, mise 2026.9.3, Go 1.27.1 via mise: fixture
created, relative worktree links resolved without repair, build and test passed
inside the dirty tree, snapshot captured and a no-change `compare` came back
clean. Hestia containers have not run this fixture yet; that starts with the
image work (`61Q7E8F`).

These are fixture helpers, not Hestia commands; Hestia has no CLI.
