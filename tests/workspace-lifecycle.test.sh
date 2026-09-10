#!/usr/bin/env bash
# 24GJSHY — acceptance tests for workspace/workspace-lifecycle.sh.
#
# Runs the full workspace journey on a fresh fixture: start, attach, durable
# writes, stop/start keeping the container, remove-runtime, and recreate with
# a different container ID — with source/Git state, the durable state
# directory and the cache volume preserved throughout, and build/tests
# passing again after recreation.
#
# Needs a reachable Docker daemon and the fixture-tools image; prints SKIP and
# exits 0 when either is missing. The fixture is created under the user's home
# (Docker-shared path on macOS).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gen="$here/workspace/workspace-compose.sh"
life="$here/workspace/workspace-lifecycle.sh"
image="hestia-fixture-tools:2026-09-09"

if ! command -v docker >/dev/null 2>&1; then
	echo "SKIP: docker not installed"
	exit 0
fi
if ! docker info >/dev/null 2>&1; then
	echo "SKIP: docker daemon not reachable"
	exit 0
fi
if ! docker compose version >/dev/null 2>&1; then
	echo "SKIP: docker compose v2 plugin not available"
	exit 0
fi
if ! docker image inspect "$image" >/dev/null 2>&1; then
	echo "SKIP: image $image not built (docker build --target fixture-tools -t $image .)"
	exit 0
fi

tmp_base="$HOME/.cache/hestia-lifecycle-tests"
mkdir -p "$tmp_base"
root="$(mktemp -d "$tmp_base/hestia-lifecycle-XXXXXXXX")"
fx=""
cleanup() {
	# Keep artifacts for inspection when anything failed (or KEEP_ARTIFACTS=1);
	# containers are still torn down, files are preserved.
	cleanup_compose >/dev/null 2>&1 || true
	if [ "${fail:-0}" -gt 0 ] || [ "${KEEP_ARTIFACTS:-0}" = "1" ]; then
		echo "preserving artifacts for inspection: $root (fixture: ${fx:-n/a})" >&2
		return 0
	fi
	[ -n "$fx" ] && rm -rf "$fx"
	rm -rf "$root"
	return 0
}
trap cleanup EXIT
export HESTIA_STATE_ROOT="$root/hestia-state"

pass=0
fail=0
ok() {
	echo "ok   - $1"
	pass=$((pass + 1))
}
bad() {
	echo "FAIL - $1"
	fail=$((fail + 1))
}

TMPDIR="$tmp_base" "$here/fixtures/bin/make-fixture.sh" >"$root/make-fixture.log" 2>&1 || {
	echo "FAIL - fixture creation"
	exit 1
}
fx_count="$(grep -c '^root: ' "$root/make-fixture.log")"
fx="$(sed -n 's/^root: //p' "$root/make-fixture.log" | head -1)"
if [ "$fx_count" -ne 1 ] || [ -z "$fx" ] || [ ! -d "$fx" ]; then
	echo "FAIL - fixture root not uniquely parsed from make-fixture log" >&2
	exit 1
fi
repo="$fx/repo"

"$gen" --out "$root/ws.yaml" "$repo" 2>/dev/null
[ -f "$root/ws.yaml" ] || {
	echo "FAIL - generator produced no file"
	exit 1
}
ws_id="$(sed -n 's/^name: //p' "$root/ws.yaml")"
printf '%s' "$ws_id" | grep -Eq '^hestia-[a-z0-9][a-z0-9-]{0,23}-[0-9a-f]{12}$' ||
	{ echo "FAIL - malformed workspace id parsed from generated file: $ws_id" >&2; exit 1; }

cleanup_compose() {
	"$life" remove-runtime "$root/ws.yaml" >/dev/null 2>&1 || true
	docker compose -f "$root/ws.yaml" down --remove-orphans >/dev/null 2>&1 || true
	docker volume rm "${ws_id}_linux-caches" >/dev/null 2>&1 || true
	return 0
}
trap 'cleanup_compose; cleanup' EXIT

echo "== validate / start / attach =="
"$life" validate "$root/ws.yaml" >/dev/null 2>&1 &&
	ok "validate accepts the generated workspace" || bad "validate failed"
"$life" start "$root/ws.yaml" >"$root/start.log" 2>&1 &&
	ok "workspace starts detached" || bad "start failed: $(cat "$root/start.log")"
id_a="$(sed -n 's/^workspace running: //p' "$root/start.log")"
[ -n "$id_a" ] && ok "container id captured ($id_a)" || bad "no container id"

state_dir="$HESTIA_STATE_ROOT/$ws_id"
"$life" attach "$root/ws.yaml" \
	sh -c "echo durable-marker >'$state_dir/marker.txt'" &&
	ok "attach runs a command in the running workspace" || bad "attach failed"
[ "$(cat "$state_dir/marker.txt" 2>/dev/null)" = "durable-marker" ] &&
	ok "durable write through the container lands in the state dir" || bad "state write failed"

echo "== stop / start keeps the container =="
"$life" stop "$root/ws.yaml" >/dev/null 2>&1 && ok "stop retains the container" || bad "stop failed"
"$life" start "$root/ws.yaml" >"$root/start2.log" 2>&1
id_a2="$(sed -n 's/^workspace running: //p' "$root/start2.log")"
[ "$id_a2" = "$id_a" ] &&
	ok "start after stop reuses the same container (attachable workspace)" || bad "container changed: $id_a2"

echo "== recreate =="
"$life" recreate "$root/ws.yaml" >"$root/recreate.log" 2>&1 &&
	ok "recreate completes" || bad "recreate failed: $(cat "$root/recreate.log")"
id_b="$(sed -n 's/^recreated: [0-9a-f]* -> //p' "$root/recreate.log")"
case "$id_b" in
"$id_a") bad "replacement container ID did not change" ;;
"") bad "no replacement id parsed" ;;
*) ok "replacement has a different container id ($id_b)" ;;
esac
marker="$(docker compose -f "$root/ws.yaml" exec -T workspace cat "$state_dir/marker.txt" 2>/dev/null)"
[ "$marker" = "durable-marker" ] &&
	ok "durable state survives recreation" || bad "state lost on recreation"

"$here/fixtures/bin/fixture-snapshot.sh" compare "$repo" "$fx/snapshots/00-created" >/dev/null 2>&1 &&
	ok "source and Git state unchanged by the whole lifecycle" || bad "lifecycle mutated the fixture"

docker volume inspect "${ws_id}_linux-caches" >/dev/null 2>&1 &&
	ok "cache volume survives recreation" || bad "cache volume missing"

echo "== remove-runtime =="
if "$life" remove-runtime "$root/ws.yaml" >"$root/rm.log" 2>&1; then
	ok "remove-runtime succeeds"
else
	bad "remove-runtime failed: $(tail -1 "$root/rm.log")"
fi
[ -z "$(docker compose -f "$root/ws.yaml" ps -aq workspace 2>/dev/null)" ] &&
	ok "remove-runtime leaves no workspace container" || bad "container still present after remove-runtime"
[ "$(cat "$state_dir/marker.txt" 2>/dev/null)" = "durable-marker" ] &&
	ok "durable state survives remove-runtime" || bad "state lost on remove-runtime"
docker volume inspect "${ws_id}_linux-caches" >/dev/null 2>&1 &&
	ok "cache volume survives remove-runtime" || bad "cache volume removed by remove-runtime"
"$life" start "$root/ws.yaml" >/dev/null 2>&1

echo "== build/test after recreation =="
docker compose -f "$root/ws.yaml" exec -T workspace \
	bash -c "mise trust '$repo' >/dev/null && go build ./... && go test -count=1 ./..." >"$root/rebuild.log" 2>&1 ||
	{ cat "$root/rebuild.log" >&2; }
grep -q "ok  .*example.com/hestia-synthetic/greet" "$root/rebuild.log" &&
	ok "build/tests pass again after recreation" || bad "post-recreation build/test failed"

echo "== guards =="
printf 'name: not-hestia\nservices:\n  workspace:\n    image: busybox\n' >"$root/foreign.yaml"
if "$life" remove-runtime "$root/foreign.yaml" >/dev/null 2>&1; then
	bad "non-Hestia project refused"
else
	ok "non-Hestia Compose project refused"
fi

cleanup_compose
echo
echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
