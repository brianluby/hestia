# Roadmap

[Project overview](../README.md) · [Architecture decisions](architecture.md) · [Milestone 1 spec](milestone-1.md)

The current state is a verified foundation: architecture defaults and the Milestone 1 specification stand, and the Milestone 1A fixture, identity, image, scoped mounts, lifecycle and cache-clearing slices are implemented and verified on macOS arm64 (see the [evidence log](evidence.md) and the [review disposition](reviews/2026-09-09-ocr-prs-1-8-disposition.md)). Agent integration, the Argus pilot, concurrency and later milestones remain. These milestones describe acceptance order, not delivered features or deadlines. Record actual platforms, versions, actions, and results. Lifecycle names do not imply an implemented Hestia CLI.

## 1. Foundation and Argus pilot

The [Milestone 1 spec](milestone-1.md) defines requirements M1-01 through M1-09 and evidence expectations.

### 1A. Nonproprietary foundation

- On the available Apple Silicon Mac, use a synthetic repository with an actual build/test, declared mise toolchain, dirty Git states and linked-worktree fixture.
- Establish the canonical build path, effective permissions, host source access, artifact separation and lifecycle behavior.
- Validate deterministic identities for matching directory names and worktrees, path-consistent Git metadata mounts, and synthetic state persistence. These fundamentals must precede later concurrency proofs.
- Integrate one selected agent and verify recreation with source/state comparisons, real file operations and isolated resources. No employer source, credentials or endpoints are required here.

### 1B. Argus on the employer work laptop

- Confirm laptop OS/CPU/runtime, selected agent and Argus toolchain/build/test/service requirements there.
- Use the real agent to make a reviewable change, build/test Argus, remove/recreate the workspace, resume selected state and build/test again.
- Keep source, credentials, employer-specific configuration and detailed evidence on the work laptop. Share only sanitized outcomes appropriate for Hestia documentation.
- If this laptop uses Windows/WSL2, exercise its pilot path now. The broader matrix in Milestone 5 is additional coverage.

Milestone 1 closes only after the Argus journey and M1 requirements pass. Fixture success, a running shell, or a version check alone is insufficient. There are no completed runtime checks yet.

## 2. Concurrent projects

- Run two independent repositories concurrently using the same canonical build path, including a case where their directory names match.
- Show distinct workspace identities and no unintended source/state sharing or service-name/port collisions. Build and test each repository.
- Recreate one project's container and show that the other remains usable and its durable work is unchanged.

## 3. Concurrent Git worktree workflows

- Extend Milestone 1's worktree identity/mount checks to simultaneous real workflows. Open a main checkout and a linked worktree in distinct workspaces; each builds and tests its intended branch through a terminal agent.
- Recreate one container; confirm both workspaces retain their changes and Git operations still work. Access to shared metadata must not require a broad host home mount.

## 4. Backup and restore

- Define the backup contents and handling of sensitive state, then back up the durable source, Git/worktree metadata, and selected agent/service state used in the proof. Exclude disposable caches; handle credentials explicitly rather than silently copying a credential tree.
- Restore into fresh storage and demonstrate the saved work, valid worktree relationships, and selected state. Rebuild caches and successfully build and test the repository. A backup file existing is not acceptance.

## 5. Windows through WSL2

- Repeat the single-repository, concurrent-project, worktree, and backup/restore proofs on an actual Windows/WSL2 host using the same canonical build definition, not a platform fork. Expand any Windows evidence already collected during the Argus pilot.
- Record the runtime, CPU architecture, source filesystem placement, path/permission behavior, and any limitations. Verify architecture-specific dependencies and builds for the tested host architectures; claim support only for the matrix exercised.

Browser IDE and voice input remain optional future considerations, not milestones or prerequisites for this sequence. A custom CLI and agent orchestration are outside the initial scope.
