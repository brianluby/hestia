# Neighbor recreation evidence — 3B36AE6

On 2026-10-02, macOS 27.0.1 (26A434) arm64, Docker client 29.8.2/server
29.5.2, Compose 5.5.1. Extends the [independent repository proof](concurrency-evidence.md).

Command:
`rtk proxy env KEEP_ARTIFACTS=1 bash tests/workspace-concurrency.test.sh recreate`.
Exit 0; **38 passed, 0 failed**, no SKIP. Source baseline:
`1bf0e88e3cb4146765a1d38d6c3b6e34297dcd30`; tested suite SHA-256:
`48da112034a2c7aac878e08603e3efe0257c9f083f79cfa8ad4a59b52ef5048b`.
Image:
`sha256:da4e08c28c507e8a9cd5913f15f2fda2fb2fa01dc9a836b4af2dea884edb46d1`
(`hestia-fixture-tools:2026-09-09`, linux/arm64).

Both independent repositories contained staged, unstaged and untracked edits.
Both had distinct selected durable state and disposable caches. After snapshots,
B repeatedly ran `go build ./...` and `go test -count=1 ./...`, recording
a success event only after both completed. While B continued, the existing
lifecycle helper recreated A. Success events rose from 4 to 44 during the
11-second recreation interval; B's loop was still active afterwards and exited
successfully when explicitly finished. The loop is bounded at 120 iterations.

| Container | Before | After |
| --- | --- | --- |
| A, `hestia-repo-a65aaceb2b83` | `2edb17b8a8a1bb67ba4c068958763d9e5a8aabbc0eff4472dd4465131c7aa855` | `8f8217f63bcff4ca80f04f4a1d3933f9f3e0142549910a008f8775bae8b9c657` |
| B, `hestia-repo-575fc0183241` | `83e36ba5e992c0539159de1a42a8114a467ae800eff4b87ae738b326b29a6bba` | unchanged |

A rebuilt and tested successfully after recreation. Both complete source/Git
snapshots compared unchanged: working bytes, index entries/tree, HEAD/branch,
status including untracked work and worktree registration. All files in the
synthetic selected state directories had unchanged SHA-256 manifests. Both cache
volumes retained their creation time/mountpoint; B retained its network ID.
Final host/container Git status agreed for both. No real agent inference or
native session resume is established by these synthetic state markers.

Receipts:
`/Users/bluby/.cache/hestia-concurrency-tests/hestia-concurrency-kYMSxnWi`.
They include timestamped progress, recreation log, before/after Docker inspect,
source/state snapshots, cache identities and build/test logs. Cleanup verified
the two test-owned containers, networks and cache volumes were removed; durable
synthetic fixtures and receipts remain. No global prune or unrelated resource
deletion was used. The host metadata visibility limit and copied-index
observation method are documented in the independent proof.
