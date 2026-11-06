# Hestia

Hestia is a terminal-first development container project targeting Apple Silicon macOS and Windows through WSL2. The goal is reproducible toolchains and disposable containers without disposable work.

**Status: fixture foundation implemented; Milestone 1 acceptance incomplete.** The synthetic Go fixture, checkout identity, canonical linux/arm64 image, scoped Compose generator, durable state, lifecycle/cache helpers and the optional agent layers (omp, PiG) have macOS arm64 evidence in the [evidence log](docs/evidence.md). omp settings persistence and the provider-policy overlay are exercised. Every agent image also carries the [nono](https://github.com/nolabs-ai/nono) sandbox CLI, and opt-in images add upstream Pi, Pi-Bolt and Claude Code; all of them build on the Mac, but no agent session has run under nono or in the new images. The [native LiteLLM fixture proof](docs/m1-apple-silicon-evidence-v2.md) verifies real assisted edits, recreation and saved-session resume; Bedrock authentication, PiG's authentication and sessions, Argus and Windows/WSL2 acceptance are pending. The three-step start below is a requirement: the `hestia` launcher exists (step 2); the shared login and the first-run toolchain install of a checkout's declared tools are implemented; the installer is not. Today the path still takes about ten expert steps (see the [runbook](docs/runbook.md)).

## Target workflow: three steps

With Docker installed ([ADR-006](docs/architecture.md#adr-006-three-step-start)):

1. **Install** Hestia with one copy-paste command.
2. **Run `hestia`** in any repository. The first run builds the image and the repository's declared toolchain, then opens pi in a container that sees the same files as your host.
3. **Tell pi what to do.** The first time, sign in with `/login`. The login carries over to every repository.

Run `hestia` again to return to the workspace. Recreating the container keeps source changes, Git metadata and agent sessions; caches can be rebuilt. Expert controls (identity, mounts, lifecycle, sandboxing, provider handoffs) remain in the [workspace helpers](workspace/README.md). You never need them to get started.

## Initial scope

- A minimal base containing OS utilities and mise; project toolchains and agents stay outside the default base.
- One canonical build definition, with verified dependencies and multi-architecture builds as design goals rather than existing support claims.
- Checkout identity derived from its canonical path, explicit Git worktree support, and host source separated from persistent agent/service state and disposable Linux caches.
- Optional agents and project services, not an agent orchestration framework.
- No default host Docker socket mount or broad credential/home-directory mounts.

The first milestone has two evidence stages: a nonproprietary fixture on the available Apple Silicon Mac, followed by the Argus pilot on the employer work laptop. Argus source, credentials, and employer-specific configuration stay there. Fixture success alone does not complete the milestone. omp retains AWS Bedrock as its default; the user-selected LiteLLM opt-in passes fixture acceptance. Work-laptop platform and Argus build/service requirements remain open.

Identity and worktree mount planning are part of the foundation; full concurrent workloads, backup/restore, and the broader platform matrix follow. A future browser IDE variant will share the terminal variant's tools and state. Browser IDE and voice implementation are optional, not prerequisites for terminal use.

## Project notes

- [Tester runbook](docs/runbook.md): verification of internals, not the user path. Step-by-step fixture setup, workspace checks, persistence, optional omp acceptance and regression commands.
- [Milestone 1](docs/milestone-1.md): user journey, acceptance checks, pilot boundaries, and open inputs.
- [Synthetic fixture](fixtures/README.md): nonproprietary build/test fixture for Milestone 1A evidence.
- [Workspace identity](identity/README.md): bounded checkout-derived identity helper (M1-04).
- [Workspace mounts](workspace/README.md): scoped Compose generator for host checkouts and worktree metadata (M1-02/M1-05).
- [Evidence log](docs/evidence.md): observed platforms, versions, commands and results per requirement.
- [nono best practices](docs/nono.md): configuring the optional nono sandbox CLI inside a workspace.
- [Architecture](docs/architecture.md): accepted design defaults, trade-offs, and remaining implementation choices.
- [Roadmap](docs/roadmap.md): short, acceptance-driven implementation sequence.
- [Contributor instructions](AGENTS.md): scope, evidence, verification, and safety expectations.

## License

[MIT](LICENSE)
