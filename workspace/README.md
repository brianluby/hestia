# Workspace mounts

[ADR-001](../docs/architecture.md) · Tickets `JP73P2D` `KSCDG1J` `24GJSHY` `HE2GM6N` `XJVWF4K` · [Mount tests](../tests/workspace-mounts.test.sh) · [Lifecycle tests](../tests/workspace-lifecycle.test.sh) · [Cache-clear tests](../tests/workspace-cache-clear.test.sh)

`workspace/workspace-compose.sh` generates a scoped Compose definition for one
checkout. It is a helper, not a Hestia command: the output is an ordinary
Compose file for `docker compose -f ... run workspace ...`.

## Usage

```sh
workspace/workspace-compose.sh [--image IMG] [--out FILE] <checkout-path>
docker compose -f <file> run --rm workspace <command>   # one-off command
workspace/workspace-lifecycle.sh start <file>           # persistent workspace
```

The generated service runs `sleep infinity` when started, so it stays
attachable; `compose run` overrides that for one-off commands.

## Fixture walkthrough

Run from the Hestia repository root in Bash on the exercised Apple Silicon
Mac with Docker/Compose running, host Git and mise available, and host Go
1.27.1 already installed through mise. Builds require network access. This
uses only synthetic source and a fresh directory under Docker-shared `$HOME`.
The fixture helper itself builds/tests on the host; its narrowly scoped
`MISE_TRUSTED_CONFIG_PATHS` deliberately trusts only this new synthetic tree.

```sh
set -euo pipefail
docker build --target fixture-tools -t hestia-fixture:walkthrough .
demo="$(mktemp -d "$HOME/hestia-demo-XXXXXXXX")"
fixture="$(TMPDIR="$demo" MISE_TRUSTED_CONFIG_PATHS="$demo" \
  fixtures/bin/make-fixture.sh | sed -n 's/^fixture ready: //p')"
compose="$demo/workspace.yml"
HESTIA_STATE_ROOT="$demo/state" workspace/workspace-compose.sh \
  --image hestia-fixture:walkthrough --out "$compose" "$fixture/repo"
workspace/workspace-lifecycle.sh validate "$compose"
workspace/workspace-lifecycle.sh start "$compose"
workspace/workspace-lifecycle.sh attach "$compose" bash -c \
  'mise trust && mise exec -- go build ./... && mise exec -- go test ./...'
# Finish active work before replacing the container.
workspace/workspace-lifecycle.sh recreate "$compose"
workspace/workspace-lifecycle.sh attach "$compose" bash -c \
  'mise trust && mise exec -- go build ./... && mise exec -- go test ./...'
fixtures/bin/fixture-snapshot.sh compare "$fixture/repo" "$fixture/snapshots/00-created"
workspace/workspace-lifecycle.sh stop "$compose"
```

For an interactive shell, use `workspace/workspace-lifecycle.sh attach "$compose"`
while running. Inspect a real repository's mise configuration before trusting it;
the explicit `mise trust` above is for this known fixture and is repeated after
recreation. The stopped runtime, cache volume and `$demo` remain available.
`fixture-tools` installs the fixture's pinned Go only: it does not discover or
install arbitrary mounted repositories' tools. This walkthrough proves neither
agent authentication nor Argus/Windows support; credentials are a separate
runtime concern below.

## Lifecycle

`workspace/workspace-lifecycle.sh` wraps the operations explicitly:

| Command | Behavior |
| --- | --- |
| `validate <file>` | Read-only preflight: recorded identity, Compose config and image present locally |
| `start <file>` | Preflight, then create and start detached |
| `attach <file> [cmd...]` | Shell (or command) in the running workspace |
| `stop <file>` | Stop; container, volumes and state retained |
| `remove-runtime <file>` | Remove the container; volumes and state retained |
| `recreate <file>` | Preflight before stopping/removing runtime, then start again — fails if the replacement container ID is not different |
| `clear-caches <file>` | Preflight, then remove only this workspace's `linux-caches` volume (name and declaration verified) and restart; durable state and source untouched |

The helper never runs `down -v`, prunes, or touches source, and the only volume it ever removes is the workspace's own `linux-caches` (via `clear-caches`, identity-verified).
All commands reject non-Hestia project names. `validate`, `start`, `recreate`
and `clear-caches` check durable identity, Compose config and local image before
mutation; a failed preflight leaves the existing runtime and caches alone.
`remove-runtime` also checks durable identity. These checks do not promise
recovery from a later Docker runtime failure.

Limits: recreation interrupts running processes — finish active work first
(`recreate` stops the workspace itself). Warm startup requires the image to
be present locally; startup never downloads or installs (preflight tells you
to build/pull explicitly). If the durable state directory
is lost, the workspace regenerates its `identity.record` on the next
generation; if a container disappears unexpectedly, `start` recreates it.
Published-port conflict validation arrives with project services; the
current workspace publishes no ports.

## What gets bound

- The checkout's canonical path (symlink-resolved) is bind-mounted at the
  identical path inside the container, so host tools and the container see the
  same source at the same location — host edits appear inside and container
  edits outside, and Git status/diff agree.
- When the checkout is a linked worktree, the common Git directory is bound at
  its identical path too: required metadata only. The main checkout's source
  is never mounted alongside (a worktree container sees its own tree plus the
  shared `.git` metadata, nothing else). Both absolute and relative gitdir
  links resolve because the host layout is preserved exactly; no Git pointers
  are rewritten.
- The Compose project name is the checkout's workspace id from
  [identity](../identity/README.md); Compose namespaces containers, networks
  and volumes from it, with no fixed container names.
- Durable workspace state lives in `HESTIA_STATE_ROOT/<workspace-id>`
  (default `~/.local/share/hestia/<workspace-id>`), bound at its identical
  path. Before generating, the directory's recorded identity is checked
  (identity helper `--state-dir`): state recorded for a different checkout is
  refused, and an unwritable state directory fails with an actionable error.
- Disposable Linux build/dependency caches live in a workspace-scoped Compose
  volume at `/hestia/cache` (`GOCACHE`, `GOMODCACHE`); the image pre-creates
  the directory dev-owned so a fresh volume is writable by the non-root user.
  Nothing mounts over mise's install directories, so image toolchain updates
  cannot be hidden by old state.
- Nothing else: no home or repository-collection mount, no host Docker socket,
  no credentials — by construction, asserted in tests.

Host and container UIDs differ, so the generated file sets git's
`safe.directory` through protected environment configuration, scoped to
exactly the mounted paths — no blanket trust.

## Failure behavior

Missing paths, non-checkouts, dangling or out-of-place `.git` pointers and
unreadable metadata fail with a clear error before anything is written; a
failed generation leaves no partial Compose file and never mutates the
checkout.

## Agent layer (omp)

The optional `agent` image target (`docker build --target agent .`) adds omp
(oh-my-pi) on top of `fixture-tools`, installed through mise and verified
against the pinned release digest. The provider policy
(`agent/omp/config.yml`: every built-in provider disabled except bedrock,
which uses the standard AWS credential chain) is baked root-owned at
`/opt/hestia/omp/config.yml` — outside the writable state tree — and loaded
as a config overlay via `PI_CONFIG_FILES`. omp merges global → project →
overlay → runtime overrides; a missing or malformed overlay fails startup.
The overlay shadows user settings without breaking omp's atomic settings
writes, unlike the superseded read-only bind over `~/.omp/agent/config.yml`.
It is not a security boundary against control of the process environment or
runtime overrides. Generate with `--image hestia-agent:<tag>` after explicitly
building that tag with the `agent` target.

Fresh workspaces skip the pinned omp 18.1.16 onboarding wizard through
`setupVersion: 2` in the image overlay. The supported defaults are Titanium
for dark terminals, Light for light terminals, Unicode glyphs and the Band
composer (input editor) layout. These appearance values remain upstream
schema defaults, so writable native settings can change them; the overlay
does not force a theme or composer. There is no separate `editor.mode` key
or first-run external-editor prompt in this version. No model identifier is
invented: Bedrock chooses among models available with runtime authentication.
`omp setup` can explicitly reopen the wizard. Recheck the marker and scenes
when changing the pinned omp version. Sources: [settings schema](https://github.com/can1357/oh-my-pi/blob/61b1b8aef634334eaf1412afd003a763e1d1b9c1/packages/coding-agent/src/config/settings-schema.ts),
[setup version](https://github.com/can1357/oh-my-pi/blob/61b1b8aef634334eaf1412afd003a763e1d1b9c1/packages/coding-agent/src/modes/setup-version.ts)
and [wizard selection](https://github.com/can1357/oh-my-pi/blob/61b1b8aef634334eaf1412afd003a763e1d1b9c1/packages/coding-agent/src/modes/setup-wizard/index.ts).

omp's durable state — sessions (`--resume`), the `agent.db` database, its own
`~/.omp/agent/config.yml` settings (model selection, theme), memory, logs and
extracted natives — lives under `~/.omp`, which the generated Compose file
binds from the workspace state directory
(`<state-root>/<workspace-id>/omp`), outside source and build context. It
survives stop/remove-runtime/recreate like all durable state; `clear-caches`
never touches it.

Real AWS/Bedrock credential-chain authentication remains unverified. The
[LiteLLM fixture proof](../docs/m1-apple-silicon-evidence-v2.md) verifies real
assisted work and native saved-session resume. Without AWS credentials, omp reports missing auth
while shell/source remain usable. Git authentication is separate.
`mise trust` is required per container and after config changes;
`~/.omp/natives` is extracted on first use into durable state.

### Opt-in temporary AWS handoff

After starting the workspace, use one explicit host command:

```sh
# Resolve a scoped temporary profile on the HOST (AWS CLI v2 and jq required).
# Refresh SSO on the host first if needed: aws sso login --profile <profile>.
workspace/workspace-attach-aws.sh --profile <profile> --region us-west-2 <file>
# Or forward an already exported temporary host session and region.
workspace/workspace-attach-aws.sh --env <file>
```

This opens Bash by default; append `omp` or another command to run it directly.
For scripts, add `--no-tty` before `<file>`. The region can come from the
profile, `--region`, or (with `--env`) `AWS_REGION`/`AWS_DEFAULT_REGION`.
The helper requires access key, secret key and session token, forwards only
those and the region to `compose exec`, and keeps values out of command
arguments. It uses the AWS CLI's supported
[process JSON export](https://docs.aws.amazon.com/cli/latest/reference/configure/export-credentials.html),
without evaluating shell text. Credentials are never written by the helper
to Compose, images, state or a file; the helper disables its own shell trace
and suppresses credential-provider error output.

Only the new exec process and its children receive this environment; each
attach and recreation requires another explicit handoff. Expired auth needs
a host refresh/export and a new attach. The helper does not mount `~/.aws`,
forward `AWS_PROFILE`, switch to Bedrock bearer keys or install AWS tools in
the image. Runtime environment secrets remain accessible to the agent and
privileged Docker/process inspection. Commands run in that session can write
or print their environment: keep shell tracing, `env` dumps and credential
logging off, and do not save credentials in omp settings or agent responses.
Synthetic handoff coverage is in [workspace-aws.test.sh](../tests/workspace-aws.test.sh);
it does not establish authenticated Bedrock inference.

### Opt-in LiteLLM handoff

The selected alternative is an OpenAI-compatible LiteLLM endpoint. Build the
current optional `agent` target explicitly and start/recreate with that image.
Export `LITELLM_API_KEY` on the host through your existing secret source, then
use an explicitly selected endpoint and model:

```sh
workspace/workspace-attach-litellm.sh --endpoint <URL> --model <ID> [--trace-id <UUID>] <file>
# Native arguments remain available, including explicit saved-session resume:
workspace/workspace-attach-litellm.sh --endpoint <URL> --model <ID> <file> --resume <session-id-or-path>
```

This invokes native omp directly. For scripted native `-p` work, add both
`--no-tty` and `--no-stdin` before `<file>`: the former disables TTY allocation,
while the latter closes container stdin so native print mode receives EOF.
Without `--no-stdin`, non-TTY print mode reads stdin until EOF before startup.
The helper requires a nonempty key, forwards key/endpoint/trace and
selected policy environment to that exec, and selects exact LiteLLM
main/small/slow roles. It generates a fresh UUID for the required
`x-litellm-trace-id` header unless `--trace-id` supplies one. Values stay out
of Docker arguments and generated Compose files. The non-secret endpoint
appears in temporary native provider configuration; no key value is written
there. The image-owned LiteLLM overlay enables only
that built-in provider and skips pinned onboarding; ordinary attaches retain
the default Bedrock overlay. No host models.yml, auth database or home is
copied or mounted. Permission/session controls remain native.

This helper supports the default scoped omp profile with extensions disabled.
It rejects caller routing, model-role, profile, storage, config-overlay,
extension and hook overrides; native permission controls and `--resume` remain
available. Default `~/.omp/agent/models.yml`, fallback `models.yaml`, or legacy
`models.json` can replace the endpoint/auth/headers, so their presence is
rejected before key forwarding. Symlinked native storage, ambient profile/XDG
redirection, broker environment selection, and known project/agent/config-root/
home `.env` / `.env.*` files are also unsupported. Files are preserved.

Host Python 3 with standard-library SQLite and Ruby with standard-library
Psych are required; nothing is installed by the helper. Read-only SQLite
metadata checks reject active stored LiteLLM auth, unknown/corrupt schema,
legacy `auth.json`, and nonempty legacy settings when native global YAML is
absent. Safe YAML/plain JSON checks reject a nested or dotted broker URL key
in default global/project native settings, without inspecting credential
values or reporting file contents. YAML aliases/tags and JSONC are unsupported
by this bounded guard. Ordinary native session/settings databases and safe
appearance preferences remain usable. Use fresh default scoped workspace state
or deliberately resolve the conflicting native configuration yourself before
retrying; do not change routing configuration concurrently with handoff.

After these read-only guards, the image-owned wrapper exclusively locks the
default agent directory and temporarily publishes its own `models.yml`
symlink to a private container `/tmp` file. This native configuration declares
only the existing LiteLLM provider, selected endpoint, generic OpenAI
`/models` discovery with the Chat Completions API, and environment-name
references; it defines no custom models or credential value.
Discovery preserves the advertised exact IDs and the explicit Chat Completions
route; it does not infer a Responses route from rich LiteLLM management metadata.
Discovery and inference receive the trace header; the key remains in the
process environment. When `/models` omits metadata, omp uses its upstream
catalog or defaults for context/output limits and capabilities. These SDK
assumptions do not qualify the backend's limits or capabilities.

Every attach runs native `omp models litellm --json --no-extensions`, requires
the exact model ID, and launches qualified main/small/slow roles. Raw discovery
payloads/errors are suppressed. Native omp updates its own settings, database
and model caches. Normal exit or caught signals remove wrapper-owned temporary
configuration and lock, preserving any replacement native file. Concurrent
handoffs to this profile are rejected. Forced termination such as SIGKILL can
retain the pointer and lock; stop the old process and deliberately resolve
those helper-owned entries before retrying. Existing native configuration is
never overwritten.

Each attach/recreation needs another explicit handoff; revoke/refresh the key
through its existing provider. Runtime environment remains visible to the
agent and privileged inspection. The helper does not prove that every
OpenAI-compatible server/model implements Chat Completions. Verify real
inference and explicit native resume for the selected
endpoint/model before closing agent acceptance; synthetic plumbing does not
satisfy those criteria.

## Limits

One writer per checkout at a time: host and container share the working tree
and index (ADR-001). Worktrees share Git metadata and are not mutually
untrusted boundaries. Full concurrent worktree workloads follow in
Milestone 3. Persistence and lifecycle are implemented, not concurrency proof.

## Verified

The [evidence log](../docs/evidence.md) records macOS arm64 fixture builds,
mount/write/worktree checks, lifecycle/cache preservation and omp
state/settings/overlay checks, including later review fixes. The
[native LiteLLM fixture proof](../docs/m1-apple-silicon-evidence-v2.md) verifies
real assisted edits and saved-session resume after recreation. Bedrock
authentication remains unverified. Fixtures must live
on Docker-shared paths on macOS (home, not the unshared `/tmp` path observed
in the recorded runtime). No broader platform support is established.
