# Hestia

Hestia is a planned, terminal-first development container environment for Apple Silicon macOS and Windows through WSL2. The goal is reproducible toolchains and disposable containers without disposable work.

**Status: scaffold only.** This repository contains design notes and ignore rules, not a working environment. No containers, Compose configuration, mise configuration, dependency installation, or custom CLI are implemented. There are no Hestia commands to run yet; neither target platform has been validated.

## Intended workflow

The following describes the proposed experience, not available commands:

1. Select a real repository and identify its project and, when applicable, its Git worktree.
2. Start its workspace through Docker Compose using one canonical image/build path. Use mise to manage the repository's declared toolchains.
3. Attach through a terminal. Optionally install and use a coding agent such as Codex CLI, omp, or pi.dev, with that agent's own authentication, session, and permission mechanisms.
4. Build and test using the repository's normal workflow. Compose additional project services only when needed.
5. Recreate the container without losing source changes, Git metadata, or selected durable state. Treat caches as rebuildable, not as the only copy of work.

## Initial scope

- A minimal base containing OS utilities and mise; project toolchains and agents stay outside the default base.
- One canonical build definition, with verified dependencies and multi-architecture builds as design goals rather than existing support claims.
- Per-project workspace identity, explicit Git worktree support, and deliberate separation of durable source/state from disposable caches.
- Optional agents and project services, not an agent orchestration framework.
- No default host Docker socket mount or broad credential/home-directory mounts.

The first implementation milestone must prove a real repository can be opened, changed, built, and tested through one terminal agent, then survive container recreation. Concurrent projects, worktrees, backup/restore, and Windows/WSL2 validation follow. Browser IDE and voice input are optional future capabilities, not prerequisites or scheduled commitments.

## Project notes

- [Architecture](docs/architecture.md): proposed responsibilities, trade-offs, and unresolved decisions.
- [Roadmap](docs/roadmap.md): short, acceptance-driven implementation sequence.
- [Contributor instructions](AGENTS.md): scope, evidence, verification, and safety expectations.
