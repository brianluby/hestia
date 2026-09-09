# Roadmap

[Project overview](../README.md) · [Proposed architecture](architecture.md)

The scaffold is the current state. The following are implementation milestones, in acceptance order, not delivered features or deadlines. Select tools and resolve architecture choices only as needed for the next proof. Record the actual platform, versions, actions, and results; no executable Hestia commands are promised here.

## 1. One real repository, end to end

On Apple Silicon macOS:

- Open an existing, real repository in a terminal workspace built through the canonical image/Compose path, using its toolchains through mise.
- Use one selected terminal agent to make a reviewable change and run the repository's real build and tests successfully inside the container. A shell prompt or agent version check alone is not acceptance; supporting every candidate agent is not required for this proof.
- Record source/Git and selected durable state, including staged, unstaged, and untracked work. Remove and recreate the container, not merely restart it. Confirm the work and state remain usable, then rerun the build and tests successfully.
- Inspect the effective mounts: no default host Docker socket or broad credential/home-directory exposure. Record dependency integrity evidence for the tested architecture.

## 2. Concurrent projects

- Run two independent repositories concurrently using the same canonical build path, including a case where their directory names match.
- Show distinct workspace identities and no unintended source/state sharing or service-name/port collisions. Build and test each repository.
- Recreate one project's container and show that the other remains usable and its durable work is unchanged.

## 3. Explicit Git worktrees

- Open a main checkout and a linked worktree in distinct workspaces. Demonstrate that Git resolves the shared metadata correctly and each workspace builds and tests its intended branch through a terminal agent.
- Recreate one container; confirm both workspaces retain their changes and Git operations still work. Access to shared metadata must not require a broad host home mount.

## 4. Backup and restore

- Define the backup contents and handling of sensitive state, then back up the durable source, Git/worktree metadata, and selected agent/service state used in the proof. Exclude disposable caches; handle credentials explicitly rather than silently copying a credential tree.
- Restore into fresh storage and demonstrate the saved work, valid worktree relationships, and selected state. Rebuild caches and successfully build and test the repository. A backup file existing is not acceptance.

## 5. Windows through WSL2

- Repeat the single-repository, concurrent-project, worktree, and backup/restore proofs on an actual Windows/WSL2 host using the same canonical build definition, not a platform fork.
- Record the runtime, CPU architecture, source filesystem placement, path/permission behavior, and any limitations. Verify architecture-specific dependencies and builds for the tested host architectures; claim support only for the matrix exercised.

Browser IDE and voice input remain optional future considerations, not milestones or prerequisites for this sequence. A custom CLI and agent orchestration are outside the initial scope.
