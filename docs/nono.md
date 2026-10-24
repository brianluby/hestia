# nono best practices

[Workspace reference](../workspace/README.md#agent-layers) · [Architecture](architecture.md) · [Evidence log](evidence.md)

**Status:** guidance for the pinned nono v0.80.0 in every agent image, and
the [profiles the images ship](#shipped-profiles). No image containing nono
has been built, and nothing here has run inside a Hestia container.
Statements marked *observed* were run with the same release's x86_64 binary
on a Linux 6.18 cloud host (2026-10-24); the rest cite upstream's v0.80.0
sources, linked at the end. The shipped profiles are tested starting points,
not accepted configurations: no agent has done assisted work under them.

## What nono adds here

The container stays the outer boundary (ADR-001, ADR-004). nono adds a
second, narrower one inside it: a sandboxed command reaches only the paths,
hosts and environment its profile grants, enforced by Landlock and seccomp
and inherited by every child process. Upstream calls this a capability
model, not an isolation model: it shares the container's kernel and user,
and it is only as narrow as the profile ([security model][sec]). It also
closes a gap recorded in the [workspace reference](../workspace/README.md):
the workspace state directory is mounted whole, so without nono one agent
can read a sibling agent's state.

## Review of the current configuration

| Setting (Dockerfile `nono` stage) | Assessment |
| --- | --- |
| v0.80.0 tarball pinned by sha256, cross-checked with upstream `SHA256SUMS.txt` | Keep. Matches the mise pattern. |
| SLSA provenance required from `release.yml` only, not the whole `workflows/` prefix | Keep. `attest-release.yml` re-attests downloaded assets and proves nothing about the build. First real verification is the Mac build. |
| `NONO_NO_UPDATE_CHECK=1` | Keep. The binary is pinned; the check would contact `update.nono.sh` daily with an install UUID. |
| `~/.local/state/nono` created dev-owned | Keep. Audit logs, sessions and rollbacks live there and are lost on recreation unless bound with `--state` (below). |
| Hestia profiles shipped root-owned in `/opt/hestia/nono`; agents still start unsandboxed by default | The built-in profiles (`default`, `mise-dev`, `go-dev`, …) cover no agent or Hestia path (*observed*: `nono profile list`), so Hestia ships its own ([below](#shipped-profiles)). Starting agents under nono by default is an open choice. |

## Practices

1. **Check enforcement before relying on it.** Run `nono setup --check-only`
   in each new runtime. nono refuses to run when Landlock reports
   `NotEnforced` and continues on `PartiallyEnforced` (newer rules the kernel
   lacks), so read `nono run -v` output for the status. Whether the macOS
   runtime's VM kernel enables Landlock is unobserved.

2. **Grant the checkout explicitly.** *Observed:* `workdir.access:
   "readwrite"` alone left the checkout read-only, with "Skipping CWD prompt
   (non-interactive)", and the failure diagnostic said no denials were
   observed. Pass `--allow-cwd`, or `--allow "$PWD"`, on every run. For a
   linked worktree, also grant the common Git directory, or commits fail:
   `--allow "$(git rev-parse --path-format=absolute --git-common-dir)"`.
   Worktrees share that metadata (ADR-001); this does not change that.

3. **Extend a base that carries deny groups.** A profile with no
   `groups.include` has no deny rules ([authoring guide][guide], Key Rules).
   Extend `mise-dev` (`default` plus mise's read paths, readwrite workdir
   and the `developer` network preset, cleared in the example below), which blocks
   `~/.ssh`, `~/.aws`, `~/.gnupg`, `~/.docker`, `~/.kube`, `~/.netrc`, shell
   configs and history among others. Do not use `groups.exclude` to fix a
   denial; grant the one path instead.

4. **Grant Hestia's paths narrowly.** These are the paths a workspace uses:

   | Path | Grant | Why |
   | --- | --- | --- |
   | Checkout (and the common Git dir for worktrees) | read+write | The work |
   | `~/.omp` (omp), `~/.pig` (PiG), `~/.pi` (Pi, Pi-Bolt) or `~/.claude` (Claude Code) | read+write | The agent's own sessions and settings |
   | `/hestia/cache` | read+write | `GOCACHE`/`GOMODCACHE` point here |
   | `/opt/hestia/omp` | read only | omp's provider-policy overlay |
   | `/opt/hestia/pi` or `/opt/hestia/pi-bolt` | read only | Pi's or Pi-Bolt's install tree (themes, assets) |
   | `~/.local/state/mise` | read only | mise trust records; write would let the agent `mise trust` its own edits, defeating `MISE_PARANOID=1` |

   Never grant `$HOME`, `~/.local` or the workspace state directory root.
   nono rejects grants that contain its own state, so the first two fail
   anyway ([guide][guide], Protected nono state roots); the state-directory
   root would expose every agent's state. Never grant write to a directory
   on `PATH` (for example the mise shims): a planted binary there runs
   outside the sandbox ([security model][sec]; `--strict-broker-path` turns
   the startup warning into a failure).

5. **Grant narrowly; do not carve denies out of grants.** Landlock has no
   deny primitive. *Observed:* allowing the checkout and denying
   `$WORKDIR/.env` refused to start ("Landlock deny-overlap is not
   enforceable on Linux"). If a file inside the checkout must stay hidden,
   it does not belong in an agent-writable checkout.

   Two more Linux details (*observed*): a grant for a path that does
   not exist when nono starts is silently skipped (Landlock rules attach to
   existing inodes), so create agent directories in the image; and the base
   policy grants `/tmp` **write-only**, which broke Claude Code ("Temp
   directory … is not readable") until the `linux_temp_read` group was
   added. Go builds use `/tmp` the same way.

6. **List network hosts; do not trust presets for Bedrock.** Any
   `allow_domain` or `network_profile` puts the command behind nono's proxy:
   only listed hosts pass, cloud metadata and link-local addresses are always
   denied, and the proxy fails closed ([networking][net]). Clear the
   inherited preset (`"network_profile": null`) and list hosts. *Observed:*
   the `enterprise` preset **denies** `bedrock-runtime.us-west-2.amazonaws.com`
   and `bedrock.us-west-2.amazonaws.com`, because its suffixes only match
   `*.bedrock-runtime.amazonaws.com`, while Bedrock's endpoints are regional.
   Name the region's host explicitly. For LiteLLM, add the endpoint's host;
   a loopback endpoint is untested under the proxy. A Go project that
   downloads modules needs `proxy.golang.org` and `sum.golang.org`. Prefer
   host rules to raw `open_port` grants, which Landlock matches by port
   only.

7. **Filter environment variables with Hestia's variables in the list.**
   Without an `environment` section, everything passes through
   ([environment][env]). An `allow_vars` list removes everything else,
   including variables Hestia depends on. *Observed:* `allow_vars: ["PATH",
   "HOME", "TERM", "AWS_*"]` stripped `PI_CONFIG_FILES` and
   `GIT_CONFIG_COUNT`. Without `PI_CONFIG_FILES`, omp starts **without its
   Bedrock-only policy overlay**; without `GIT_CONFIG_*`, Git's
   `safe.directory` entries disappear. If you filter, include at least
   `PATH`, `HOME`, `TERM`, `LANG`, `PI_CONFIG_FILES`, `GIT_CONFIG_*`,
   `GOCACHE`, `GOMODCACHE`, `GOTOOLCHAIN`, `MISE_*` and the provider's
   variables (`AWS_*`, or `LITELLM_*` and `HESTIA_LITELLM_TRACE_ID`).
   `deny_vars` is the safer tool for dropping one unrelated secret.

8. **Do not count on command blocking.** The inherited `dangerous_commands`
   lists (`rm`, `mv`, `cp`, `chmod`, …) are startup-only checks unless the
   profile also defines `command_policies` ([command blocking][cmd]), and a
   coding agent needs most of them. Path scope, Git and rollback are the
   protection; per-tool command policies are an advanced, untested option.

9. **Keep the policy out of the agent's reach.** Keep profiles in version
   control and load them by path: `nono run --profile /path/profile.json`
   works and can extend a built-in (*observed*). Never grant write to
   `~/.config/nono` or an ancestor: it holds profiles, `config.toml` and
   installed packages, and is not a protected root ([guide][guide],
   Profile Drafts). Hestia follows the omp-overlay pattern: the shipped
   profiles are a root-owned copy under `/opt/hestia/nono`, which no profile
   grants write to.

10. **Review a profile before running it.** `nono profile validate <file>`,
    `nono profile show <name>`, `nono why --profile <file> --path <p> --op
    write` or `--host <h>`, and `nono run --dry-run`. `why` did not apply
    `workdir` access in testing, so check the checkout with a real run.
    Registry packs (`nono pull`) download when you run the command and can
    bring hooks and skills; read them with `nono profile show` and prefer a
    reviewed local copy.

11. **Persist audit and rollback state deliberately.** Supervised runs
    (`nono run`) record an audit session by default; `--rollback` adds
    content-addressed snapshots (default limits: 10 sessions, 5 GB)
    ([rollbacks][rb], [audit][audit]). To keep them across recreation,
    generate the workspace with `--state omp --state
    nono:/home/dev/.local/state/nono`. Snapshots are local undo, not backup.
    The audit ledger is tamper-evident locally but rewritable by anyone with
    the same user; signing (`--audit-sign-key`) helps only if verifiers pin
    the public key.

12. **Leave capability elevation off.** Runtime approval
    (`--capability-elevation`) is disabled by default
    ([supervisor][sup]). Each approval expands authority; prefer editing the
    reviewed profile.

## Shipped profiles

The [`agent/nono`](../agent/nono) files are copied root-owned to
`/opt/hestia/nono` in every agent image. `hestia-base` holds the workspace
paths (practice 4) and is not for direct use: it clears the network preset
and lists no hosts, so on its own it would leave egress unfiltered. Each
agent profile extends it by name; nono resolves the sibling file first.

| Profile | For | Own state (read+write) | Read only | Hosts |
| --- | --- | --- | --- | --- |
| `hestia-omp` | omp (`agent`) | `~/.omp` | `/opt/hestia/omp` | `bedrock-runtime.*.amazonaws.com` (one label: any region) |
| `hestia-pig` | PiG (`pig`) | `~/.pig` | — | nono's `minimal` preset (LLM APIs) |
| `hestia-pi` | Pi and Pi-Bolt | `~/.pi` | `/opt/hestia/pi`, `/opt/hestia/pi-bolt` | `minimal` preset plus `pi.dev` (model catalog) |
| `hestia-claude` | Claude Code | `~/.claude`, `~/.claude.lock` | — | `api.anthropic.com`, `claude.ai`, `platform.claude.com`, `console.anthropic.com` |

Every profile also gets the checkout (with `--allow-cwd`), `/hestia/cache`,
readable `/tmp`, Git config and read-only mise trust state, and denies
credentials, other agents' state and nono's own state. `hestia-claude` sets
`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`, since telemetry hosts are not
allowed anyway. Run an agent under its profile from the checkout:

```sh
nono run --allow-cwd --profile /opt/hestia/nono/hestia-claude.json -- claude
nono run --allow-cwd --profile /opt/hestia/nono/hestia-omp.json -- omp
```

Add `--allow "$(git rev-parse --path-format=absolute --git-common-dir)"` in a
linked worktree, and `--allow-domain <host>` for anything else an agent
needs: a LiteLLM endpoint for omp, or another provider for Pi.

*Observed* on the cloud host with the image's layout recreated (profiles in
`/opt/hestia/nono`, Pi and Pi-Bolt trees in `/opt/hestia`, a dev-like home):

- All five profiles validate. A `nono why` matrix of 73 expectations passed:
  each profile denies `~/.ssh`, nono's state, policy and profile writes,
  mise trust writes, `github.com` and the metadata address, and allows its
  own state, `/hestia/cache` and `/usr/local/bin`; no profile reaches
  another agent's state; omp's wildcard allows two regions' Bedrock hosts
  and denies the regionless host, two-label spellings, S3 and Anthropic;
  Claude's denies OpenAI, `statsig.anthropic.com` and `pi.dev`.
- Real runs, offline: Pi and Pi-Bolt `--list-models` and `claude --version`
  exit 0; a Go module builds and tests under `hestia-pi`.
- Through nono's proxy: `curl` to `api.anthropic.com` under `hestia-claude`
  reached the API (HTTP 401, no credentials); `github.com` was refused by
  nono. Under a clean environment, `claude doctor` ran, wrote only inside
  `~/.claude`, and reported no credentials and auto-updates disabled.
- Fixed during testing: `~/.claude.lock` must exist (now created in the
  image, with `~/.pig`), and `/tmp` needed `linux_temp_read`.

**Not run:** omp and PiG under nono (only `why` checks), any authenticated
agent session or assisted change, provider traffic other than the one
`curl`, and anything on arm64 or in a container.

## Open choices

- Whether agents should start under their profile by default, rather than
  by an explicit `nono run`.
- Per-provider host lists for Pi and PiG beyond nono's `minimal` preset, and
  a LiteLLM variant of `hestia-omp`.
- Whether nono's state should be a default `--state` in generated workspaces.

## Sources

Upstream at the pinned tag `v0.80.0`:

- [Security model][sec], [authoring guide][guide], [networking][net],
  [environment filtering][env], [command blocking][cmd],
  [rollbacks][rb], [audit][audit], [supervisor][sup]
- [Network presets](https://github.com/nolabs-ai/nono/blob/v0.80.0/crates/nono-cli/data/network-policy.json)
  and [policy groups](https://github.com/nolabs-ai/nono/blob/v0.80.0/crates/nono-cli/data/policy.json)

[sec]: https://github.com/nolabs-ai/nono/blob/v0.80.0/docs/cli/internals/security-model.mdx
[guide]: https://github.com/nolabs-ai/nono/blob/v0.80.0/crates/nono-cli/data/profile-authoring-guide.md
[net]: https://github.com/nolabs-ai/nono/blob/v0.80.0/docs/cli/features/networking.mdx
[env]: https://github.com/nolabs-ai/nono/blob/v0.80.0/docs/cli/features/environment.mdx
[cmd]: https://github.com/nolabs-ai/nono/blob/v0.80.0/docs/cli/features/dangerous-command-blocking.mdx
[rb]: https://github.com/nolabs-ai/nono/blob/v0.80.0/docs/cli/features/atomic-rollbacks.mdx
[audit]: https://github.com/nolabs-ai/nono/blob/v0.80.0/docs/cli/features/audit.mdx
[sup]: https://github.com/nolabs-ai/nono/blob/v0.80.0/docs/cli/features/supervisor.mdx
