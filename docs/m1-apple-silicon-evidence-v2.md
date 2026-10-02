# 4AC12YE: Apple Silicon native LiteLLM proof

[Milestone 1](milestone-1.md) · [Machine-readable result](m1-apple-silicon-result-v2.json) · [Historical partial receipt](m1-apple-silicon-evidence.md)

Observed 2026-10-02: **the nonproprietary M1A fixture journey passes with
native omp and the user-authorized LiteLLM provider.** Two real agent edits,
independent behavior checks, builds/tests, container recreation and explicit
saved-session resume completed. Bedrock authentication, Argus and Windows/WSL2
remain unverified; Milestone 1 is incomplete. The earlier partial MD/JSON
receipts are preserved byte-for-byte.

Platform: macOS 27.0.1/Darwin 27.0.0 arm64; Docker client 29.8.2/server
29.5.2, Compose 5.5.1, Colima VF/aarch64/virtiofs. Tested implementation:
`bbb5b21cad68590612bb6a22f07e6956df99fa12`, stacked on PR19. Canonical
`agent` image `hestia-agent:4ac12ye-litellm-final-20261002`, linux/arm64:
`sha256:99434438c11a25bc5118dae8191a8bb5341fca277fadcfc407bb2bf0ca50e252`.
Versions: mise 2026.9.4, Go 1.27.1, omp 18.1.16. Source hashes and sanitized
commands, exits and timings are in the JSON receipt.

## Requirement results

| Requirement | Result in fixture scope | Evidence |
| --- | --- | --- |
| M1-01 | PASS | Final canonical cold/cached builds exit 0 in 48.329/0.212s. Pinned mise/cosign/omp integrity checks and mise provenance `Verified OK`; actual Go builds/tests pass. No browser IDE in the selected target. |
| M1-02 | PASS | Selected source, state, omp and classified-cache mounts; no host socket, broad home bind or published ports. Historical host/container writes and mount suite retained. Final actual agent edits are visible on the host. |
| M1-03 | PASS | Existing non-root UID 1000 write/artifact-separation evidence; final agent writes and native persisted state succeed. No host ownership repair. |
| M1-04 | PASS | Historical 19-check identity suite, including matching basenames, worktrees, branch/symlink behavior and conflicts. Final Compose retains the same recorded project identity across recreation. |
| M1-05 | PASS | Historical 31-check mount suite includes actual staging through absolute/relative links and unchanged pointers. The retained fixture's Git/worktree listing remains identical. Full concurrent workloads have separate acceptance. |
| M1-06 | PASS | First recreation before the second edit preserves source/Git snapshots and raw index. Additional persisted checkpoint verifies all 33 selected-state files, all 52 Git files, source inventory and nine source/Git snapshot files before native resume; container ID changes. |
| M1-07 | PASS | Real authenticated `litellm/qwen-27b-hf`, native Chat Completions, actual read/edit tools, successful final assistant events, same saved JSONL/header, recalled original context and repeated build/tests. Runtime handoff leaves no stored LiteLLM auth row or key match in the checked files. |
| M1-08 | PASS | Historical own-cache1098→0→1097 proof and12-check cache suite, with source/Git/native state preserved and regenerated build/tests. Final cleanup removes only the proof's classified cache. |
| M1-09 | PASS (applicable cases) | Historical missing-source/tool/metadata/state/identity/download negatives; real endpoint denies invalid auth with 401 and helper exits1, shell/source remain usable, fresh valid handoff succeeds. Missing key exits1 with an actionable export instruction. Port conflicts are N/A with no published services. Actual key expiry/automatic refresh were not tested. |

The historical foundation suites passed **101/101**, no failures or SKIP, at
`fccd1bd6cafd7d0410d1886742ea5dea7264f8c0` using their documented existing
image tags. They were not rerun against the final agent image; unchanged
foundation-helper hashes are checked in the successor JSON. The final
LiteLLM suite passed **34/34**, no failures or SKIP, against the final image.
Its isolated loopback stub checks native discovery/inference trace headers,
key handling, cache restoration, config conflicts, normal/failure/signal
cleanup, saved sessions and stdin behavior. Stub results are separate from
the real-provider observations below.

## Real journey and preservation

The first native turn finished in 23.059s and made two successful edits:
`Hello` trims surrounding whitespace and `TestHelloTrimsWhitespace` covers
normal and whitespace-only names. Native edit calls also reported25 rejected
attempts before success; these are retained in the tool counts, not hidden
as clean tool execution. The reviewed diff changes only `greet/greet.go` and
`greet/greet_test.go`. Staged comments/index, unrelated unstaged work and
untracked files remain. Build/test and a separately authored exported-function
probe pass.

After quiescing native omp, the fixture was recreated in 10.916s. Source/Git
snapshots and raw index compare identically before resumed work. Native omp
resumed the explicit existing JSONL and completed a second edit in 13.460s:
`HelloAll` preserves order, calls `Hello` and returns an empty slice for empty
input. Its tests and an independent probe cover ordered values, whitespace,
empty names, empty input and nil input. Both pass.

The second final reply omitted the requested context marker. A separate
no-tools turn on the same saved session, whose prompt did not contain the
marker, recalled it exactly in 3.980s. To retain a fully inspectable checkpoint,
one additional quiesced recreation was performed in 10.836s:

- Old container `712b2220f29c07b9a8bb603edf7bca7274f115407fd41ec1a7bbcb1dfc6cc24b`;
  new container `b17039543ea81ef3f44bf0e8d580056f61b824af72ac509f85e17a9fc48fd3a7`.
- All33 selected-state files and52 Git files, source bytes/modes, raw index,
  HEAD/branch/tree, staged tree/listing, status/untracked files and worktree
  metadata remain identical **before** resumed work. Snapshotting uses a copied
  index and `GIT_OPTIONAL_LOCKS=0`; the real index is hashed separately.
- Native session `01a0fc4d-1b5b-71b8-9172-fb95a9b72e64` has146 records before
  resume. Its JSONL SHA-256 is
  `b3767bc5afd0b02a832d39a6dcc1dae0930b41fe7252343b24b7d77fb83f42d0`.
  Raw index SHA-256 is
  `a067da73ed1db29de7bee9663807b128ad72e8250a8b2a1a995d0f8bd667cdab`.
- Explicit native resume recalls the original token again in 4.021s; all
  historical entry IDs/order, graph links, user/assistant content and other
  metadata remain. Three new records produce149 total. Native maintenance
  replaces one old read result with `[Superseded by a newer read of this file]`
  and adds `prunedAt`; a later read of the same path is verified. This happens
  after resume, not during recreation. The session is not claimed append-only.
- Build/test and the independent behavior probe pass again. All three
  build/test cycles and all three probes exit 0. The fixture is explicitly
  re-trusted through native mise after each recreation.

The pruning behavior is implemented by the pinned upstream
[pruning code](https://github.com/can1357/oh-my-pi/blob/61b1b8aef634334eaf1412afd003a763e1d1b9c1/packages/agent/src/compaction/pruning.ts#L243-L309)
and [session maintenance](https://github.com/can1357/oh-my-pi/blob/61b1b8aef634334eaf1412afd003a763e1d1b9c1/packages/coding-agent/src/session/session-maintenance.ts#L530-L573).
Raw catalogs, prompts and native transcripts remain private.

## Provider, credential and network boundaries

All successful dedicated-key calls use the approved HTTPS endpoint and
`x-litellm-trace-id`. Generic native OpenAI discovery retains the exact
advertised `qwen-27b-hf` ID; explicit `openai-completions` selects Chat
Completions. No custom model record or replacement agent engine is introduced.
Upstream catalog defaults for capabilities, context and output limits are not
backend qualification. `--no-tty --no-stdin` closes Docker exec stdin for scripted
JSON mode; upstream otherwise waits for nonterminal stdin EOF before a prompt.

Earlier bounded attempts using the rich-discovery Responses API and open
Docker stdin did not establish acceptance: one saved failed native session
reported an upstream404, and two outer commands timed out. Those private
receipts are retained. Final discovery/API/stdin fixes above are the tested path.

The dedicated key was held only by a temporary host process and supplied by
exec environment. It was absent from command arguments, prompts, generated
Compose, tracked config and builds. Native temporary `models.yml` uses only
environment references for key/trace and is removed with its owned lock after
exit. Separate ordinary attach contains no runtime key, URL or trace; it loads
the existing default overlay and can use source/Git. Native SQLite contains
zero LiteLLM auth rows. Literal-key scanning of the proof files, selected state,
image/container metadata, build receipts and managed checkout found zero
matches; this is a bounded at-rest check, not a claim about memory zeroization
or encrypted representations. Authorized agents/process inspectors can read
credentials supplied in their environment. Refresh/revocation stays under host
control; Git authentication is separate. State/transcripts remain sensitive.

macOS reached the local endpoint with verified TLS; direct Colima-container
LAN connectivity failed. The proof used a temporary loopback CONNECT transport
restricted to the exact approved host:443, with TLS passthrough and no request
logging or credential parsing. Only the fixture Compose received `HTTPS_PROXY`;
the canonical generator and Colima configuration were unchanged. This network
prerequisite must be resolved or supplied on another host; direct LAN access
is not claimed. No additional endpoint or published container port was used.

## Cleanup and retained receipts

Only project `hestia-repo-ce0a9e169ec7` runtime/network and its classified cache
volume were removed. Container listing is empty and volume inspection reports
absence. Source/Git and selected native state remain byte-identical through
cleanup and are retained for inspection; the image remains. Temporary host
credential and CONNECT processes are stopped, and the primary checkout's
original Dockerfile/runbook diff is preserved.

Private receipts: `/Users/bluby/.cache/hestia-m1-proofs/run-enryxux3`
(`auth-commands.json`, `auth-result.json`, persisted checkpoint, before/after
snapshots, native maintenance and cleanup results),
`/Users/bluby/.cache/hestia-litellm-tests/run-yj2Xj0yb`,
`/private/tmp/hestia-4ac12ye-litellm-final-build` and the historical foundation
receipt paths. One-off proof harnesses stay outside the repository; normal
workspaces use the existing Compose/mise/native-agent helpers.
