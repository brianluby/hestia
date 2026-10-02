# 4AC12YE: Apple Silicon foundation proof

[Milestone 1 contract](milestone-1.md) · [Native acceptance procedure](agent-acceptance.md) · [Machine-readable result](m1-apple-silicon-result.json)

Observed 2026-10-02 on macOS 27.0.1/Darwin 27.0.0 arm64, Docker client
29.8.2/server 29.5.2, Compose 5.5.1. This receipt covers the nonproprietary
foundation only. **4AC12YE remains incomplete:** actual LiteLLM inference,
agent-assisted changes and saved-session resume after recreation have not run.
The user authorized use of the dedicated local-system key; automatic approval
review still requires confirmation naming the exact configured destination.
No actual key was accessed, stored or transmitted.

Tested source: `fccd1bd6cafd7d0410d1886742ea5dea7264f8c0`, stacked on PR19/PR18.
The canonical Dockerfile and helper hashes are in the JSON receipt.
Canonical optional-agent image `hestia-agent:4ac12ye-20261002`, linux/arm64:
`sha256:894c7b78bdaa29cfd29f65e243b15b4c4a31941bfc1faf36d45c346ff31721a2`. Native versions: mise 2026.9.4, Go 1.27.1, omp 18.1.16.
The observed Go version is the resolution of the existing declaration; this
receipt adds no pin or broader architecture claim.

## Requirement results

| Requirement | Result | Observed evidence |
| --- | --- | --- |
| M1-01 | PASS | Explicit canonical cold and cached builds; pinned mise/cosign checksums, mise attestation `Verified OK`, pinned omp checksum; real host/container fixture builds/tests. |
| M1-02 | PASS | Scoped source/state/omp/cache mounts, no host socket or published ports; host and container writes visible both ways, Git status equal; mount suite checks sibling-source exclusion. |
| M1-03 | PASS | UID1000 writes source/native settings/cache; native atomic settings persistence succeeds; Linux artifacts stay in the classified cache volume and host artifacts use separate storage. |
| M1-04 | PASS | 19 identity checks cover matching basenames, linked worktrees, branches, symlinks and recorded-identity conflicts. |
| M1-05 | PASS | 31 mount checks include actual staging through absolute/relative Git links, unchanged pointers and rejected unsupported layouts. |
| M1-06 | PARTIAL | 32 lifecycle checks and the selected-state cache/recreation observation pass; real authenticated JSONL-session fidelity/resume remains NOT RUN. |
| M1-07 | NOT RUN | Native real-provider edit and explicit saved-session resume require the pending exact-destination confirmation. Protocol/stub evidence is not substituted. |
| M1-08 | PASS | Own cache file counts 1098 → 0 → 1097; source/Git/raw index and all11 selected native-state files unchanged; rebuilt Go tests pass. Existing12-check suite also preserves an unrelated sentinel volume. |
| M1-09 | PARTIAL | Missing checkout, unsupported metadata, unwritable state, identity conflict, missing image and malformed Compose reject in existing suites. Actual unavailable Go1.999 rejects under GOTOOLCHAIN=local, exact source/index restored. Permission denial and failed download pass below. Real denied/expired auth and recovery remain NOT RUN. Port conflicts are N/A for this fixture with no published ports/services. |

## Commands and timing

All shell invocations used `rtk`. These are actual wall-clock diagnostics,
including helper preflights; no speed threshold or reproducibility claim.

- `rtk proxy docker build --no-cache --target agent -t hestia-agent:4ac12ye-20261002 .`: exit0, **109.601s**. Existing legacy builder; buildx unavailable. The initial `--progress=plain` attempt exited125 before building and is not counted as a successful cold build.
- Same canonical build without `--no-cache`: exit0, **0.647s**.
- Fresh home-cache fixture `workspace-lifecycle.sh start`: exit0, **0.732s**; stop then start retains its container, warm start **0.804s**.
- `rtk proxy env KEEP_ARTIFACTS=1 bash tests/fixture-snapshot.test.sh`: **7/7**.
- Same invocation for `workspace-id.test.sh`: **19/19**; `workspace-mounts.test.sh`: **31/31**; `workspace-lifecycle.test.sh`: **32/32**; `workspace-cache-clear.test.sh`: **12/12**. All exit0, **101 total passed, 0 failed, no SKIP**. Foundation runtime suites retain their own existing fixed image tags; they are not attributed to the newly built agent image.

The new image's own fixture started at container
`1f0bd86a454ad033380a5eb0d0ea653d1cc616e36f17bf18d10a5bd9db656bdb`;
scoped cache clearing recreated it as
`b4906a87bef0d22d4d774e33d6349f397a3ba8c548543251b33aa93d2fcc75c5`.
Source/index/tree/HEAD/branch/status/untracked/worktree listings were captured
with a copied `GIT_INDEX_FILE` and `GIT_OPTIONAL_LOCKS=0`; the real index was
hashed independently. Hashing selected native files establishes byte fidelity,
not authenticated session acceptance.

## Failure observations and limits

A disposable container-local Git fixture under UID1000 denied a direct HEAD
read at metadata mode000 (exit1, Permission denied) and Git status (exit128).
Restoring the mode restored Git (exit0) with identical source/state/status.
Git itself reported a generic not-a-repository error; the direct read supplied
the permission diagnostic. This is not host-bind permission evidence.

A separate owned image alias initially pointed to the working image. The
canonical base build with a deliberately unavailable non-secret MISE_VERSION
failed at the first download (exit22,16.286s). The alias/protected image ID,
running fixture container and source/state bytes/modes/ownership were unchanged.
Only the owned alias, failed-build intermediate and disposable projects were
removed.

`/private/tmp` bind diagnostics failed visibility or mapped writable host files
as root-owned inside the container. Those failed attempts are retained and not
credited. The successful host-bind proof uses a unique home-cache fixture,
the same placement used by the existing suites. No host chown/chmod workaround
or broader source/home/socket mount was introduced.

## Remaining acceptance

After exact endpoint authorization, discover an explicit available model using
the corrected runtime key held only in process memory. Use the existing
LiteLLM helper and native read/edit permissions for a small test-backed change;
review the actual diff and build/test independently. Stop active work, snapshot
source/Git/raw index plus the actual nonempty JSONL/session header/settings,
recreate and require zero differences **before** native resume. Resume that
explicit existing JSONL, verify retained conversation context, make a second
test-backed change and build/test again. Require completed native assistant
events and actual write tools, rather than JSON-mode exit0 alone. Verify denied
auth leaves shell/source usable, fresh runtime handoff recovers, and no key
appears in source, Compose, selected state, image/container configuration or
evidence. Raw model catalogs/transcripts remain private.

Neither this partial receipt nor eventual fixture acceptance closes the
employer-local Argus pilot or Milestone1. Windows/WSL2 is not exercised.

Private receipts: `/private/tmp/hestia-4ac12ye-build`,
`/private/tmp/hestia-4ac12ye-regressions`,
`/Users/bluby/.cache/hestia-m1-proofs/run-enryxux3`, and
`/private/tmp/hestia-m109-negative-EBYiv4sR`. The one-off runtime harnesses are
kept outside the repository; production uses the existing Compose/mise helpers.

Final cleanup: project `hestia-repo-ce0a9e169ec7` has no remaining containers (Compose ps -aq empty, exit0) or cache volume (inspect exit1). Source/Git and selected native state remain byte-identical and are retained privately for the pending authorized continuation. The image is retained. The primary checkout's original Dockerfile/runbook diff remains unchanged (SHA-256 `ac597c98e92f67fd5ff1df53079fe238e73d2dd7b8f8bbe6eb2bffb48e95e5b8`).
