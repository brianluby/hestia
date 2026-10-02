# XJVWF4K: remaining native agent acceptance

[Workspace workflow](../workspace/README.md) · [Current regression evidence](aws-handoff-evidence.md)

The optional omp layer and writable scoped state already exist. Native
regressions passed 24/24 on 2026-10-02; real authentication, an agent-assisted
change and native resume remain blocked by unavailable AWS credentials.
Use only a fresh synthetic fixture, never employer source. Keep credentials
and raw sessions/provider responses out of evidence.

1. Create the [fixture](../fixtures/README.md) on a Docker-shared path; record
   Hestia commit, platform, image ID and scoped resources. Build explicitly
   with the canonical Dockerfile's `agent` target, generate Compose for
   `<fixture>/repo`, and start it with the existing lifecycle helper.
2. On the host, refresh a scoped temporary AWS session. Attach with
   `workspace/workspace-attach-aws.sh --profile <profile> --region <region> <file>`
   (host AWS CLI v2/jq) or `--env` (already exported temporary keys and region).
   Inspect/trust this known fixture's mise config with `mise trust`, then
   invoke `omp` directly. Keep its native permissions and provider selection.
3. Ask omp to add a small greeting behavior with a corresponding Go test,
   preserving the fixture's existing staged/unstaged/untracked work. Review
   `git diff` on host and container; run `mise exec -- go build ./...` and
   `mise exec -- go test ./...` in the container. Record exit statuses and
   sanitized result summaries, not the agent transcript.
4. Exit omp cleanly and finish active commands. Record its actual session
   ID/path privately; snapshot source/Git with the fixture helper and hash
   the selected JSONL session and settings while the agent is stopped.
   Capture the old container ID. No database dump or credential-tree copy.
5. Run `workspace/workspace-lifecycle.sh recreate <file>`. Require a different
   container ID and no unintended source/Git/settings/session differences
   **before resumed work**. Reattach with a new explicit credential handoff
   and re-trust the fixture's mise config.
6. Run `omp --resume <session-id-or-path>` and verify the actual saved
   conversation/history and prior fixture change. Ask it for a further small
   test-backed change, review the diff, and build/test again. Record native
   resume and authenticated inference separately from file persistence.
7. In a separate ordinary attach without handoff, verify missing auth still
   blocks omp while shell/source/Git remain usable. End credential-bearing
   shells to remove their environment; host revocation/refresh is separate.
   Verify source, selected session state and unrelated workspaces survive.

For pinned omp 18.1.16, sessions live at
`~/.omp/agent/sessions/<encoded-cwd>/<timestamp>_<sessionId>.jsonl`; terminal
breadcrumbs live under `~/.omp/agent/terminal-sessions/`. `omp --resume`
without an argument opens a picker. `omp --continue` may create a fresh
session if none exists, so use an explicit saved ID/path for the proof.
`--no-session` cannot prove durable resume. Primary sources:
[session format](https://github.com/can1357/oh-my-pi/blob/61b1b8aef634334eaf1412afd003a763e1d1b9c1/docs/session.md),
[native session operations](https://github.com/can1357/oh-my-pi/blob/61b1b8aef634334eaf1412afd003a763e1d1b9c1/docs/session-operations-export-share-fork-resume.md).

Until those observations exist, XJVWF4K remains incomplete. This fixture
journey does not close the employer-local Argus pilot or Milestone 1.
