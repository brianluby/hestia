# Durable fixture backup and restore

[Architecture](architecture.md) · [Roadmap](roadmap.md) · Tickets `B6J27FG` and `R3N7X5F`

Use one tar archive with a separate JSON manifest and SHA-256 checksum. This is
an explicit fixture procedure, not a general backup service. Container
persistence does not protect against storage loss; keep an independently stored
copy and exercise restoration before relying on a backup.

## Select the data first

| Data | Capture and sensitivity |
| --- | --- |
| Main and linked source | Raw tracked, staged, unstaged, deleted and untracked work; preserve file modes and symlink targets. Source can contain confidential material or secrets, even when ignored by Git. |
| Common Git directory | Entire selected repository metadata, including objects, refs, reflogs, config and each linked worktree's index/HEAD/link metadata. Inspect local config/hooks for embedded secrets first. A Git bundle or `git archive` alone omits dirty work and per-worktree indexes. |
| Selected agent state | Explicitly reviewed non-secret preferences and synthetic session state in this proof. Never recursively copy `~/.omp`, a host home, credentials, or an auth database. Real sessions may contain prompts, source and credentials and require separate review. |
| Service data | None in this Go fixture. For a real service, use its supported consistent dump or shut down before a data-volume copy, then verify its restore with that service. |
| Relocation records | Original canonical checkout/common/git paths, workspace and repository IDs, checkout-to-agent-state mapping, captured image ID, timestamp and selected relative archive paths. Paths and Git remote URLs can themselves be private. |
| Verification | Per-file SHA-256/size/mode or symlink target, archive SHA-256, each checkout's raw-source/index/HEAD/branch/status snapshot and original worktree relationships. |

Exclude each workspace's `linux-caches` Docker volume, native source-tree build
caches/output, extracted `omp/natives`, runtime containers/networks, generated
Compose and old `identity.record`. Those records describe the old location;
keep their identity values in the manifest for comparison, then regenerate them
at the destination. Exclude credential files, auth databases and tokens and
reauthenticate at runtime. Do not infer that arbitrary ignored files are either
safe to exclude or safe to back up: classify the selected tree explicitly.

The synthetic archive is classified non-secret and requires no encryption. If
any selected data contains secrets — source, Git config/hooks, sessions or
database state — stop before producing a plaintext backup. Exclude those
secrets and prefer reauthentication where possible. If sensitive data must
remain in the backup, choose user-controlled encryption and
recovery keys, encrypt the archive and its sensitive manifest during capture,
and verify decryption/restore in an isolated location. Encryption, reauthentication
and native session restoration are not exercised by the synthetic proof.

## Capture a consistent set

1. Record the selected checkouts and their `git rev-parse --path-format=absolute
   --git-common-dir` / `--git-dir` results. Enumerate `git worktree list
   --porcelain` and include every selected linked checkout with its shared metadata.
2. Finish builds and agent/Git operations, stop the selected workspace containers,
   and stop or dump applicable services. Coordinate all writers sharing the common
   Git directory; stopping one worktree alone is insufficient. Keep them stopped
   until hashes, tar capture and verification finish. The fixture has no services
   or background host writers, and explicitly checks both containers stopped.
3. Snapshot every checkout with `fixtures/bin/fixture-snapshot.sh`. Stage only the
   approved source/common/linked metadata and selected state into a fresh private
   directory. Keep staging/archive outside the source and image build context.
   Inspect the member list against the inclusion/exclusion decision.
4. Write the manifest over the staged bytes, then create the tar without following
   symlinks. Hash the finished archive. Check source snapshots again, extract a
   verification copy, and compare every archived file, mode and symlink against
   the manifest. Reject a missing/extra/changed member or checksum mismatch.
   A checksum detects corruption; it provides no authenticity without a trusted
   separately retained receipt.

These operations do not constitute online consistency for an actively changing
checkout or database. Snapshot/hash disagreement invalidates capture; quiesce
again and recapture rather than accepting a partial archive.

## Restore into fresh storage

1. Verify the archive checksum against the trusted receipt before extracting into
   an empty, isolated destination. Verify extracted bytes and permissions against
   the manifest before starting tools or changing Git links. Keep the original
   source/state available for recovery but never run relocation repair against it.
2. When both main and linked checkouts move, run supported
   `git -C <restored-main> worktree repair <restored-linked>...`. Git documents this
   operation for relocating both ends; do not rewrite pointer files manually.
   Check every checkout's resolved common/git directory and worktree list now
   points only into the restored root. Shared metadata remains shared.
3. Compare raw source, index listing/tree, HEAD/branch/status and branch refs.
   Compare the worktree listing with only the recorded source-root-to-destination
   translation. The expected Git relocation changes are the `.git` pointer and
   common metadata `worktrees/*/gitdir`; other durable work must agree.
4. Generate new Compose files using `workspace/workspace-compose.sh` and a fresh
   absolute `HESTIA_STATE_ROOT`. Require different workspace/repository identities,
   inspect their new records, and explicitly copy approved agent payloads into
   their mapped new workspace state directories. Never replay saved Compose or
   overwrite new identity records with old ones.
5. Start fresh containers, require different container IDs and initially empty
   cache volumes, deliberately trust the inspected fixture mise declaration, then
   run real `mise exec -- go build ./...` and `mise exec -- go test ./...` for
   each checkout. Require rebuilt caches and compare source/state again. Restore
   real runtime credentials through their separate supported handoff when needed.

Run the self-contained fixture from the Hestia checkout on a Docker-shared path:

```sh
rtk proxy env KEEP_ARTIFACTS=1 python3 tests/workspace-backup-restore.test.py
```

It requires host Git/Python (with tar extraction filters), reachable Docker and
Compose, and the existing canonical `hestia-agent:2026-09-10` image. It performs
four real builds/tests: both original checkouts and both restored checkouts.
Missing Docker/image is a failure; a reported prerequisite `SKIP` is not an
executed proof. `HESTIA_TEST_IMAGE` and `HESTIA_TEST_ROOT` can explicitly select
another prebuilt canonical image and Docker-shared synthetic storage parent.
Only the run's four uniquely identified Compose projects and cache volumes are
removed. With `KEEP_ARTIFACTS=1`, the tar, manifest, checksum, source copies,
snapshots and command/exit receipt remain in the printed private fixture root.
Without it, those synthetic artifacts are removed after a successful run.
The extraction safety filter changes regular-file permissions; the fixture
reapplies recorded non-symlink modes before checking fidelity. Owner IDs, ACLs,
extended attributes and service-specific restore are outside this proof.

The [executed fixture receipt](evidence/backup-restore-2026-10-02.md) records the
78-check capture and fresh restore proof for `B6J27FG` / `R3N7X5F`.
This procedure proves selected synthetic state fidelity; it does not establish
native authenticated omp session resume, Argus compatibility, Windows/WSL2
support, or completion of the earlier native-agent milestone.

Primary references: [Git worktree repair and metadata](https://git-scm.com/docs/git-worktree),
[Docker volume lifecycle](https://docs.docker.com/engine/storage/volumes/), and
[Python tar archives](https://docs.python.org/3/library/tarfile.html). Tar/checksums
are the transport in this fixture; application-specific recovery remains a
separate acceptance test.
