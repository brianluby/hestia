#!/usr/bin/env bash
# AWCEX5Z — synthetic LiteLLM exec-session plumbing; no endpoint calls.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image="${HESTIA_LITELLM_TEST_IMAGE:-hestia-agent:litellm-handoff}"
docker info >/dev/null 2>&1 || { echo 'SKIP: Docker unreachable'; exit 0; }
docker image inspect "$image" >/dev/null 2>&1 || { echo "SKIP: image $image absent"; exit 0; }
mkdir -p "$HOME/.cache/hestia-litellm-tests"
root="$(mktemp -d "$HOME/.cache/hestia-litellm-tests/run-XXXXXXXX")"
project=''
pass=0
fail() { echo "FAIL - $*" >&2; exit 1; }
ok() { echo "ok - $*"; pass=$((pass+1)); }
cleanup() {
	local status=$?
	if [ -n "$project" ]; then
		docker compose -p "$project" -f "$root/ws.yml" down --timeout 1 >/dev/null 2>&1 || true
		docker volume rm "${project}_linux-caches" >/dev/null 2>&1 || true
	fi
	if [ "$status" -ne 0 ] || [ "${KEEP_ARTIFACTS:-0}" = 1 ]; then echo "receipts: $root"; else rm -rf "$root"; fi
}
trap cleanup EXIT
mkdir -p "$root/repo" "$root/bin"
cp -R "$here/fixtures/synthetic/." "$root/repo/"
git -C "$root/repo" init -q
HESTIA_STATE_ROOT="$root/state" "$here/workspace/workspace-compose.sh" --image "$image" --out "$root/ws.yml" "$root/repo"
project="$(sed -n 's/^name: //p' "$root/ws.yml")"
"$here/workspace/workspace-lifecycle.sh" start "$root/ws.yml" >"$root/start.log" 2>&1
dc() { docker compose -p "$project" -f "$root/ws.yml" "$@"; }
attach="$here/workspace/workspace-attach-litellm.sh"
{
	echo "tested-head: $(git -C "$here" rev-parse HEAD)"
	shasum -a 256 "$attach" "$here/Dockerfile"
	sw_vers 2>/dev/null || true
	uname -srm
	docker version --format 'client: {{.Client.Version}} server: {{.Server.Version}}'
	docker compose version
	docker image inspect --format 'image: {{.Id}} architecture: {{.Architecture}}' "$image"
} >"$root/environment.txt"
cat "$root/environment.txt"
dc exec -T workspace mise trust "$root/repo" >/dev/null
endpoint=https://hestia.invalid/v1
model=fixture/custom-model:exact
unset LITELLM_API_KEY LITELLM_BASE_URL
if "$attach" --endpoint "$endpoint" --model "$model" --no-tty "$root/ws.yml" --version >"$root/missing.log" 2>&1; then fail 'missing key accepted'; fi
grep -q 'export a scoped nonempty LITELLM_API_KEY' "$root/missing.log" || fail 'missing key error not actionable'
ok 'missing exported key rejected without exposing values'
export LITELLM_API_KEY=HESTIA_FAKE_LITELLM_KEY
for invalid in 'http://user:HESTIA_FAKE_PASSWORD@host/v1' 'https://host/v1?key=HESTIA_FAKE_QUERY' 'https://host/v1#fragment' 'file:///v1' 'https:///v1' 'http://host:65536/v1' $'https://host/v1\nsecond-line'; do
	if "$attach" --endpoint "$invalid" --model "$model" --no-tty "$root/ws.yml" --version >"$root/url-error.log" 2>&1; then fail 'invalid URL accepted'; fi
	if grep -q HESTIA_FAKE_ "$root/url-error.log"; then fail 'invalid URL value printed'; fi
done
ok 'URL rejects credentials, query, fragment, wrong scheme, missing host, invalid port and line breaks'
for invalid in '-bad' 'bad model' $'valid\nsecond'; do
	if "$attach" --endpoint "$endpoint" --model "$invalid" --no-tty "$root/ws.yml" --version >"$root/model-error.log" 2>&1; then fail 'invalid model accepted'; fi
done
ok 'model rejects option-like IDs, whitespace and line breaks'
"$attach" --endpoint "$endpoint" --model "$model" --no-tty "$root/ws.yml" --version >"$root/native-version.log" 2>&1 || fail 'native version invocation failed'
grep -Eq '^(omp/)?18[.]1[.]16$' "$root/native-version.log" || fail 'wrong native version'
ok 'native omp version executes through opted-in attach without inference'
bash -x "$attach" --endpoint "$endpoint" --model "$model" --no-tty "$root/ws.yml" --version >"$root/trace.log" 2>&1 || fail 'traced caller failed'
if grep -q HESTIA_FAKE_ "$root/trace.log"; then fail 'secret in enabled trace'; fi
ok 'caller-enabled trace suppressed before secret access'

# Observe the helper's exact native argv, then use the same real Docker exec
# environment for an assertion-only shell instead of making a model call.
real_docker="$(command -v docker)"
cat >"$root/bin/docker" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >>"$LITELLM_TEST_ARGS"
args=("$@")
for ((i=0; i<${#args[@]}-1; i++)); do
	if [ "${args[$i]}" = workspace ] && [ "${args[$((i+1))]}" = omp ]; then
		exec "$LITELLM_TEST_DOCKER" "${args[@]:0:$((i+1))}" bash -c '
			test "$LITELLM_API_KEY" = HESTIA_FAKE_LITELLM_KEY &&
			test "$LITELLM_BASE_URL" = https://hestia.invalid/v1 &&
			test "$PI_CONFIG_FILES" = /opt/hestia/omp/litellm.yml &&
			test -z "${AWS_ACCESS_KEY_ID:-}" &&
			test -z "${OPENAI_API_KEY:-}" &&
			echo selected-durable-marker >/home/dev/.omp/handoff-marker'
	fi
done
exec "$LITELLM_TEST_DOCKER" "$@"
SH
chmod +x "$root/bin/docker"
export LITELLM_TEST_DOCKER="$real_docker"
PATH="$root/bin:$PATH" LITELLM_TEST_ARGS="$root/args.log" \
	AWS_ACCESS_KEY_ID=HESTIA_FAKE_UNRELATED_AWS OPENAI_API_KEY=HESTIA_FAKE_UNRELATED_OPENAI \
	"$attach" --endpoint "$endpoint" --model "$model" --no-tty "$root/ws.yml" --resume fixture-session >"$root/probe.log" 2>&1 || fail 'synthetic session environment forwarding failed'
ok 'real exec session receives endpoint/key/overlay and no unrelated host provider keys'
if grep -q 'HESTIA_FAKE_\|https://hestia.invalid' "$root/args.log"; then fail 'endpoint/key value in Docker argv'; fi
ok 'Docker argv forwards names, never endpoint/key values'
python3 - "$root/args.log" "$model" <<'PY'
import pathlib, sys
args = pathlib.Path(sys.argv[1]).read_text().splitlines()
start = args.index("omp")
model = sys.argv[2]
assert args[start:] == ["omp", "--provider", "litellm", "--model", model,
                       "--smol", "litellm/" + model, "--slow", "litellm/" + model,
                       "--resume", "fixture-session"], args[start:]
PY
ok 'exact caller model and native resume arguments reach provider/model/smol/slow roles'
dc exec -T workspace bash -c 'test -z "${LITELLM_API_KEY:-}" && test -z "${LITELLM_BASE_URL:-}" && test "$PI_CONFIG_FILES" = /opt/hestia/omp/config.yml' || fail 'credentials or overlay leaked into a separate attach'
ok 'separate attach retains default overlay and receives no LiteLLM credentials'
dc exec -T -e PI_CONFIG_FILES=/opt/hestia/omp/litellm.yml workspace omp config get disabledProviders >"$root/litellm-providers.json"
dc exec -T workspace omp config get disabledProviders >"$root/default-providers.json"
python3 - "$root" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
default = set(json.loads((root / "default-providers.json").read_text()))
opted = set(json.loads((root / "litellm-providers.json").read_text()))
assert "litellm" in default and "bedrock" not in default
assert "litellm" not in opted and "bedrock" in opted
assert opted == (default - {"litellm"}) | {"bedrock"}
PY
ok 'native effective overlay permits only LiteLLM and leaves default Bedrock policy unchanged'
setup="$(dc exec -T -e PI_CONFIG_FILES=/opt/hestia/omp/litellm.yml workspace omp config get setupVersion)"
[ "$setup" = 2 ] || fail 'opted-in setupVersion is not 2'
ok 'native opted-in onboarding completion marker is 2'
dc exec -T workspace bash -c 'test ! -w /opt/hestia/omp/litellm.yml && test ! -w /opt/hestia/omp && mkdir -p /home/dev/.omp/agent && printf "setupVersion: 0\n" >/home/dev/.omp/agent/config.tmp && mv /home/dev/.omp/agent/config.tmp /home/dev/.omp/agent/config.yml' || fail 'root overlay ownership or writable settings failed'
ok 'opted-in overlay is root-owned while native settings remain atomically writable'
dc exec -T workspace cat /opt/hestia/omp/config.yml >"$root/default-policy.yml"
cmp "$here/agent/omp/config.yml" "$root/default-policy.yml" || fail 'default provider policy bytes changed'
ok 'default provider policy byte-identical to existing source'

# Execute the canonical Dockerfile derivation against a seeded source policy
# in this disposable runtime. This catches integration with first-run defaults:
# setupVersion must occur once, and unrelated non-secret keys must survive.
derivation="$(python3 - "$here/Dockerfile" <<'PY'
import pathlib, sys
lines = pathlib.Path(sys.argv[1]).read_text().splitlines()
start = next(i for i, line in enumerate(lines) if line.startswith("RUN sed "))
step = []
for line in lines[start:]:
    step.append(line)
    if not line.endswith("\\"):
        break
print("\n".join(step)[4:])
PY
)"
dc exec -T --user root workspace sh -c 'cp /opt/hestia/omp/config.yml /tmp/default-policy-before-control && printf "\nsetupVersion: 2\ntheme:\n  dark: serius\n" >>/opt/hestia/omp/config.yml'
dc exec -T --user root workspace sh -c "$derivation" || fail 'canonical derivation failed with seeded setup marker'
[ "$(dc exec -T workspace grep -c '^setupVersion:' /opt/hestia/omp/litellm.yml)" = 1 ] || fail 'seeded marker duplicated'
[ "$(dc exec -T -e PI_CONFIG_FILES=/opt/hestia/omp/litellm.yml workspace omp config get setupVersion)" = 2 ] || fail 'seeded native overlay malformed'
dc exec -T -e PI_CONFIG_FILES=/opt/hestia/omp/litellm.yml workspace omp config get theme.dark >"$root/seeded-theme.txt"
grep -qx serius "$root/seeded-theme.txt" || fail 'extra nonsecret theme default lost'
dc exec -T --user root workspace sh -c 'mv /tmp/default-policy-before-control /opt/hestia/omp/config.yml'
dc exec -T --user root workspace sh -c "$derivation"
ok 'canonical derivation with seeded setupVersion remains native-valid, exactly once, and preserves extra defaults'
cid="$(dc ps -q workspace)"
docker inspect "$cid" >"$root/container-inspect.json"
docker image inspect "$image" >"$root/image-inspect.json"
if grep -R -q 'HESTIA_FAKE_' "$root/state" "$root/ws.yml" "$root/native-version.log" "$root/probe.log" "$root/container-inspect.json" "$root/image-inspect.json"; then fail 'synthetic secret stored at rest'; fi
ok 'no synthetic credential in Compose, selected state, native/helper logs or image/container configuration'
dc exec -T workspace bash -c 'go build ./... && go test -count=1 ./...' >"$root/build.log" 2>&1 || fail 'canonical fixture build/test failed'
ok 'fixture builds/tests on the canonical image'
"$here/workspace/workspace-lifecycle.sh" recreate "$root/ws.yml" >"$root/recreate.log" 2>&1
dc exec -T workspace bash -c 'test -z "${LITELLM_API_KEY:-}" && test -z "${LITELLM_BASE_URL:-}" && grep -qx selected-durable-marker /home/dev/.omp/handoff-marker && grep -qx "setupVersion: 0" /home/dev/.omp/agent/config.yml' || fail 'recreation leaked keys or lost selected state'
ok 'recreation retains selected marker/native settings and no session credentials'
"$attach" --endpoint "$endpoint" --model "$model" --no-tty "$root/ws.yml" --version >"$root/after-version.log" 2>&1 && fail 'recreation unexpectedly reused trusted mise state' || true
# Explicit trust remains native and per-container; it is not bypassed by helper.
dc exec -T workspace mise trust "$root/repo" >/dev/null
"$attach" --endpoint "$endpoint" --model "$model" --no-tty "$root/ws.yml" --version >"$root/after-version.log" 2>&1 || fail 'explicit re-trust did not restore native CLI'
ok 'explicit native mise trust works after recreation'
echo "passed: $pass, failed: 0; authenticated inference/session resume: NOT RUN"
