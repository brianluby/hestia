# Contributing to Hestia

Hestia is currently a scaffold. Read the [architecture](docs/architecture.md) and [roadmap](docs/roadmap.md) before changing scope.

- Prefer the smallest straightforward solution. Users get one thin `hestia` launcher over Compose, mise and the existing helpers ([ADR-006](docs/architecture.md#adr-006-three-step-start)). Do not grow it into a CLI framework, orchestration framework or specification machinery.
- Protect the three-step start: install, run `hestia`, talk to the agent. Any change that adds a required user step, flag, path or environment variable needs a demonstrated need and an update to M1-10.
- Preserve one canonical image/build path. Keep optional capabilities out of the minimal base.
- Back technical claims with primary sources or observed results. Distinguish intentions from implemented and verified behavior; do not invent dependencies, version pins, platform support, or commands.
- Verify the behavior you change. Record the platform, actions, and actual results. For scaffold-only changes, check structure, documentation links, ignore rules, and Git status; do not install dependencies or build containers merely to validate prose.
- Treat source, Git worktree metadata, and selected durable state as user data. Do not confuse caches with durable storage or persistence with backup.
- Never commit secrets or bake them into images. Keep credentials outside the repository and build context; examples must contain only non-secret values. Ignore files are hygiene, not a security boundary.
- Do not default to host Docker socket access or broad credential/home-directory mounts. Scope any required access explicitly and retain each agent's own session and permission controls.
- Preserve existing work. Treat `container-dev-env` as read-only inspiration; do not copy its backlog, agent framework, or extensive specification process.
- Keep documentation small and aligned with observed behavior. Record unresolved choices rather than silently expanding requirements.
