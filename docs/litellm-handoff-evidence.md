# AWCEX5Z: opt-in native LiteLLM handoff

Observed 2026-10-02 on macOS 27.0.1 (26A434) arm64, Docker client
29.8.2/server 29.5.2, Compose 5.5.1. This implements the user-selected
LiteLLM/OpenAI-compatible alternative while retaining the default Bedrock
overlay and existing scoped mounts.

Verified implementation commit:
`73c8f501c2fc4d0d297e4ea6f19a20cf2a49a109`
(follows initial helper commit `dae9df420f46c7af80df0e61ed758a4f11b3593c`).

Commands, all exit 0:

- `rtk proxy docker build --target agent -t hestia-agent:litellm-handoff .`
  built through the canonical Dockerfile. Existing pinned tool layers used
  cache; the new overlay derivation executed. This is not a new cold-download
  or provenance verification claim.
- `rtk proxy env KEEP_ARTIFACTS=1 bash tests/workspace-litellm.test.sh`
  on the verified commit: **18 passed, 0 failed**, no SKIP.
- `rtk proxy bash -n tests/workspace-litellm.test.sh workspace/workspace-attach-litellm.sh`
  and `rtk git diff --check` passed.

Final image `hestia-agent:litellm-handoff`:
`sha256:96d5aa9cb84db4de6d2e39954356552649a7b46f04789ecc59725264ebfcb9e8`,
linux/arm64, native omp 18.1.16. The image remains available for the real proof.

| Tested file | SHA-256 |
| --- | --- |
| Dockerfile | `994c4d245a663fae06a959f1157522320c5371c9ba69754b4c3a0cf4f827c86a` |
| LiteLLM helper | `89d3d13382f7bfec0fff2d7c1dee32c1fda3e82a3d3b05eaba0755dd6ee77942` |
| LiteLLM suite | `2aa1431c3b9354da49832b64ab521e0d25f2ee7e90a0e122504c336521a41c1e` |

The helper requires an exported nonempty `LITELLM_API_KEY`, an explicit
`--endpoint` HTTP(S) hostname/IPv4 URL and exact `--model` ID. It rejects
userinfo, queries, fragments, invalid ports, whitespace and line breaks
without printing input values. Endpoint/key values stay out of Docker argv
through bare `-e LITELLM_BASE_URL` and `-e LITELLM_API_KEY`; the selected
`PI_CONFIG_FILES` name is forwarded the same way.

Native invocation selects `--provider litellm`, the exact main model, and
`--smol litellm/<ID>` / `--slow litellm/<ID>`. Remaining arguments, including
native `--resume`, pass through without a replacement permission/session
engine. No host credential database, models file, home mount or secret file
is introduced. Runtime environment is available to the native process and
privileged inspection.

Native config reads verified that the root-owned opt-in overlay enables
LiteLLM and disables Bedrock, while ordinary attaches retain the byte-identical
default Bedrock overlay. The derived overlay has `setupVersion: 2`. A seeded
control executed the canonical Dockerfile derivation in disposable runtime
storage against a source policy already containing `setupVersion: 2` and
a nonsecret theme default. Pinned omp parsed exactly one setup marker and
retained the theme default. This verifies integration with first-run defaults;
it does not report an authenticated interactive onboarding journey.

Synthetic exec-session probes verified key/endpoint/policy delivery with no
unrelated host provider keys, trace suppression, exact native model/resume
arguments, and no synthetic secret in Compose, selected state, native/helper
logs or image/container configuration. The argv probe substituted an
assertion-only shell for inference; no fake native session was created. Actual
native version/config commands and fixture `go build ./...` /
`go test -count=1 ./...` ran successfully.

Recreation retained the selected marker and atomically writable native settings,
without retaining exec-session credentials. Native mise trust remained required
per container; explicit re-trust restored native CLI use. A separate disposable
control using the old agent image correctly rejected its missing LiteLLM overlay
before native execution, with an actionable build/recreate error and no key
value in the error.

Main receipts:
`/Users/bluby/.cache/hestia-litellm-tests/run-mvU9G2Jh`.
Missing-overlay control:
`/Users/bluby/.cache/hestia-litellm-tests/no-overlay-L0cYC7Y7`.
Test-owned containers, networks and cache volumes were removed; synthetic
receipts remain. Earlier harness attempts are preserved; assertions were
corrected to the observed bare version/scalar formats and native leaf setting
keys before the final complete run.

**Not run:** a real endpoint request, authenticated agent-assisted edit or
native saved-session resume. No actual key was read or transmitted for these
checks. Complete the separately authorized endpoint/model journey before
closing real agent acceptance. See [usage](../workspace/README.md#opt-in-litellm-handoff).
