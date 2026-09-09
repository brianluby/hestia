# Milestone 1: A durable terminal workspace

[Overview](../README.md) · [Architecture](architecture.md) · [Roadmap](roadmap.md)

**Status:** specification, 2026-09-09. Implementation and acceptance are not complete. Agreed scope is recorded here; pilot-specific inputs remain open.

## Problem and goals

Developers need reproducible tools and their preferred terminal agent without installing every project's dependencies on the host. They must retain access from host tools and replace containers without losing work. The first proof is an ordinary working session, not merely a running container.

Success means:

- One repository is editable from host and container tools and builds/tests with its declared toolchain.
- Recreation preserves staged, unstaged, untracked, Git and selected agent state.
- Identity and mount planning accommodate matching directory names and linked worktrees from the first slice.
- Argus completes a real agent-assisted change and build/test cycle on the employer work laptop.

## Evidence stages

**1A — Nonproprietary foundation:** develop a small synthetic repository on the available Apple Silicon Mac. Include a real build/test command, a mise-managed toolchain, dirty Git states and a linked worktree fixture. Choose the language during implementation; fixture success does not establish Argus compatibility. No employer source, credentials or endpoints are required here.

**1B — Argus pilot:** run on the work laptop after its platform, runtime, agent and project requirements are known. Keep Argus source, credentials, internal endpoints and employer-specific configuration there. Use its existing build/test workflow and required services. Retain detailed evidence there; portable Hestia docs contain only sanitized outcomes and limitations appropriate to share.

Passing 1A permits pilot integration. Milestone 1 is complete only when 1B passes. If the work laptop uses Windows, validate its pilot then rather than postponing it to the broader Windows milestone.

## User journey

1. Select an existing checkout and agent. Inspect resolved source/Git paths, workspace identity, persistent state, effective mounts and any published ports.
2. Explicitly build declared tools. Start the workspace without automatic tool installation/upgrades.
3. Attach a terminal, authenticate the selected agent through its supported flow and configure Git access separately. Invoke the agent directly.
4. Make a reviewable change, run the normal build/tests and confirm host tools see the source changes. Committing or publishing is not required for pilot acceptance.
5. Finish active commands, snapshot source/Git and selected session state, remove and recreate the container. Compare durable state before resuming the session and rerunning build/tests.

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
| M1-09 | Actionable failures | Missing checkout, inaccessible metadata, unwritable state, conflicting identity/port or missing required tool yields a clear error. Missing/expired auth blocks the agent with documented recovery while leaving shell/source available. Failed downloads do not replace a working image or modify source/state. |

## Verification and success measures

Use isolated fixture repositories and unique disposable resource identities. Check actual file writes and Git operations, not just generated configuration text. Synthetic credentials test plumbing; they do not prove provider login, refresh or permissions.

A built workspace must start a shell and report installed tool versions without installation downloads. This is not an offline-development promise: agent providers, uncached application dependencies and project services may require networking. Record those dependencies explicitly.

Record platform/runtime/tool versions, image/container IDs, commands, exit codes, cold-build/warm-start timings and persistence comparisons. Timing is diagnostic; no speed threshold is claimed before measurement. Track each M1 requirement as pass/fail/not run with evidence and distinguish fixture from Argus observations. Leading success is all applicable 1A checks passing. Pilot success is all nine requirements supported by combined fixture and Argus evidence, including the real agent/build/test/recreation journey. A fixture alone cannot close 1B.

## Scope limits and follow-ups

- No custom CLI or agent supervisor: use Compose and small necessary helpers.
- No GUI/voice implementation: preserve the shared-build extension point without delaying terminal use.
- No all-agent matrix: validate one integration before expanding.
- No complete backup system or destructive reset automation: preserve data now; restoration follows in Milestone 4.
- Full simultaneous project/worktree workloads and platform matrix expand later; identity and metadata fundamentals are required now.

Nice-to-have: concise task aliases after underlying operations work. They do not gate acceptance.

## Open inputs and sequence

| Input / owner | Needed by | State |
| --- | --- | --- |
| Work laptop OS/CPU and available runtime — user | Argus integration | Unknown; does not block 1A |
| First agent and native authentication/state — user + implementation | Agent integration | Select one; do not assume all candidates behave alike |
| Argus toolchain, build/test commands, services and network needs — user on work laptop | Argus integration | Unknown; remains employer-local |
| Base, verified versions, fixture stack, files, hash format and ownership strategy — implementation | Foundation code | Choose against ADRs and document evidence |

Implement in order: (1) image and declared tools; (2) source/identity/mount planning and lifecycle; (3) selected agent and fixture recreation checks; (4) employer-local Argus configuration and acceptance. Verify each slice before expanding. No deadline or duration has been set.
