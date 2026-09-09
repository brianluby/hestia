# Hestia

Hestia is a planned, terminal-first development container environment for Apple Silicon macOS and Windows through WSL2. The goal is reproducible toolchains and disposable containers without disposable work.

**Status: specification ready; foundation implementation starting.** This repository contains accepted architecture defaults, a Milestone 1 specification, ignore rules, and the first implementation slices: an isolated synthetic build/test fixture under `fixtures/`, a checkout-derived identity helper under `identity/`, a canonical Dockerfile with a non-root mise base plus an explicit fixture-toolchain stage (linux/arm64), and a scoped-mount Compose generator under `workspace/`, all verified on macOS arm64 with results in the [evidence log](docs/evidence.md). No Compose configuration or custom CLI is implemented yet. Neither target platform has been validated end to end.

## Intended workflow

The following describes the proposed experience, not available commands:

1. Select an existing host repository (for example under `~/repos`) and identify its checkout and, when applicable, shared Git metadata. Host tools continue using the same source files.
2. Start its workspace through Docker Compose using one canonical image/build path. Use mise to manage the repository's declared toolchains.
3. Attach through a terminal. Optionally install and use a coding agent such as Codex CLI, omp, or pi.dev, with that agent's own authentication, session, and permission mechanisms.
4. Build and test using the repository's normal workflow. Compose additional project services only when needed.
5. Recreate the container without losing source changes, Git metadata, or selected durable state. Treat caches as rebuildable, not as the only copy of work.

## Initial scope

- A minimal base containing OS utilities and mise; project toolchains and agents stay outside the default base.
- One canonical build definition, with verified dependencies and multi-architecture builds as design goals rather than existing support claims.
- Checkout identity derived from its canonical path, explicit Git worktree support, and host source separated from persistent agent/service state and disposable Linux caches.
- Optional agents and project services, not an agent orchestration framework.
- No default host Docker socket mount or broad credential/home-directory mounts.

The first milestone has two evidence stages: a nonproprietary fixture on the available Apple Silicon Mac, followed by the Argus pilot on the employer work laptop. Argus source, credentials, and employer-specific configuration stay there. Fixture success alone does not complete the milestone. Work-laptop platform, first agent, and Argus build/service requirements remain open.

Identity and worktree mount planning are part of the foundation; full concurrent workloads, backup/restore, and the broader platform matrix follow. A future browser IDE variant will share the terminal variant's tools and state. Browser IDE and voice implementation are optional, not prerequisites for terminal use.

## Project notes

- [Milestone 1](docs/milestone-1.md): user journey, acceptance checks, pilot boundaries, and open inputs.
- [Synthetic fixture](fixtures/README.md): nonproprietary build/test fixture for Milestone 1A evidence.
- [Workspace identity](identity/README.md): bounded checkout-derived identity helper (M1-04).
- [Workspace mounts](workspace/README.md): scoped Compose generator for host checkouts and worktree metadata (M1-02/M1-05).
- [Evidence log](docs/evidence.md): observed platforms, versions, commands and results per requirement.
- [Architecture](docs/architecture.md): accepted design defaults, trade-offs, and remaining implementation choices.
- [Roadmap](docs/roadmap.md): short, acceptance-driven implementation sequence.
- [Contributor instructions](AGENTS.md): scope, evidence, verification, and safety expectations.
