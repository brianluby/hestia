# Linked-worktree terminal proof — M9FMY5V

**Partial acceptance.** Concurrent terminal edits/builds, scoped native omp
state initialization, Git operations and recreation passed. Authenticated
agent-assisted changes and native session resume were **not run** in this
receipt, so this ticket is not complete.

Observed on 2026-10-02: macOS 27.0.1 (26A434) arm64, Docker client
29.8.2/server 29.5.2, Compose 5.5.1. Command:
`rtk proxy env KEEP_ARTIFACTS=1 bash tests/workspace-concurrency.test.sh worktree`.
Exit 0; **55 passed, 0 failed**, no SKIP. Baseline:
`f1377577b9b3e7e94d275914386722ff71c18e7d`; tested suite SHA-256:
`592ca29c97d6152b2743ff2e33d028dd1f3f2c111ebd546919b033026bd7dfb1`.
Canonical agent image:
`hestia-agent:2026-09-10`,
`sha256:9c7150a7fefd9b35463199896bc080ff37e64100ea0821332d651761b112b026`
(linux/arm64, `omp/18.1.16`). No build or image install was needed.

The main checkout `a/repo` and linked worktree `b/repo` used intended branches
`proof/a` and `proof/b`. Both edit/build/test commands launched before either
was awaited. Each added a branch-specific Go function and test, staged its
library edit, and retained separate unstaged and untracked work. Both passed
`go build ./...` and `go test -count=1 ./...`; staged diffs and
host/container status agreed. They shared the repository-group identity and
canonical common Git directory, but had distinct workspace resources.

Native `omp --version` and `omp config get disabledProviders` ran separately
in each workspace and initialized separate `omp/agent/agent.db` files. No
placeholder session files were created. Distinct state/cache markers and native
database paths demonstrate state scoping, not inference or native session use.

| Container | Before | After |
| --- | --- | --- |
| Main, `hestia-repo-b545d59f002d` | `0275f962da6939679d1094d2ed0b47fa1534e282e9babba0b7e3fbfa1ede508b` | `371461f2271e5085764420052d649354daa53ce4596c79eaa5a70226d770874b` |
| Linked, `hestia-repo-8b0f6443842f` | `56b1a295406764264da604caa780db5fcd2b325c5319b5bf03a38e1e32b04645` | unchanged |

During main-workspace recreation, the linked worktree continued real builds
and uncached tests: success events rose from 1 to 33. It retained its container,
cache and network identity. After recreation the main built/tested again.
Both source/Git snapshots and selected-state SHA-256 manifests compared
unchanged; branches, staged diffs and common metadata still resolved. The linked
worktree's `.git` pointer bytes stayed unchanged.

Effective mounts were each checkout, its scoped state and its own omp state;
the linked workspace additionally mounted only the main checkout's `.git`
directory at its canonical path. It could not read main source. No broad home,
repository collection or Docker socket was mounted. Shared Git metadata remains
shared writable user data, and worktrees are **not mutually untrusted security
boundaries**. This run used Git's absolute linked-worktree layout; it does not
add concurrent relative-link acceptance.

The final suite also passed both independent-repository controls, with the same
baseline and suite hash: isolation **21/21**, recreation **38/38**, each exit 0.
The earlier [isolation](concurrency-evidence.md) and
[neighbor recreation](neighbor-recreation-evidence.md) receipts remain unchanged.

| Retained synthetic receipt | Local root |
| --- | --- |
| Linked-worktree final proof | `/Users/bluby/.cache/hestia-concurrency-tests/hestia-concurrency-nqSf5VPG` |
| Final isolation control | `/Users/bluby/.cache/hestia-concurrency-tests/hestia-concurrency-y1xS5mqw` |
| Final recreation control | `/Users/bluby/.cache/hestia-concurrency-tests/hestia-concurrency-UGxjg8fZ` |

Each contains Compose definitions, identity records, exact container IDs and
inspection, source/Git snapshots, selected-state hashes and actual command logs.
Test-owned containers/networks/caches were removed; synthetic source/state
remains reusable. The copied-index observation method and observed host atomic
metadata visibility delay are described in the isolation receipt.

Remaining acceptance: supply the user-authorized scoped provider access,
complete real authenticated terminal-agent changes in both intended branches,
build/test those changes, capture actual native session state, recreate one,
resume that native session or documented native equivalent, and compare durable
state before resumed work. The user has since authorized a local
LiteLLM/OpenAI-compatible endpoint as an alternative to Bedrock; no authenticated
call to it is represented by this receipt. Argus/Windows acceptance is separate.
