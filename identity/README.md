# Workspace identity

[Architecture ADR-002](../docs/architecture.md) · Ticket `503RD0P` · [Tests](../tests/workspace-id.test.sh)

`identity/workspace-id.sh` derives the resource identity for a checkout. It is
a helper, not a Hestia command: Compose receives the derived value as the
project name and namespaces containers, networks and volumes from it, so no
container or volume carries a fixed global name.

## Interface

```sh
identity/workspace-id.sh [--state-dir <dir>] <checkout-path>
```

Prints `canonical:`, `repo-group:` and `workspace:` lines on success. Exit 0 on
success, 1 on a validation or record mismatch error, 2 on usage errors. With
`--state-dir`, the first run writes `identity.record` under that directory;
later runs verify the recorded full path and ids before allowing reuse.

## Exact encoding

- **Canonical path:** `git rev-parse --show-toplevel` from the checkout,
  then physical resolution with `cd && pwd -P`. Symlink aliases therefore
  collapse onto one identity (including the `/var` → `/private/var` alias on
  macOS).
- **Label:** the basename of the canonical path, lowercased, characters kept
  from `[a-z0-9]`, every other run collapsed to one dash, leading/trailing
  dashes trimmed, truncated to 24 characters, `repo` when nothing survives.
- **Hash:** the first 12 lowercase hex characters of `sha256` over the
  canonical path string in UTF-8 with no trailing newline.
- **Form:** `hestia-<label>-<hash>` — at most `7 + 24 + 1 + 12 = 44`
  characters, matching `^hestia-[a-z0-9][a-z0-9-]{0,23}-[0-9a-f]{12}$`.
- **Repo group:** the same construction over the resolved
  `git rev-parse --path-format=absolute --git-common-dir` (git >= 2.31), with
  the label taken from that directory's parent, which is the main checkout for
  normal repositories and their linked worktrees. A main checkout and its
  worktrees therefore share a repo-group id while keeping distinct workspace
  ids.

Docker's Compose documentation requires project names to contain only
lowercase letters, decimal digits, dashes and underscores and to begin with a
lowercase letter or digit; it documents no maximum length. The form above
satisfies those rules and the 44-character bound is Hestia's own headroom for
resource names Compose derives from it.

## Stability and reuse

Identity derives from the canonical checkout path only, so branch, tool, agent
or workspace-variant changes preserve it, while moving or copying the checkout
changes it. Because names can collide while paths do not, the full canonical
path is recorded in the state directory and checked before any reuse: a
recorded path that differs from the current canonical path fails with a clear
error instead of reusing the state, and a recorded id that differs from the
derivation fails as a collision. Old state is never rewritten by these
failures, so a moved checkout's previous state survives for explicit,
validated reattachment. Twelve hex characters (48 bits) keep accidental
collision odds negligible for the local scale this identity serves; the record
check turns even a real collision into a hard failure rather than silent
reuse.

## Verified

2026-09-09, macOS 25.6.0 arm64, git 2.55.0: `tests/workspace-id.test.sh`
passed 14/14 — form and length bounds, sanitization and truncation, distinct
ids for matching basenames at different paths and for a main checkout versus a
linked worktree with a shared repo-group, branch-switch stability, symlink
aliasing, clear failures for non-checkouts and missing paths, record
write/verify, moved-checkout rejection with the old record intact, and a
forged-record collision failing before reuse.
