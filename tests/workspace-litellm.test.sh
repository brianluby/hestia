#!/usr/bin/env bash
# AWCEX5Z — synthetic LiteLLM handoff; fake-key endpoint calls stay on localhost.
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
# Test-only loopback networking prevents native discovery from reaching any
# external endpoint. The canonical production generator is unchanged.
sed -i.bak '/^  workspace:$/a\
    network_mode: none
' "$root/ws.yml"
rm "$root/ws.yml.bak"
project="$(sed -n 's/^name: //p' "$root/ws.yml")"
"$here/workspace/workspace-lifecycle.sh" start "$root/ws.yml" >"$root/start.log" 2>&1
dc() { docker compose -p "$project" -f "$root/ws.yml" "$@"; }
attach="$here/workspace/workspace-attach-litellm.sh"
{
	echo "tested-head: $(git -C "$here" rev-parse HEAD)"
	shasum -a 256 "$attach" "$here/tests/workspace-litellm.test.sh" "$here/tests/litellm-stub.go" "$here/agent/omp/litellm-session.sh" "$here/Dockerfile"
	sw_vers 2>/dev/null || true
	uname -srm
	docker version --format 'client: {{.Client.Version}} server: {{.Server.Version}}'
	docker compose version
	docker image inspect --format 'image: {{.Id}} architecture: {{.Architecture}}' "$image"
} >"$root/environment.txt"
cat "$root/environment.txt"
dc exec -T workspace mise trust "$root/repo" >/dev/null
dc exec -T workspace bash -c 'cat >/tmp/hestia-litellm-stub.go' <"$here/tests/litellm-stub.go"
dc exec -T workspace go build -o /tmp/hestia-litellm-stub /tmp/hestia-litellm-stub.go >"$root/stub-build.log" 2>&1 || fail 'localhost stub build failed'
dc exec -d workspace /tmp/hestia-litellm-stub
port="$(dc exec -T workspace bash -c 'for i in {1..30}; do if test -s /tmp/hestia-litellm-stub.port; then cat /tmp/hestia-litellm-stub.port; exit 0; fi; sleep 0.1; done; exit 1')" || fail 'localhost stub not ready'
endpoint="http://127.0.0.1:$port/v1"
model=hestia-opaque-model-7e4/sub:exact
trace_id=11111111-2222-4333-8444-555555555555
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
for invalid in HESTIA_FAKE_TRACE '-bad' '11111111-2222-4333-8444-55555555555' $'11111111-2222-4333-8444-555555555555\nsecond'; do
    if "$attach" --endpoint "$endpoint" --model "$model" --trace-id "$invalid" --no-tty "$root/ws.yml" --version >"$root/trace-id-error.log" 2>&1; then fail 'invalid trace ID accepted'; fi
    grep -q 'trace ID must be a UUID' "$root/trace-id-error.log" || fail 'trace ID error not actionable'
    if grep -q HESTIA_FAKE_ "$root/trace-id-error.log"; then fail 'invalid trace value printed'; fi
done
ok 'explicit trace ID rejects malformed/multiline values without printing them'
clean_transient() {
    dc exec -T workspace bash -c 'test ! -e "$HOME/.omp/agent/models.yml" && test ! -L "$HOME/.omp/agent/models.yml" && test ! -e "$HOME/.omp/agent/.hestia-litellm.lock" && test -z "$(find /tmp -maxdepth 1 -type d -name "hestia-litellm.*" -print -quit)"' || fail 'owned transient config or lock remained'
}
# Exercise real cold native lookup and a completed response using only a fake
# key and opaque model ID on a disposable in-container loopback stub.
dc exec -T workspace bash -c 'test ! -e "$HOME/.omp/agent" && test -z "$(find "$HOME/.omp" -name models.db -print -quit)"' || fail 'native discovery cache already exists'

"$attach" --endpoint "$endpoint" --model "$model" --trace-id "$trace_id" --no-tty "$root/ws.yml" \
    --no-session --no-tools --no-extensions --no-skills --no-lsp --no-title --max-time 45s -p 'Reply with the fixed local test response.' >"$root/cold-native.log" 2>&1 || fail 'cold native localhost completion failed'
grep -q HESTIA_LOCAL_STUB_OK "$root/cold-native.log" || fail 'completed localhost response missing'
dc exec -T workspace cat /tmp/hestia-litellm-stub.log >"$root/stub-requests.log"
grep -qx 'GET /model_group/info auth=true trace=true traceExact=true' "$root/stub-requests.log" || fail 'native discovery missed explicit trace header'
grep -qx 'POST /v1/chat/completions model=true auth=true trace=true traceExact=true tools=0 stream=true' "$root/stub-requests.log" || fail 'native completion missed exact ID, fake auth, trace or zero tools'
clean_transient
dc exec -T workspace bash -c 'test -z "$(find "$HOME/.omp" -name "*.jsonl" -print -quit)"' || fail 'no-session probe persisted a native session'
ok 'cold native discovery/completion receive explicit trace UUID with fake key, no tools/session and transient cleanup'


"$attach" --endpoint "$endpoint" --model "$model" --no-tty "$root/ws.yml" --version >"$root/native-version.log" 2>&1 || fail 'native version invocation failed'
grep -Eq '^(omp/)?18[.]1[.]16$' "$root/native-version.log" || fail 'wrong native version'
dc exec -T workspace cat /tmp/hestia-litellm-stub.log >"$root/default-trace-requests.log"
grep -q '^GET .* auth=true trace=true traceExact=false$' "$root/default-trace-requests.log" || fail 'default handoff missed generated valid UUID'
clean_transient
ok 'native version uses generated trace UUID and cleans transient configuration without inference'
if "$attach" --endpoint "$endpoint" --model HESTIA_FAKE_UNAVAILABLE_ID --no-tty "$root/ws.yml" -p 'No completion expected.' >"$root/unavailable-model.log" 2>&1; then fail 'unavailable exact ID accepted'; fi
grep -q 'exact selected model unavailable' "$root/unavailable-model.log" || fail 'unavailable model error not bounded'
if grep -q HESTIA_FAKE_ "$root/unavailable-model.log"; then fail 'unavailable model value printed'; fi
[ "$(dc exec -T workspace grep -c '^POST ' /tmp/hestia-litellm-stub.log)" = 1 ] || fail 'unavailable exact ID reached inference'
clean_transient
ok 'unavailable exact ID rejects after traced discovery, cleans config and starts no inference or value output'
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
	if [ "${args[$i]}" = workspace ] && [ "${args[$((i+1))]}" = bash ] && [ "${args[$((i+2))]:-}" = /opt/hestia/omp/litellm-session.sh ]; then
		exec "$LITELLM_TEST_DOCKER" "${args[@]:0:$((i+1))}" bash -c '
			test "$LITELLM_API_KEY" = HESTIA_FAKE_LITELLM_KEY &&
			[[ "$LITELLM_BASE_URL" = http://127.0.0.1:*/v1 ]] &&
			test "$PI_CONFIG_FILES" = /opt/hestia/omp/litellm.yml &&
			test "$HESTIA_LITELLM_TRACE_ID" = 11111111-2222-4333-8444-555555555555 &&
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
	"$attach" --endpoint "$endpoint" --model "$model" --trace-id "$trace_id" --no-tty "$root/ws.yml" --resume fixture-session >"$root/probe.log" 2>&1 || fail 'synthetic session environment forwarding failed'
ok 'real exec session receives endpoint/key/trace/overlay and no unrelated host provider keys'
if grep -q 'HESTIA_FAKE_\|http://127.0.0.1' "$root/args.log" || grep -q "$trace_id" "$root/args.log"; then fail 'endpoint/key/trace value in Docker argv'; fi
ok 'Docker argv forwards names, never endpoint/key/trace values'
python3 - "$root/args.log" "$model" <<'PY'
import pathlib, sys
args = pathlib.Path(sys.argv[1]).read_text().splitlines()
start = max(i for i, arg in enumerate(args) if arg == "/opt/hestia/omp/litellm-session.sh")
assert args[start - 1:] == ["bash", "/opt/hestia/omp/litellm-session.sh", sys.argv[2],
                          "--resume", "fixture-session"], args[start - 1:]
assert args[start - 3:start - 1] == ["HESTIA_LITELLM_TRACE_ID", "workspace"]
PY
ok 'exact caller model/resume reach image wrapper with bare trace environment'
# Exercise real image wrapper ownership/status/argv with test-owned omp, no HTTP.
cat >"$root/omp-probe" <<'SH_PROBE'
#!/usr/bin/env bash
set -euo pipefail
jq -e '.providers.litellm | .baseUrl == env.LITELLM_BASE_URL and .api == "openai-completions" and .discovery.type == "litellm" and .headers == {"x-litellm-trace-id":"HESTIA_LITELLM_TRACE_ID"} and (.apiKey == "LITELLM_API_KEY") and (.authHeader == true) and (has("models") | not)' "$HOME/.omp/agent/models.yml" >/dev/null
if grep -q HESTIA_FAKE_LITELLM_KEY "$HOME/.omp/agent/models.yml"; then exit 91; fi
if [ "$1" = models ]; then
    printf '%s\n' "$@" >/tmp/hestia-native-probe/discovery-args
    printf '{"models":[{"provider":"litellm","id":"hestia-opaque-model-7e4/sub:exact"}]}\n'
    exit 0
fi
printf '%s\n' "$@" >/tmp/hestia-native-probe/native-args
case "$HESTIA_WRAPPER_PROBE_ACTION" in
    fail) exit 42 ;;
    signal) kill -TERM "$PPID"; exit 0 ;;
    replace) rm "$HOME/.omp/agent/models.yml"; printf 'HESTIA_REPLACEMENT_NATIVE_CONFIG\n' >"$HOME/.omp/agent/models.yml" ;;
esac
SH_PROBE
dc exec -T workspace bash -c 'mkdir -p /tmp/hestia-native-probe; cat >/tmp/hestia-native-probe/omp; chmod 0700 /tmp/hestia-native-probe/omp' <"$root/omp-probe"
probe_wrapper() {
    local action="$1"; shift
    LITELLM_BASE_URL="$endpoint" HESTIA_LITELLM_TRACE_ID="$trace_id" HESTIA_WRAPPER_PROBE_ACTION="$action" \
        dc exec -T -e LITELLM_API_KEY -e LITELLM_BASE_URL -e HESTIA_LITELLM_TRACE_ID -e HESTIA_WRAPPER_PROBE_ACTION \
        -e PATH=/tmp/hestia-native-probe:/usr/local/bin:/usr/bin:/bin workspace \
        bash /opt/hestia/omp/litellm-session.sh "$model" "$@"
}
probe_wrapper ok --resume fixture-session >"$root/wrapper-probe.log" 2>&1 || fail 'wrapper probe failed'
dc exec -T workspace cat /tmp/hestia-native-probe/discovery-args >"$root/discovery-args.log"
dc exec -T workspace cat /tmp/hestia-native-probe/native-args >"$root/native-args.log"
python3 - "$root" "$model" <<'PY_WRAPPER'
import pathlib, sys
root = pathlib.Path(sys.argv[1]); model = "litellm/" + sys.argv[2]
assert (root / "discovery-args.log").read_text().splitlines() == ["models", "litellm", "--json", "--no-extensions"]
assert (root / "native-args.log").read_text().splitlines() == ["--no-extensions", "--model", model,
    "--smol", model, "--slow", model, "--resume", "fixture-session"]
PY_WRAPPER
clean_transient
ok 'wrapper keeps env-reference-only config during native commands and launches qualified exact roles/resume'
for action in fail signal; do
    if probe_wrapper "$action" --version >"$root/wrapper-$action.log" 2>&1; then fail 'wrapper lost failure/signal status'; else status=$?; fi
    if [ "$action" = fail ]; then [ "$status" = 42 ] || fail 'native exit status changed'; else [ "$status" = 143 ] || fail 'caught TERM status changed'; fi
    clean_transient
done
ok 'native failure/caught TERM preserve status and clean owned config/lock'
dc exec -T workspace bash -c 'mkdir "$HOME/.omp/agent/.hestia-litellm.lock"; printf "HESTIA_OTHER_HANDOFF\n" >"$HOME/.omp/agent/.hestia-litellm.lock/owner"; rm /tmp/hestia-native-probe/native-args'
if probe_wrapper ok --version >"$root/concurrent-wrapper.log" 2>&1; then fail 'concurrent handoff accepted'; fi
grep -q 'another or interrupted LiteLLM handoff owns scoped state' "$root/concurrent-wrapper.log" || fail 'concurrent error not actionable'
dc exec -T workspace bash -c 'set -e; grep -qx HESTIA_OTHER_HANDOFF "$HOME/.omp/agent/.hestia-litellm.lock/owner"; test ! -e "$HOME/.omp/agent/models.yml"; test ! -e /tmp/hestia-native-probe/native-args; rm "$HOME/.omp/agent/.hestia-litellm.lock/owner"; rmdir "$HOME/.omp/agent/.hestia-litellm.lock"' || fail 'concurrent guard touched owner or ran native inference'
clean_transient
ok 'concurrent wrapper rejects before native execution and preserves another lock'
probe_wrapper replace --version >"$root/replaced-config.log" 2>&1 || fail 'replacement probe failed'
dc exec -T workspace bash -c 'set -e; grep -qx HESTIA_REPLACEMENT_NATIVE_CONFIG "$HOME/.omp/agent/models.yml"; test ! -e "$HOME/.omp/agent/.hestia-litellm.lock"; rm "$HOME/.omp/agent/models.yml"' || fail 'cleanup removed replacement native file'
clean_transient
ok 'cleanup preserves a replacement native configuration file'
# Every default model filename must reject before a credential
# environment exec. Files are test-owned sentinels, not parsed or rewritten.
for conflict in agent/models.yml agent/models.yaml agent/models.json; do
    dc exec -T workspace bash -c 'mkdir -p "$(dirname "$HOME/.omp/$1")"; printf "HESTIA_FAKE_CONFLICT_CONTENT\n" >"$HOME/.omp/$1"' bash "$conflict"
    PATH="$root/bin:$PATH" LITELLM_TEST_ARGS="$root/conflict-args.log" \
        "$attach" --endpoint "$endpoint" --model "$model" --no-tty "$root/ws.yml" --version >"$root/conflict.log" 2>&1 && fail 'custom model configuration accepted'
    grep -q 'custom model files' "$root/conflict.log" || fail 'conflict error not actionable'
    if grep -q 'HESTIA_FAKE_' "$root/conflict.log"; then fail 'conflict contents printed'; fi
    if grep -q '^LITELLM_API_KEY$' "$root/conflict-args.log"; then fail 'key environment forwarded despite conflict'; fi
    dc exec -T workspace bash -c 'grep -qx HESTIA_FAKE_CONFLICT_CONTENT "$HOME/.omp/$1"' bash "$conflict" || fail 'conflicting native file changed'
    dc exec -T workspace bash -c 'rm "$HOME/.omp/$1"' bash "$conflict"
    rm "$root/conflict-args.log"
done
ok 'all default native model filenames reject before key handoff without reading, printing or changing files'

state="$(dc config --format json | python3 -c 'import json,sys; print(next(m["source"] for m in json.load(sys.stdin)["services"]["workspace"]["volumes"] if m.get("target") == "/home/dev/.omp"))')"
agent="$state/agent"
blocked() {
    rm -f "$root/blocked-args.log"
    if PATH="$root/bin:$PATH" LITELLM_TEST_ARGS="$root/blocked-args.log" \
        "$attach" --endpoint "$endpoint" --model "$model" --no-tty "$root/ws.yml" "$@" >"$root/blocked.log" 2>&1; then fail 'unsupported state or override accepted'; fi
    grep -Eq 'unsupported|stored native|broker selection' "$root/blocked.log" || fail 'blocked error not actionable'
    if grep -q HESTIA_FAKE_ "$root/blocked.log"; then fail 'blocked values exposed'; fi
    if [ -f "$root/blocked-args.log" ] && grep -q '^LITELLM_API_KEY$' "$root/blocked-args.log"; then fail 'blocked key environment handed off'; fi
}
for override in --provider=other --model=other --smol=other --slow=other --plan=other --profile=other --config=other --cwd=other --session-dir=other --extension=other --api-key=HESTIA_FAKE_OVERRIDE; do blocked "$override" --version; done
blocked --hook "$root/does-not-run.js" --version
blocked --hook="$root/does-not-run.js" --version
blocked --no-extensions=false --version
ok 'caller routing, role, profile, storage, extension, hook and auth overrides fail before key handoff'
for conflict in "$root/repo/.env" "$root/repo/.env.local" "$state/.env" "$agent/.env"; do
    printf 'HESTIA_FAKE_DOTENV_CONTENT\n' >"$conflict"
    blocked --version
    grep -qx HESTIA_FAKE_DOTENV_CONTENT "$conflict" || fail 'dotenv file modified'
    rm "$conflict"
done
ln -s /hestia-test-missing-target "$agent/models.yml"
blocked --version
[ -L "$agent/models.yml" ] || fail 'model symlink changed'
rm "$agent/models.yml"
ok 'known dotenv files and dangling model symlinks reject without reading or changing their contents'
dc exec -T workspace omp config set setupVersion 2 >"$root/preferences-integration.log"
dc exec -T workspace omp config set theme.dark serius >>"$root/preferences-integration.log"
ok 'native setupVersion and safe appearance settings initialize through the supported CLI before ordinary database handoff/resume'
python3 - "$agent/agent.db" "$root/auth-row-id" <<'PY_AUTH'
import pathlib, sqlite3, sys
with sqlite3.connect(sys.argv[1]) as db:
    row = db.execute("INSERT INTO auth_credentials(provider,credential_type,data) VALUES ('litellm','api_key','{}')").lastrowid
pathlib.Path(sys.argv[2]).write_text(str(row))
PY_AUTH
blocked --version
python3 - "$agent/agent.db" "$root/auth-row-id" <<'PY_AUTH'
import pathlib, sqlite3, sys
row = int(pathlib.Path(sys.argv[2]).read_text())
with sqlite3.connect(sys.argv[1]) as db:
    assert db.execute("SELECT EXISTS(SELECT 1 FROM auth_credentials WHERE id=?)", (row,)).fetchone()[0] == 1
    db.execute("DELETE FROM auth_credentials WHERE id=?", (row,))
PY_AUTH
python3 - "$agent/agent.db" <<'PY_SCHEMA'
import sqlite3, sys
with sqlite3.connect(sys.argv[1]) as db:
    db.execute("INSERT INTO schema_version(version) VALUES (77)")
PY_SCHEMA
blocked --version
python3 - "$agent/agent.db" <<'PY_SCHEMA'
import sqlite3, sys
with sqlite3.connect(sys.argv[1]) as db:
    assert db.execute("SELECT MAX(version) FROM schema_version").fetchone()[0] == 77
    db.execute("DELETE FROM schema_version WHERE version=77")
PY_SCHEMA
printf 'HESTIA_FAKE_LEGACY_AUTH\n' >"$agent/auth.json"
blocked --version
grep -qx HESTIA_FAKE_LEGACY_AUTH "$agent/auth.json" || fail 'legacy auth file changed'
rm "$agent/auth.json"
ok 'active LiteLLM auth, unknown schema and conservative legacy auth presence reject before key handoff and remain preserved'
# Broker controls inspect keys only, including empty selection and YAML forms;
# safe loading rejects executable tags/aliases without running or altering them.
for broker in 'auth: {broker: {url: ""}}' '"auth.broker.url": HESTIA_FAKE_BROKER' 'unsafe: !ruby/object:Object {}' 'first: &a {}
second: *a'; do
    target="$agent/config.yml"
    if [ -f "$target" ]; then cp "$target" "$root/config-before-control"; fi
    printf '%b\n' "$broker" >"$target"
    cp "$target" "$root/broker-control"
    blocked --version
    cmp "$target" "$root/broker-control" || fail 'broker settings file modified'
    if [ -f "$root/config-before-control" ]; then mv "$root/config-before-control" "$target"; else rm "$target"; fi
done
mkdir -p "$root/repo/.omp"
printf '{"auth.broker.url":"HESTIA_FAKE_PROJECT_BROKER"}\n' >"$root/repo/.omp/settings.json"
blocked --version
grep -q HESTIA_FAKE_PROJECT_BROKER "$root/repo/.omp/settings.json" || fail 'legacy project setting changed'
rm "$root/repo/.omp/settings.json"
ok 'nested/dotted broker metadata, legacy project JSON and unsafe YAML reject before key handoff while settings bytes remain intact'
# Preserve the native YAML, then add only test-owned legacy metadata. The
# presence-only database check must reject migration before a native CLI runs.
for config in config.yml config.yaml; do if [ -f "$agent/$config" ]; then mv "$agent/$config" "$root/saved-$config"; fi; done
python3 - "$agent/agent.db" <<'PY_LEGACY'
import sqlite3, sys
with sqlite3.connect(sys.argv[1]) as db:
    db.execute("INSERT INTO settings(key,value) VALUES ('hestia_test_legacy','{}')")
PY_LEGACY
blocked --version
python3 - "$agent/agent.db" <<'PY_LEGACY'
import sqlite3, sys
with sqlite3.connect(sys.argv[1]) as db:
    assert db.execute("SELECT EXISTS(SELECT 1 FROM settings WHERE key='hestia_test_legacy')").fetchone()[0] == 1
    db.execute("DELETE FROM settings WHERE key='hestia_test_legacy'")
PY_LEGACY
for config in config.yml config.yaml; do if [ -f "$root/saved-$config" ]; then mv "$root/saved-$config" "$agent/$config"; fi; done
ok 'nonempty legacy SQLite settings without native YAML reject without migration or row modification'
# Real native JSONL creation/resume against the same fixed fake response proves
# ordinary database/session state is permitted; this is not agent acceptance.
"$attach" --endpoint "$endpoint" --model "$model" --no-tty "$root/ws.yml" \
    --no-tools --no-skills --no-lsp --no-title --max-time 45s -p 'Create a synthetic protocol session.' >"$root/native-session.log" 2>&1 || fail 'synthetic native session creation failed'
session="$(dc exec -T workspace find /home/dev/.omp/agent/sessions -name '*.jsonl' -print -quit)"
[ -n "$session" ] || fail 'native completed session not persisted'
"$attach" --endpoint "$endpoint" --model "$model" --no-tty "$root/ws.yml" --resume "$session" \
    --no-tools --no-skills --no-lsp --no-title --max-time 45s -p 'Resume the synthetic protocol session.' >"$root/native-resume.log" 2>&1 || fail 'synthetic native saved-session resume failed'
grep -q HESTIA_LOCAL_STUB_OK "$root/native-session.log" && grep -q HESTIA_LOCAL_STUB_OK "$root/native-resume.log" || fail 'native saved/resumed completion missing'
dc exec -T workspace cat "$session" >"$root/native-session.jsonl"
python3 - "$root/native-session.jsonl" <<'PY_SESSION'
import json, pathlib, sys
records = [json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text().splitlines()]
assert sum(r.get("type") == "session" for r in records) == 1
assert sum(r.get("message", {}).get("role") == "assistant" for r in records) == 2
PY_SESSION
ok 'ordinary native database allows real synthetic saved-session creation and exact JSONL resume with two completed responses'

dc exec -T workspace bash -c 'test -z "${LITELLM_API_KEY:-}" && test -z "${LITELLM_BASE_URL:-}" && test -z "${HESTIA_LITELLM_TRACE_ID:-}" && test "$PI_CONFIG_FILES" = /opt/hestia/omp/config.yml' || fail 'credentials or overlay leaked into a separate attach'
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
echo "passed: $pass, failed: 0; real endpoint agent acceptance: NOT RUN"
