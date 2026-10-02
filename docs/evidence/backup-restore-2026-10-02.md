# Fixture backup and fresh restore receipt, 2026-10-02

[Procedure](../backup-restore.md) · Tickets `B6J27FG` / `R3N7X5F`

Executed on macOS arm64 (`Darwin 27.0.0 arm64`), host git version 2.56.0, Python 3.14.8, Docker Engine 29.5.2 aarch64, Docker Compose version 5.5.1.
Existing canonical optional agent image `hestia-agent:2026-09-10`, `sha256:9c7150a7fefd9b35463199896bc080ff37e64100ea0821332d651761b112b026 arm64`. Runtime Go reported `go1.27.1 linux/arm64`.

Tested Hestia commit: `7d8d27465a4bf513971da120f13430ce0c832512`. Test source SHA-256: `1f1954228ce889db56d69573f8d29b491437a28b08b80195026458263857e5df`.

```sh
rtk proxy env KEEP_ARTIFACTS=1 python3 tests/workspace-backup-restore.test.py
```

Exit **0**, **78 passed / 0 failed**. Four real Go build/test runs succeeded: original main and linked checkout, then both restored checkouts. The 72 recorded subprocess commands, including own-resource cleanup, all exited 0.

## Capture and relocation results

- Both original containers were verified stopped before capture; this fixture has no services or other writers.
- Source and complete common/linked Git metadata bytes and modes remained equal across capture. Both raw indexes were archived; staged, unstaged, deleted, binary/Unicode untracked and ignored durable notes were included. Symlink targets and file modes were checked.
- Explicitly selected non-secret preferences and synthetic session payloads were captured for each workspace. Synthetic auth-database, extracted-native and source-cache exclusion sentinels were left out, along with Docker cache volumes, Compose and old identity records.
- The tar contained 123 manifest members (71 files, 50 directories, 2 symlinks). Archive SHA-256: `68894f4504369c83cda95c29c4ef5cbe59e48259b7cfee5b3efa170f326428c8`.
- Fresh extraction matched every manifest entry. A deliberate raw-byte corruption failed manifest equality; restoring those bytes returned equality. Python data-filter mode normalization was corrected by explicitly restoring recorded non-symlink modes.
- Original source paths were made unavailable by renaming only this fixture source root. Supported `git worktree repair` relocated the restored main/linked association; exactly the linked `.git` and common `worktrees/linked/gitdir` pointers changed. Branch refs, raw source, index listing/tree, HEAD/branch and status remained equal. Worktree listing changed only by the recorded root translation.
- Fresh Compose and state identity records were generated at restored paths; both workspace IDs and the common repository ID differed from the original location. State payloads were explicitly mapped into the new IDs. Both restored containers had different IDs.
- Both restored Linux cache volumes initially had **0 files**, then **1,103 files** after successful real builds/tests. Container Git staging succeeded in both checkouts, then all snapshots and selected state still matched. Ignored durable notes also matched after build.

| Checkout | Original workspace | Restored workspace | Cache files |
| --- | --- | --- | --- |
| main | `hestia-repo-0832553821d4` | `hestia-repo-82947c829cd2` | 1,103 → 0 → 1,103 |
| linked | `hestia-linked-e710f1e9100d` | `hestia-linked-651accce26d1` | 1,103 → 0 → 1,103 |

Container identities:

- main: `b7b24a1a85acd4ab8dc3ff59b072c5e2ffcf3d8ce2b01d59365a68d5abdebe9b` → `5089c1939688411cb374584fcff93183164bf6e6120d8b6c73d7c743df04214b`.
- linked: `cab12f8de1157daa9eaaf09c285aec598a97b01138418246bc9829241efd0968` → `d0a115ac76defc8a90c8b7550caf64b3bc18c0e242550eea401eac55848a450e`.

All four own Compose projects/containers/networks and their four named disposable cache volumes were removed; every cleanup command exited 0. The non-secret archive, manifest, checksum, restored/source copies, snapshots and full command/exit receipt remain under:

`/Users/bluby/.cache/hestia-backup-tests/hestia-backup-4x9ahugm`

The receipt is `evidence/receipt.json`; the archive and manifest are `durable.tar.gz` and `manifest.json`. They are retained in private synthetic test storage and are not committed to the repository.

The existing byte-fidelity regression suite `rtk proxy bash tests/fixture-snapshot.test.sh` also passed **7/7**, exit 0. Python AST parsing and `git diff --check` passed.

## Acceptance boundary

This closes the narrow fixture capture and restoration proof with selected non-secret state. It does not exercise native authenticated omp session resume, reauthentication, mixed-secret encryption, real service restore, Argus, Windows/WSL2, ownership IDs, ACLs or extended attributes. No real host preferences, sessions, credentials or employer source were inspected or copied. Earlier native-agent/worktree milestone acceptance remains separate.

The first preliminary run correctly failed on Git object permission normalization during extraction; a provisional corrected run passed 73 checks. The final 78-check run above used the committed test source and is the acceptance receipt.
