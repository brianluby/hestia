#!/usr/bin/env bash
# AWCEX5Z — synthetic plumbing only; no provider calls or real credentials.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image="hestia-agent:2026-09-10"
docker info >/dev/null 2>&1 || { echo 'SKIP: Docker unreachable'; exit 0; }
docker image inspect "$image" >/dev/null 2>&1 || { echo "SKIP: image $image absent"; exit 0; }
mkdir -p "$HOME/.cache/hestia-aws-tests"
root="$(mktemp -d "$HOME/.cache/hestia-aws-tests/run-XXXXXXXX")"
project=''
cleanup() {
	if [ -n "$project" ]; then
		docker compose -p "$project" -f "$root/ws.yml" down >/dev/null 2>&1 || true
		docker volume rm "${project}_linux-caches" >/dev/null 2>&1 || true
	fi
	if [ "${KEEP_ARTIFACTS:-0}" != 1 ]; then rm -rf "$root"; else echo "receipts: $root"; fi
}
trap cleanup EXIT
mkdir -p "$root/repo" "$root/bin"
cp -R "$here/fixtures/synthetic/." "$root/repo/"
git -C "$root/repo" init -q
HESTIA_STATE_ROOT="$root/state" "$here/workspace/workspace-compose.sh" --image "$image" --out "$root/ws.yml" "$root/repo"
project="$(sed -n 's/^name: //p' "$root/ws.yml")"
"$here/workspace/workspace-lifecycle.sh" start "$root/ws.yml" >"$root/start.log" 2>&1
pass=0
ok() { echo "ok - $*"; pass=$((pass+1)); }
fail() { echo "FAIL - $*" >&2; exit 1; }
attach="$here/workspace/workspace-attach-aws.sh"
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_REGION AWS_DEFAULT_REGION
if "$attach" --env --no-tty "$root/ws.yml" true >"$root/missing.log" 2>&1; then fail 'missing auth accepted'; fi
grep -q 'temporary AWS_ACCESS_KEY_ID' "$root/missing.log" || fail 'missing auth not actionable'
ok 'missing auth fails before execution'
export AWS_ACCESS_KEY_ID=HESTIA_FAKE_ACCESS AWS_SECRET_ACCESS_KEY=HESTIA_FAKE_SECRET AWS_SESSION_TOKEN=HESTIA_FAKE_TOKEN AWS_REGION=us-west-2
"$attach" --env --no-tty "$root/ws.yml" bash -c '
 test "$AWS_ACCESS_KEY_ID" = HESTIA_FAKE_ACCESS &&
 test "$AWS_SECRET_ACCESS_KEY" = HESTIA_FAKE_SECRET &&
 test "$AWS_SESSION_TOKEN" = HESTIA_FAKE_TOKEN &&
 test "$AWS_REGION" = us-west-2 && test "$AWS_DEFAULT_REGION" = us-west-2' >"$root/env.log" 2>&1 || fail 'session handoff failed'
ok 'Compose forwards bare environment names to the exec session'
bash -x "$attach" --env --no-tty "$root/ws.yml" true >"$root/trace.log" 2>&1 || fail 'traced caller failed'
if grep -q HESTIA_FAKE_ "$root/trace.log"; then fail 'secret in caller-enabled trace'; fi
ok 'caller-enabled shell tracing is disabled before secret handling'
docker compose -p "$project" -f "$root/ws.yml" exec -T workspace bash -c 'test -z "${AWS_ACCESS_KEY_ID:-}" && test -z "${AWS_SESSION_TOKEN:-}"' || fail 'credential leaked into another attach'
ok 'separate attach remains unauthenticated'
cid="$(docker compose -p "$project" -f "$root/ws.yml" ps -q workspace)"
docker inspect "$cid" >"$root/container-inspect.json"
docker image inspect "$image" >"$root/image-inspect.json"
if grep -R -q 'HESTIA_FAKE_' "$root/state" "$root/ws.yml" "$root/env.log" "$root/container-inspect.json" "$root/image-inspect.json"; then fail 'synthetic credential at rest'; fi
ok 'no synthetic secrets in generated config, state, image/container configuration or helper log'
# A wrapper verifies that the command line contains names, never values.
real_docker="$(command -v docker)"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" >>"$AWS_TEST_ARGS"\nexec "%s" "$@"\n' "$real_docker" >"$root/bin/docker"
chmod +x "$root/bin/docker"
PATH="$root/bin:$PATH" AWS_TEST_ARGS="$root/args.log" "$attach" --env --no-tty "$root/ws.yml" true >"$root/argv.log" 2>&1
if grep -q HESTIA_FAKE_ "$root/args.log"; then fail 'secret value in argv'; fi
ok 'Docker argv contains only credential names'
cat >"$root/bin/aws" <<'AWS'
#!/usr/bin/env bash
case "$*" in
'configure export-credentials --profile fixture --format process')
 printf '%s\n' '{"Version":1,"AccessKeyId":"HESTIA_FAKE_ACCESS","SecretAccessKey":"HESTIA_FAKE_SECRET","SessionToken":"HESTIA_FAKE_TOKEN"}' ;;
'configure get region --profile fixture') printf '%s\n' us-west-2 ;;
*) exit 1 ;;
esac
AWS
chmod +x "$root/bin/aws"
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_REGION AWS_DEFAULT_REGION
PATH="$root/bin:$PATH" AWS_TEST_ARGS="$root/profile-args.log" "$attach" --profile fixture --no-tty "$root/ws.yml" bash -c 'test -n "$AWS_ACCESS_KEY_ID" && test -n "$AWS_SECRET_ACCESS_KEY" && test -n "$AWS_SESSION_TOKEN" && test "$AWS_REGION" = us-west-2' >"$root/profile.log" 2>&1 || fail 'profile handoff failed'
if grep -q HESTIA_FAKE_ "$root/profile-args.log" "$root/profile.log"; then fail 'profile secret logged'; fi
ok 'mock AWS CLI process JSON is resolved on host without eval, files or value argv'
cat >"$root/bin/aws" <<'AWS'
#!/usr/bin/env bash
echo HESTIA_FAKE_SECRET >&2
exit 1
AWS
if PATH="$root/bin:$PATH" AWS_TEST_ARGS="$root/error-args.log" "$attach" --profile fixture --no-tty "$root/ws.yml" true >"$root/profile-error.log" 2>&1; then fail 'failed profile accepted'; fi
if grep -q HESTIA_FAKE_ "$root/profile-error.log"; then fail 'credential-provider stderr leaked'; fi
grep -q 'refresh/login on the host' "$root/profile-error.log" || fail 'failed profile not actionable'
ok 'credential-provider failure is actionable and its stderr is suppressed'
"$here/workspace/workspace-lifecycle.sh" recreate "$root/ws.yml" >"$root/recreate.log" 2>&1
docker compose -p "$project" -f "$root/ws.yml" exec -T workspace bash -c 'test -z "${AWS_ACCESS_KEY_ID:-}" && test -z "${AWS_SESSION_TOKEN:-}"' || fail 'credential survived recreation'
ok 'recreated workspace has no supplied session credentials'
echo "passed: $pass, failed: 0; authenticated inference: NOT RUN (synthetic credentials)"
