# Concurrent repository evidence — CF62H3E

Observed on 2026-10-02: macOS 27.0.1 (26A434), Darwin arm64, Docker client
29.8.2/server 29.5.2, Compose 5.5.1. This is a synthetic technical proof;
Argus and authenticated agent acceptance remain separate.

Command: `rtk proxy env KEEP_ARTIFACTS=1 bash tests/workspace-concurrency.test.sh`.
Exit 0; **21 passed, 0 failed**, with no SKIP. Source baseline:
`a8fecc3d23b63b193937e6d4693caaafd8891c70`; tested suite SHA-256:
`803ccf4dd599b16e230a0a468048d0a9299a4c833217453ef1848a3f0da5282b`.

Canonical fixture image:
`hestia-fixture-tools:2026-09-09`,
`sha256:da4e08c28c507e8a9cd5913f15f2fda2fb2fa01dc9a836b4af2dea884edb46d1`,
linux/arm64. No image or project dependency installation was needed.

Two independent repositories named `repo` ran simultaneously on branches
`proof/a` and `proof/b`. Each received a distinct Go function/test, staged
change, unstaged change and untracked notes from its own container; each
passed `go build ./...` and `go test -count=1 ./...`. Host/container Git
status agreed and the source snapshots stayed unchanged after the probes.

| Resource | A | B |
| --- | --- | --- |
| Workspace | `hestia-repo-294a77a2f462` | `hestia-repo-83b308304a10` |
| Cache | `hestia-repo-294a77a2f462_linux-caches` | `hestia-repo-83b308304a10_linux-caches` |
| Network | `hestia-repo-294a77a2f462_default` | `hestia-repo-83b308304a10_default` |

Repository-group identities and containers were distinct. Effective bind mounts
were exactly each checkout, its identity-recorded state, and its own
`state/<id>/omp` at `/home/dev/.omp`. Cross-workspace source/state reads failed;
distinct durable, selected-agent-state and cache markers stayed separate. No
host home, repository collection or Docker socket was mounted. These workspaces
declare no project services or ports; Docker inspection confirmed no published
or exposed ports. Port-conflict handling was not exercised.

Local receipt root:
`~/.cache/hestia-concurrency-tests/hestia-concurrency-Q5oSCgPi`.
It contains generated Compose, identities, container IDs/inspection, build logs,
source/Git snapshots and environment/results. Both containers, networks and
test-owned cache volumes were removed; synthetic source/state receipts remain.

## Observed host metadata visibility limit

The first attempt passed 19 checks and failed two immediate host/container Git
status comparisons after the host snapshot operation replaced the live index.
No source/index loss occurred. A follow-up probe performed three byte-identical
host atomic index replacements: immediately, container `sha256sum .git/index`
returned ENOENT and Git listed zero entries while stat retained the old inode;
one second later the new inode, same SHA-256 and all five entries were visible.
This is an observed runtime filesystem visibility delay; its underlying driver
was not diagnosed. No instantaneous atomic-write visibility is claimed.

The suite copies the live index into receipt storage before invoking the
existing snapshot helper with `GIT_INDEX_FILE` and `GIT_OPTIONAL_LOCKS=0`.
This avoids observer writes to the shared index, rather than adding a delay to
hide a mismatch. Keep one writer per checkout and finish metadata operations
before handing work between host and container tools. The initial receipt and
probe are retained at
`~/.cache/hestia-concurrency-tests/hestia-concurrency-JK0gHgtP`.
Synthetic agent markers establish state scoping only; no authenticated model
call, native session or session resume was run.

## Review correction verification

At implementation commit `7ce22ae`, the isolation suite again passed 21/21,
exit 0, no SKIP; receipts are retained at
`~/.cache/hestia-concurrency-tests/hestia-concurrency-19cOXKjc`.
The suite now explicitly checks Python before runtime work and preserves
diagnostics on an early setup failure even before a check increments its
failure counter. A controlled missing-Python probe reported SKIP correctly
(this negative prerequisite check is not a runtime acceptance run). A mocked
pre-start failure exited 75 and retained its start log without needing
`KEEP_ARTIFACTS`; receipt ID `hestia-concurrency-S2NZ2Kve`. No additional
project/provider/platform support is claimed.
