# AWCEX5Z: bounded LiteLLM routing and cold native lookup

Observed 2026-10-02 on macOS 27.0.1 (26A434), Darwin 27.0.0 arm64,
Docker client 29.8.2/server 29.5.2, Compose 5.5.1, native omp 18.1.16.
This successor preserves [the earlier receipt](litellm-handoff-evidence.md)
unchanged and corrects its native invocation/discovery limits.

Immutable implementation: `dda0065935d607cdccad99ca06b3b92b762523f7`.
Final evidence branch: `codex/awc-litellm-verified`. Evidence-only changes
retain exactly that commit's helper, suite, stub, README and Dockerfile blobs.

Commands and results:

- `rtk proxy env KEEP_ARTIFACTS=1 bash tests/workspace-litellm.test.sh`:
  **28 passed, 0 failed**, exit 0, no SKIP, at the immutable implementation.
- `rtk proxy bash -n workspace/workspace-attach-litellm.sh tests/workspace-litellm.test.sh`
  and `rtk git diff --check`: exit 0.
- `rtk git diff --exit-code dda0065935d607cdccad99ca06b3b92b762523f7 -- workspace/workspace-attach-litellm.sh workspace/README.md tests/workspace-litellm.test.sh tests/litellm-stub.go Dockerfile`:
  exit 0 on the final evidence branch.

| Tested file | SHA-256 |
| --- | --- |
| LiteLLM helper | `89592d3bf7c19e0c89f82289de53b0683a6e9be37f6c0a22bdf61c19c211badd` |
| LiteLLM suite | `e13942b4df5f73361fbf63dbb80a1f5b3159fc262e3193d76c580d7dd32a7668` |
| Localhost Go stub | `d3605d30fcee13d863c33f334a0cac157e09025e3cb170e7244df89134ec1c63` |
| Dockerfile | `994c4d245a663fae06a959f1157522320c5371c9ba69754b4c3a0cf4f827c86a` |

Existing canonical image `hestia-agent:litellm-handoff`, linux/arm64:
`sha256:96d5aa9cb84db4de6d2e39954356552649a7b46f04789ecc59725264ebfcb9e8`.
The image/native binary were unchanged; this successor did not rebuild them.

The cold control began with no default agent directory, database or model
catalog. A test-only Compose override disabled external networking. The
existing image's Go compiled a disposable localhost HTTP/SSE stub. Only
`HESTIA_FAKE_LITELLM_KEY` was supplied. Native discovery followed by qualified
`litellm/hestia-opaque-model-7e4/sub:exact` main/small/slow selection completed
an actual native response with zero tools and `--no-session`; no JSONL was
created. A missing exact ID rejected before inference. Ordinary native
setupVersion/theme config commands and SQLite state then remained usable;
native session creation and explicit JSONL `--resume` produced two completed
assistant responses in one session. These are protocol checks, not real agent
acceptance.

Before key forwarding, conflict controls rejected all three default custom
model filenames, dangling symlinks, dotenv files, caller routing/role/profile/
storage/extension/hook/API-key overrides, stored active LiteLLM auth, unknown
schema, legacy auth/settings, broker keys and unsafe YAML. Test-owned files
and rows remained intact. Read-only SQL selects metadata only; safe host
Python/SQLite and Ruby/Psych checks add no installed dependencies. Native
permissions/session controls remain native. See [the bounded usage contract](../workspace/README.md#opt-in-litellm-handoff).

Native warmup is necessary under this pinned provider policy. A qualified-only
cold diagnostic failed with model not found; `omp models litellm --json
--no-extensions` warms the native catalog before launch and may contact the
selected endpoint when uncached/stale. Raw discovery payloads/errors are
suppressed. Endpoint/key values remain absent from Docker argv, tracing,
Compose, selected durable state and image/container configuration. Separate
attaches and recreation received no session credentials. Actual fixture
`go build ./...` and `go test -count=1 ./...` passed; recreation preserved native
settings/marker and still required explicit native mise trust. Native saved-session
creation/resume completed before recreation. Post-recreation checks covered
marker/settings/key isolation and native `--version` after trust; no further
native session response or inference ran after recreation.

The default scoped profile rejects exported XDG/native-path redirection.
Pinned [directory resolution](https://github.com/can1357/oh-my-pi/blob/61b1b8aef634334eaf1412afd003a763e1d1b9c1/packages/utils/src/dirs.ts#L339-L372)
uses XDG data storage only when its environment variable is set; an existing
`~/.local/share/omp` alone does not redirect it. The unnecessary presence
restriction probe `b83f4f28ddbf7ec181481625d36ad6e6b27f9772` remains preserved
on `codex/awc-litellm-handoff`, outside the final branch.

Final receipts: `/Users/bluby/.cache/hestia-litellm-tests/run-kvzpYiB2`.
Earlier diagnostic receipts remain: `run-0d7i2CxQ` (qualified-only cold limit),
`run-xY4LQD4A` (missing-agent guard), `run-AZuDqg54` (AND-list file guard),
and `run-pma5hNBC` (corrected 28-check diagnostic). The separate conservative
probe receipt `run-YlomodDu` is historical, not the final implementation.

Cleanup for exact project `hestia-repo-18e5eac0e253`: Compose `ps -q` returned
empty (exit 0); exact cache-volume inspect returned no such volume (exit 1).
Only test-owned resources were removed; synthetic receipts/state remain.

**Not run:** real endpoint requests, actual user-key access, authenticated
agent edits, or real endpoint session acceptance. This fixed-response stub
proves cold lookup and native protocol persistence only. Real acceptance
requires separately authorized endpoint/model/key execution.
