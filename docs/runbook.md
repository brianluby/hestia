# Tester runbook

[Overview](../README.md) · [Acceptance criteria](milestone-1.md) · [Recorded evidence](evidence.md) · [Workspace reference](../workspace/README.md)

Use this runbook to test Hestia against a disposable, nonproprietary Go fixture.
It covers the implemented foundation, not the Argus pilot or a general platform
certification. Historical runtime evidence is macOS arm64 with Linux arm64
containers; Windows/WSL2 and other architectures are not established by it.

**Expected results below are acceptance checks, not claims that your run passed.**
Stop at an unexpected result, retain the fixture and record the failing command,
exit status and sanitized output. Do not continue to destructive steps after a
failed preservation check.
Run commands one at a time; stop on any unexpected nonzero exit. Silent checks
and snapshot comparisons use `|| exit 1` to stop the dedicated host Bash shell
before a later command can hide a failure. On failure, retain the printed paths
and restore the run's variables in a new Bash shell before investigating; do not
continue to recreation or cache clearing. Failed checks do not delete test data.

## 1. Prepare the host

You need:

- An Apple Silicon Mac with a working Docker engine and Docker Compose v2.
- Git 2.31 or newer, Bash and host mise on `PATH`.
- The fixture's declared Go toolchain installed through host mise. Fixture
  creation runs a native build/test; the container image does not supply host Go.
- Network access for explicit image/tool downloads; optional agent testing also
  needs provider access and an approved AWS authentication method.
- A directory under your home that Docker can bind-mount. Do not use macOS
  `/tmp`: earlier testing observed empty mounts there.

Open **Bash** in the Hestia checkout. Keep this host shell for all numbered steps;
commands marked “inside the container” run in an attached shell instead.
Do not enable shell tracing or record credentials in terminal transcripts.

```sh
bash
```

Then, in that Bash shell:

```sh
HESTIA="$(pwd -P)"
uname -sm
git --version
mise --version
docker version
docker compose version
git rev-parse HEAD
cat fixtures/synthetic/mise.toml
```

Review the fixture config, then explicitly prepare its host toolchain:

```sh
(cd "$HESTIA/fixtures/synthetic" && mise trust && mise install && mise exec -- go version)
```

**Expect:** Docker reports a reachable server; Compose reports v2; host Go
matches `fixtures/synthetic/mise.toml`. Record host/runtime/tool versions and the
Hestia commit. Do not infer support from a successful version check alone.

Use only synthetic data. Source and Git metadata are host data, durable state is
not a cache, and persistence is not backup. Never mount a whole home directory,
credential directory or Docker socket to work around a failed step.

## 2. Create an isolated fixture

```sh
mkdir -p "$HOME/hestia-test-runs"
RUN="$(mktemp -d "$HOME/hestia-test-runs/run-XXXXXXXX")"
RUN="$(cd "$RUN" && pwd -P)"
export TMPDIR="$RUN"
export HESTIA_STATE_ROOT="$RUN/state"
MISE_TRUSTED_CONFIG_PATHS="$RUN" "$HESTIA/fixtures/bin/make-fixture.sh"
```

The helper prints progress, not just a path. Find its final `fixture ready:` line
and assign **that exact absolute path**, without the prefix:

```sh
# Replace this example with the path printed by your run.
FIXTURE="$RUN/hestia-fixture-XXXXXXXX"
REPO="$FIXTURE/repo"
COMPOSE="$RUN/workspace.yaml"
test -d "$REPO/.git" || exit 1
cat "$FIXTURE/FIXTURE.txt"
git -C "$REPO" status --short
"$HESTIA/fixtures/bin/fixture-snapshot.sh" compare "$REPO" "$FIXTURE/snapshots/00-created" || exit 1
```

**Expect:** fixture creation completes its native build/test; the synthetic
checkout at `$REPO` has staged, unstaged and untracked changes; both linked
worktrees exist under `$FIXTURE/worktrees`; snapshot comparison exits zero.
The dirty fixture tree is intentional; fixture creation must not modify the
real Hestia checkout at `$HESTIA`.

The command deliberately trusts only the newly created synthetic tree, following
the [workspace walkthrough](../workspace/README.md#fixture-walkthrough). Inspect
real repositories before trusting their configuration; do not disable trust
controls globally. Only use a fixture that reaches `fixture ready:`.

## 3. Build and inspect the workspace

Build explicitly from the canonical Dockerfile. The local tag below is for this
runbook; it is not a published release.

```sh
IMAGE="hestia-fixture-tools:tester"
time docker build --target fixture-tools -t "$IMAGE" "$HESTIA"
docker image inspect "$IMAGE" --format '{{.Id}} {{.Os}}/{{.Architecture}} user={{.Config.User}}'
"$HESTIA/workspace/workspace-compose.sh" --image "$IMAGE" --out "$COMPOSE" "$REPO"
cat "$COMPOSE"
"$HESTIA/workspace/workspace-lifecycle.sh" validate "$COMPOSE"
```

**Expect:** image build and validation exit zero; the image is Linux arm64 with
a non-root default user. The Compose definition has a checkout-derived
`hestia-…` project name, the checkout mounted at its identical absolute path,
workspace-scoped durable state under `$RUN/state`, and a `linux-caches` volume.
It must not expose host home, sibling source, Docker socket or published ports.
The omp state mount is described in the workspace reference; it does not mean
omp is installed in the fixture-tools image. Agent provider policy is baked into
the agent image as a config overlay, not mounted over writable user settings.

Read the generated top-level `name:` and derive the project name:

```sh
PROJECT="$(sed -n 's/^name: //p' "$COMPOSE")"
STATE="$HESTIA_STATE_ROOT/$PROJECT"
test -f "$STATE/identity.record" || exit 1
docker compose -p "$PROJECT" -f "$COMPOSE" config
```

Keep `-p "$PROJECT"` on direct Compose commands so an ambient
`COMPOSE_PROJECT_NAME` cannot redirect the test. Lifecycle helpers handle this
internally. Keep generated configuration, state and evidence outside the Hestia
build context, as above; ignore rules are not a security boundary.

## 4. Start, attach and build

```sh
time "$HESTIA/workspace/workspace-lifecycle.sh" start "$COMPOSE"
BEFORE="$(docker compose -p "$PROJECT" -f "$COMPOSE" ps -q workspace)"
test -n "$BEFORE" || exit 1
docker inspect "$BEFORE" --format '{{json .Mounts}}'
"$HESTIA/workspace/workspace-lifecycle.sh" attach "$COMPOSE"
```

Inside the container:

```sh
pwd
id
git status --short
cat mise.toml
mise trust
mise exec -- go version
mise exec -- go build ./...
mise exec -- go test ./...
exit
```

**Expect:** the working directory equals `$REPO`; UID is nonzero; Git sees the
same dirty tree; build/test pass. Inspect actual mounts as well as configuration.
Tool installation belongs to the explicit build step, not startup. Repository
trust is deliberate and must be repeated in each replacement container.

Back on the host:

```sh
"$HESTIA/fixtures/bin/fixture-snapshot.sh" compare "$REPO" "$FIXTURE/snapshots/00-created" || exit 1
```

**Expect:** comparison exits zero. Builds have not changed source or Git state;
Linux Go caches live in the workspace cache volume rather than host source.

## 5. Check writes in both directions

On the host:

```sh
printf 'written on host\n' > "$REPO/host-marker.txt"
"$HESTIA/workspace/workspace-lifecycle.sh" attach "$COMPOSE"
```

Inside the container:

```sh
cat host-marker.txt
printf 'written in container\n' > container-marker.txt
git add container-marker.txt
git diff --cached -- container-marker.txt
exit
```

Back on the host:

```sh
cat "$REPO/container-marker.txt"
git -C "$REPO" diff --cached -- container-marker.txt
printf 'durable tester marker\n' > "$STATE/tester-marker.txt"
"$HESTIA/workspace/workspace-lifecycle.sh" attach "$COMPOSE" cat "$STATE/tester-marker.txt"
"$HESTIA/fixtures/bin/fixture-snapshot.sh" capture "$REPO" "$FIXTURE/snapshots/01-before-recreate"
cp "$STATE/tester-marker.txt" "$RUN/expected-state-marker.txt"
cp "$STATE/identity.record" "$RUN/expected-identity.record"
```

**Expect:** both sides see the marker contents and staged diff, without changing
host ownership. The container reads the durable marker. The new snapshot includes
your deliberate edits; use it, not `00-created`, for subsequent comparisons.
Only one writer should modify this checkout at a time.

## 6. Stop/start, then recreate

Finish attached commands first. These operations interrupt container processes.

```sh
"$HESTIA/workspace/workspace-lifecycle.sh" stop "$COMPOSE"
"$HESTIA/workspace/workspace-lifecycle.sh" start "$COMPOSE"
RESTARTED="$(docker compose -p "$PROJECT" -f "$COMPOSE" ps -q workspace)"
test "$BEFORE" = "$RESTARTED" || exit 1
"$HESTIA/workspace/workspace-lifecycle.sh" recreate "$COMPOSE"
AFTER="$(docker compose -p "$PROJECT" -f "$COMPOSE" ps -q workspace)"
test -n "$AFTER" || exit 1
test "$BEFORE" != "$AFTER" || exit 1
"$HESTIA/fixtures/bin/fixture-snapshot.sh" compare "$REPO" "$FIXTURE/snapshots/01-before-recreate" || exit 1
cmp "$RUN/expected-state-marker.txt" "$STATE/tester-marker.txt" || exit 1
cmp "$RUN/expected-identity.record" "$STATE/identity.record" || exit 1
"$HESTIA/workspace/workspace-lifecycle.sh" attach "$COMPOSE"
```

Inside the replacement container:

```sh
mise trust
mise exec -- go build ./...
mise exec -- go test ./...
exit
```

**Expect:** stop/start keeps the container ID; recreation changes it. Snapshot and
both `cmp` checks exit zero before resumed work; build/test pass again. Record old
and new IDs. A new container alone does not prove persistence.

## 7. Clear only this fixture's Linux caches

Do this only against the generated disposable fixture workspace, after finishing
active commands. Do not use Docker prune or `down -v`.

```sh
"$HESTIA/workspace/workspace-lifecycle.sh" clear-caches "$COMPOSE"
"$HESTIA/fixtures/bin/fixture-snapshot.sh" compare "$REPO" "$FIXTURE/snapshots/01-before-recreate" || exit 1
cmp "$RUN/expected-state-marker.txt" "$STATE/tester-marker.txt" || exit 1
cmp "$RUN/expected-identity.record" "$STATE/identity.record" || exit 1
"$HESTIA/workspace/workspace-lifecycle.sh" attach "$COMPOSE"
```

Inside the replacement container, check before rebuilding:

```sh
ls -la /hestia/cache
mise trust
mise exec -- go build ./...
mise exec -- go test ./...
ls -la /hestia/cache
exit
```

**Expect:** only this workspace's `linux-caches` volume is replaced; source/Git and
durable comparisons pass. Go caches regenerate and build/test pass. Confirm the
removal target in helper output; broader isolation checks are in the regression
suite below.

## 8. Check linked worktrees

Run this block once for `wt-abs`, then again with `wt-rel`. These are sequential
mount/Git checks, not proof of concurrent-worktree safety.

```sh
WT=wt-abs
WT_REPO="$FIXTURE/worktrees/$WT"
WT_COMPOSE="$RUN/$WT.yaml"
cp "$WT_REPO/.git" "$RUN/$WT.git-pointer.before"
cp "$REPO/.git/worktrees/$WT/gitdir" "$RUN/$WT.back-pointer.before"
"$HESTIA/identity/workspace-id.sh" "$REPO"
"$HESTIA/identity/workspace-id.sh" "$WT_REPO"
"$HESTIA/workspace/workspace-compose.sh" --image "$IMAGE" --out "$WT_COMPOSE" "$WT_REPO"
cat "$WT_COMPOSE"
"$HESTIA/workspace/workspace-lifecycle.sh" start "$WT_COMPOSE"
"$HESTIA/workspace/workspace-lifecycle.sh" attach "$WT_COMPOSE"
```

Inside the worktree container:

```sh
git rev-parse --git-dir --git-common-dir HEAD
printf 'worktree staging check\n' > worktree-marker.txt
git add worktree-marker.txt
git diff --cached -- worktree-marker.txt
exit
```

Back on the host:

```sh
git -C "$WT_REPO" diff --cached -- worktree-marker.txt
cmp "$RUN/$WT.git-pointer.before" "$WT_REPO/.git" || exit 1
cmp "$RUN/$WT.back-pointer.before" "$REPO/.git/worktrees/$WT/gitdir" || exit 1
"$HESTIA/workspace/workspace-lifecycle.sh" stop "$WT_COMPOSE"
"$HESTIA/workspace/workspace-lifecycle.sh" remove-runtime "$WT_COMPOSE"
```

**Expect:** main and worktree identities differ; Git operations agree inside and
outside; pointer comparisons exit zero for both layouts. The Compose file mounts
the worktree and required common `.git` metadata, not the main checkout's source.
Shared Git metadata is not a security boundary between mutually untrusted users.

## 9. Optional: real omp session persistence

This is a **manual acceptance leg**, not a previously verified authentication
recipe. The agent layer has been tested without credentials; actual AWS login,
refresh and real-session recreation remain to be demonstrated. Skip and record
“not run” if no approved credential flow is available. Do not invent a passing
result from the unauthenticated smoke test.

1. Build the optional target explicitly:

   ```sh
   AGENT_IMAGE="hestia-agent:tester"
   docker build --target agent -t "$AGENT_IMAGE" "$HESTIA"
   "$HESTIA/workspace/workspace-lifecycle.sh" stop "$COMPOSE"
   "$HESTIA/workspace/workspace-lifecycle.sh" remove-runtime "$COMPOSE"
   "$HESTIA/workspace/workspace-compose.sh" --image "$AGENT_IMAGE" --out "$COMPOSE" "$REPO"
   "$HESTIA/workspace/workspace-lifecycle.sh" start "$COMPOSE"
   "$HESTIA/workspace/workspace-lifecycle.sh" attach "$COMPOSE"
   ```

2. Inside, review/trust `mise.toml`, then run `omp --version` and `omp --help`.
   Provider policy permits Bedrock only. With no credentials, `omp -p hi` is
   expected to fail nonzero; verify `git status` still works afterwards.
3. Supply approved, scoped AWS credentials through the native AWS credential
   chain in the attached session. Host profiles/environment are **not**
   automatically forwarded by `attach`; setting a profile name alone does not
   make its host files available. The repository does not yet prescribe a tested
   SSO/profile/refresh setup. Record the method and prerequisites, never values.
   Do not bake credentials into images, generated Compose, source or logs, or
   mount your entire AWS/home directory. Environment credentials are accessible
   to processes using them; they are not a secret-isolation mechanism.
4. Invoke `omp` directly. Retain its native permission controls. Ask it to make a
   small reviewable fixture change, inspect the diff and run the Go build/tests.
   No commit, push or Git credentials are required.
5. Exit omp and the attached shell so state is quiescent. Capture a new source
   snapshot using `fixture-snapshot.sh capture` and a new snapshot directory.
   Record the session identifier privately. omp state lives at
   `$STATE/omp` on the host, mounted as `~/.omp` in the container. Treat its
   database, sessions, memory and logs as sensitive; do not attach them to issues.
6. Record the current container ID, recreate using the lifecycle helper, and
   compare the new source snapshot **before** resuming work. Confirm the ID
   changes. Reattach, repeat `mise trust`, and reauthenticate if required.
7. Run `omp --resume`, select the saved session and verify it contains the prior
   conversation and can continue the same task. Rerun build/tests. Record real
   resumption separately from mere survival of files under `$STATE/omp`.
8. Exercise credential expiry/refresh only through the approved native flow.
   Record pass/fail/not run independently; successful initial login does not prove
   refresh. Keep Git authentication separate if later testing requires it.

## 10. Record results and stop safely

Record a row for each requirement below, using **pass**, **fail**, **partial** or
**not run**, plus command, exit status and sanitized evidence. Do not copy the
historical evidence log's status into a new run.

| Requirement | Evidence to record |
| --- | --- |
| M1-01 image/tools | Commit, image ID/architecture/user, versions, build/test results, build and warm-start timings (note cache use; a cached build is not a cold build) |
| M1-02 mounts | Actual mounts, host/container write and Git agreement; no broad mounts/socket |
| M1-03 ownership/artifacts | Non-root writes, unchanged source after builds, separate Linux caches |
| M1-04 identity | Main/worktree IDs; use regression suite for same-basename, symlink and mismatch cases |
| M1-05 worktrees | Absolute/relative Git operations and unchanged pointer files |
| M1-06 lifecycle | Container IDs, source/Git and durable comparisons, resumed build/test |
| M1-07 agent | Auth method without secrets, real assisted change and resumed session, refresh status |
| M1-08 caches | Scoped removal, preserved source/state and successful regeneration |
| M1-09 failures | Exact failure/recovery observations; regression output for covered error cases |

These manual checks are not exhaustive acceptance. Missing auth, offline behavior,
identity failures and other boundaries need their own evidence. The Argus pilot
remains separate: run it only on the employer laptop with its real workflow and
keep proprietary details there. Fixture success does not close Milestone 1.

On the host, stop and remove the main runtime after retaining evidence:

```sh
"$HESTIA/workspace/workspace-lifecycle.sh" stop "$COMPOSE"
"$HESTIA/workspace/workspace-lifecycle.sh" remove-runtime "$COMPOSE"
printf 'Retained test data: %s\n' "$RUN"
```

**Expect:** containers are removed, but source, Git metadata, state and cache
volumes remain. Worktree runtimes should already have been removed in step 8.
If a run stopped early, use its own saved Compose file to stop/remove that runtime
before handling its host data. This is intentionally not a destructive reset.

Keep failed runs for diagnosis. Before manually deleting any storage, inspect
exact paths and resource names, retain useful evidence and handle agent state as
sensitive. Delete only this run's reviewed synthetic storage and identified cache
volumes; never global prune, broad recursive deletion or another checkout's data.
Do not delete `$RUN` while its containers still reference it.

## Automated regression checks

Run the existing suites from the Hestia checkout after preparing prerequisites
above. They complement, rather than replace, the manual real-agent journey. Use
fresh disposable storage; see each script for its cleanup behavior. Record each
suite's exit status and actual result count, not a fixed historical total.

Host-only checks need Git and Bash, not Docker or host Go:

```sh
bash "$HESTIA/tests/workspace-id.test.sh"
bash "$HESTIA/tests/fixture-snapshot.test.sh"
```

The Docker suites currently use fixed local image tags, not an image override.
Build those tags explicitly from the same Dockerfile (this may reuse build cache):

```sh
docker build --target fixture-tools -t hestia-fixture-tools:2026-09-09 "$HESTIA"
```

Run suites separately. Each creates its own fixture under `$HOME/.cache`, uses
host mise/Go, and needs Docker to share that location. Clear ambient Compose
overrides in a subshell; some suite calls use Compose directly.

```sh
(unset COMPOSE_PROJECT_NAME COMPOSE_FILE; KEEP_ARTIFACTS=1 bash "$HESTIA/tests/workspace-mounts.test.sh")
(unset COMPOSE_PROJECT_NAME COMPOSE_FILE; KEEP_ARTIFACTS=1 bash "$HESTIA/tests/workspace-lifecycle.test.sh")
(unset COMPOSE_PROJECT_NAME COMPOSE_FILE; KEEP_ARTIFACTS=1 bash "$HESTIA/tests/workspace-cache-clear.test.sh")
```

Optional agent-layer regression (no real credentials required):

```sh
docker build --target agent -t hestia-agent:2026-09-09 "$HESTIA"
(unset COMPOSE_PROJECT_NAME COMPOSE_FILE; KEEP_ARTIFACTS=1 bash "$HESTIA/tests/workspace-agent.test.sh")
```

**Expect:** each executed suite reports zero failed checks. **`SKIP` is not a
pass**, even when its exit code is zero: Docker suites can skip when their image
or runtime is unavailable. Fix prerequisites and rerun, or record “not run”.
`KEEP_ARTIFACTS=1` requests retained host artifacts for inspection; it does not
keep runtime containers alive. Inspect printed paths before deleting anything;
these suite artifacts are separate from the manual run's `$RUN`.

## Draft verification

2026-09-16, Darwin arm64: all 26 shell blocks parsed with `bash -n`; all 17
relative Markdown link occurrences across this runbook and the README resolved;
all 18 preservation checks use `|| exit 1`.

Before integrating newer `origin/main` changes, `bash tests/workspace-id.test.sh`
passed 19/19. `bash tests/workspace-lifecycle.test.sh` exercised real Docker
containers and passed 23/23, including a changed container ID,
source/Git/durable-state preservation and a successful post-recreation
build/test. This did not execute every manual step above or authenticate/resume
a real omp session.
