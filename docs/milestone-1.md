# Milestone 1: A durable terminal workspace

[Overview](../README.md) · [Architecture](architecture.md) · [Roadmap](roadmap.md)

**Status:** fixture foundation and optional omp layer implemented; Milestone 1 acceptance incomplete. macOS arm64 fixture/runtime and omp settings-persistence evidence is recorded in the [evidence log](evidence.md). The [native LiteLLM fixture proof](m1-apple-silicon-evidence-v2.md) verifies real assisted edits, recreation and saved-session resume. Bedrock authentication and the Argus pilot remain pending.

## Problem and goals

Developers need reproducible tools and their preferred terminal agent without installing every project's dependencies on the host. They must retain access from host tools and replace containers without losing work. The first proof is an ordinary working session, not merely a running container.

Success means:

- One repository is editable from host and container tools and builds/tests with its declared toolchain.
- Recreation preserves staged, unstaged, untracked, Git and selected agent state.
- Identity and mount planning accommodate matching directory names and linked worktrees from the first slice.
- Argus completes a real agent-assisted change and build/test cycle on the employer work laptop.

## Evidence stages

**1A — Nonproprietary foundation:** the synthetic Go repository on the available Apple Silicon Mac exercises a real build/test, a mise-managed toolchain, dirty Git states and linked worktrees. Its image, mounts and lifecycle have runtime evidence; authenticated native omp/LiteLLM edits and saved-session resume after recreation pass the linked proof. Bedrock authentication remains unverified. Fixture success does not establish Argus compatibility. No employer source, credentials or endpoints are required here.

**1B — Argus pilot:** run on the work laptop after its platform, runtime, agent and project requirements are known. Keep Argus source, credentials, internal endpoints and employer-specific configuration there. Use its existing build/test workflow and required services. Retain detailed evidence there; portable Hestia docs contain only sanitized outcomes and limitations appropriate to share.

Passing 1A permits pilot integration. Milestone 1 is complete only when 1B passes. If the work laptop uses Windows, validate its pilot then rather than postponing it to the broader Windows milestone.

## User journey

With Docker already installed, the user takes three steps ([ADR-006](architecture.md#adr-006-three-step-start)):

1. Install Hestia with one copy-paste command.
2. Run `hestia` in an existing checkout.
3. Tell pi what to do. On first use only, sign in with pi's `/login`.

The user does not set file paths, environment variables, image tags or flags, and does not run trust or toolchain commands. Inspection and lifecycle helpers stay available but are not required.

## Acceptance procedure

Testers, not users, also verify durability: the agent makes a reviewable change and the normal build/tests pass; host tools see the change; then the tester snapshots source/Git and session state, recreates the container, compares durable state, and resumes the session and build/tests.

## User stories

- As a developer, I want my existing checkout available in the workspace so that native tools and a terminal agent share source without synchronization.
- As a developer, I want declared tools ready at startup so that recreation does not require manual environment repair.
- As a developer, I want work and selected sessions preserved so that replacing a container is routine.
- As a worktree user, I want correct Git access and distinct state so that unrelated sessions do not collide.

## Must-have requirements and acceptance

| ID | Requirement | Observable acceptance |
| --- | --- | --- |
| M1-01 | Canonical build with minimal mise base and selected tools/agent | Record image identity, actual architecture, tool versions and integrity evidence. A real build/test passes. Default variant contains no browser IDE. |
| M1-02 | Host source and scoped, path-consistent mounts | Host edits are readable inside and container edits outside; Git status/diff agrees. Effective mounts expose only selected source, required metadata and explicit state/access; no broad home/repository collection or host Docker socket. |
| M1-03 | Effective ownership and artifact separation | Non-root process can edit source and required state/cache files. No recursive host ownership changes. Native and Linux dependency/build artifacts do not overwrite each other. |
| M1-04 | Deterministic workspace identity | Identical basenames at different paths and a main checkout/linked worktree get distinct resource identities. Branch/variant changes preserve identity; symlink aliases to the same canonical checkout do not duplicate it. State/path mismatch is detected before reuse. |
| M1-05 | Worktree-aware mount planning | Git resolves checkout/common metadata inside and outside for supported absolute and relative link layouts. Stage/diff a fixture change without rewriting pointers or exposing sibling source. Unsupported layouts fail clearly without mutation. Full concurrent worktree workloads follow in Milestone 3. |
| M1-06 | Lifecycle and persistence | Snapshot source bytes, index/tree identity, branch/HEAD, status including untracked files and selected state. Recreate with a different container ID; require zero unintended durable differences before resumed work. Build/tests pass again. |
| M1-07 | Native agent authentication and sessions | Document state paths/sensitivity, login/refresh and separate Git access. Complete an agent-assisted change, recreate and resume the saved session or documented native equivalent. No replacement permission engine or credential values in logs, images, tracked config or generated Compose. |
| M1-08 | Scoped cache clearing | In disposable fixture storage, clear only that workspace's classified caches. Source/Git and durable state remain unchanged; regeneration and build/tests succeed. No global prune or production resource identity. |
| M1-10 | Three-step start | Starting with a Mac that has only Docker installed, a tester who has not read the docs beyond the README quick start installs Hestia, runs `hestia` in a non-fixture repository with a mise declaration, and has pi make and build/test a change in no more than three steps. Record the commands typed, every prompt answered and the time to the first agent prompt (cold and warm). A second repository needs no new login. |
| M1-09 | Actionable failures | Missing checkout, inaccessible metadata, unwritable state, conflicting identity/port or missing required tool yields a clear error. Missing/expired auth blocks the agent with documented recovery while leaving shell/source available. Failed downloads do not replace a working image or modify source/state. |

## Verification and success measures

Use isolated fixture repositories and unique disposable resource identities. Check actual file writes and Git operations, not just generated configuration text. Synthetic credentials test plumbing; they do not prove provider login, refresh or permissions.

A built workspace must start a shell and report installed tool versions without installation downloads. This is not an offline-development promise: agent providers, uncached application dependencies and project services may require networking. Record those dependencies explicitly.

Record platform/runtime/tool versions, image/container IDs, commands, exit codes, cold-build/warm-start timings and persistence comparisons. Timing is diagnostic; no speed threshold is claimed before measurement. Track each M1 requirement as pass/fail/not run with evidence and distinguish fixture from Argus observations. Leading success is all applicable 1A checks passing. Pilot success is all nine requirements supported by combined fixture and Argus evidence, including the real agent/build/test/recreation journey. A fixture alone cannot close 1B.

## Scope limits and follow-ups

- One thin `hestia` launcher (ADR-006), with no CLI framework or agent supervisor. Underneath, Compose and the existing helpers do the work.
- No GUI/voice implementation: preserve the shared-build extension point without delaying terminal use.
- No all-agent matrix: pi is the default; validate it before expanding.
- No complete backup system or destructive reset automation: preserve data now; restoration follows in Milestone 4.
- Full simultaneous project/worktree workloads and platform matrix expand later; identity and metadata fundamentals are required now.

## Open inputs and sequence

| Input / owner | Needed by | State |
| --- | --- | --- |
| Work laptop OS/CPU and available runtime — user | Argus integration | Unknown; does not block 1A |
| Native agent acceptance — user + implementation | Complete agent acceptance | User-selected omp/LiteLLM fixture proof passes; Bedrock authentication remains unverified |
| Argus toolchain, build/test commands, services and network needs — user on work laptop | Argus integration | Unknown; remains employer-local |
| Foundation implementation — implementation | Extend beyond fixture | Debian/mise, fixture Go, canonical files, identity encoding and non-root scoped mounts implemented; see architecture and evidence |

Next: employer-local Argus configuration and acceptance using the selected supported provider. Preserve the established image, source/identity/mount and lifecycle contracts. No deadline or duration has been set.
