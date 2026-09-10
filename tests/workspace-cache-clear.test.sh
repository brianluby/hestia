#!/usr/bin/env bash
# HE2GM6N — acceptance tests for scoped cache clearing.
#
# Populates a workspace's disposable cache volume with a real build, then
# clears it through workspace-lifecycle.sh clear-caches and verifies: only
# that volume was removed (fresh and empty afterwards), source/Git state and
# durable state are unchanged, caches regenerate, and build/tests pass again.
# Needs a reachable Docker daemon and the fixture-tools image; prints SKIP
# otherwise. The fixture lives under the user's home (Docker-shared path).
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
if ! docker image inspect "$image" >/dev/null 2>&1; then
	echo "SKIP: image $image not built (docker build --target fixture-tools -t $image .)"
	exit 0
fi

tmp_base="$HOME/.cache/hestia-cacheclear-tests"
mkdir -p "$tmp_base"
root="$(mktemp -d "$tmp_base/hestia-cacheclear-XXXXXXXX")"
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
ws_id="$(sed -n 's/^name: //p' "$root/ws.yaml")"
volume="${ws_id}_linux-caches"
state_dir="$HESTIA_STATE_ROOT/$ws_id"

sentinel="hestia-sentinel-$$"
docker volume create "$sentinel" >/dev/null

cleanup_compose() {
	docker compose -f "$root/ws.yaml" down --remove-orphans >/dev/null 2>&1 || true
	docker volume rm "$volume" >/dev/null 2>&1 || true
	docker volume rm "$sentinel" >/dev/null 2>&1 || true
	return 0
}
trap 'cleanup_compose; cleanup' EXIT

echo "== populate caches with a real build =="
"$life" start "$root/ws.yaml" >/dev/null 2>&1 || bad "start failed"
docker compose -f "$root/ws.yaml" exec -T workspace \
	bash -c "mise trust '$repo' >/dev/null && echo durable >'$state_dir/marker.txt' && go build ./... && go test ./..." \
	>"$root/build1.log" 2>&1 || { cat "$root/build1.log" >&2; }
grep -q "ok  .*example.com/hestia-synthetic/greet" "$root/build1.log" &&
	ok "initial container build/test passes (caches populate)" || bad "initial build failed"
docker compose -f "$root/ws.yaml" exec -T workspace \
	sh -c 'test -d /hestia/cache/go/build && echo populated' 2>/dev/null | grep -q populated &&
	ok "cache volume populated" || bad "cache volume not populated"

"$here/fixtures/bin/fixture-snapshot.sh" capture "$repo" "$fx/snapshots/10-before-clear" >/dev/null

echo "== clear caches =="
if "$life" clear-caches "$root/ws.yaml" >"$root/clear.log" 2>&1; then
	ok "clear-caches completes (log: $root/clear.log)"
else
	bad "clear-caches failed (log: $root/clear.log: $(tail -1 "$root/clear.log"))"
fi
docker volume inspect "$sentinel" >/dev/null 2>&1 &&
	ok "unrelated sentinel volume untouched by clearing" || bad "sentinel volume removed"
fresh="$(docker compose -f "$root/ws.yaml" exec -T workspace \
	sh -c 'test -d /hestia/cache/go/build && echo stale || echo fresh-empty' 2>/dev/null)"
[ "$fresh" = "fresh-empty" ] &&
	ok "cache volume recreated fresh and empty" || bad "cache not cleared: $fresh"
[ "$(cat "$state_dir/marker.txt" 2>/dev/null)" = "durable" ] &&
	ok "durable state unchanged by cache clearing" || bad "durable state affected"
[ -f "$state_dir/identity.record" ] &&
	ok "identity record intact" || bad "identity record lost"
"$here/fixtures/bin/fixture-snapshot.sh" compare "$repo" "$fx/snapshots/10-before-clear" >/dev/null 2>&1 &&
	ok "source bytes, index/tree, HEAD/branch and status unchanged" || bad "clearing touched the source"

echo "== caches regenerate and build passes again =="
docker compose -f "$root/ws.yaml" exec -T workspace \
	bash -c "mise trust '$repo' >/dev/null && go build ./... && go test ./..." >"$root/build2.log" 2>&1 || { cat "$root/build2.log" >&2; }
grep -q "ok  .*example.com/hestia-synthetic/greet" "$root/build2.log" &&
	ok "build/tests pass again after clearing (caches regenerate)" || bad "rebuild failed"

echo "== guards (rejections must also leave resources unchanged) =="
volumes_before="$(docker volume ls -q | sort)"
containers_before="$(docker compose -f "$root/ws.yaml" ps -aq | sort)"
printf 'name: hestia-impostor\nservices:\n  workspace:\n    image: busybox\n' >"$root/impostor.yaml"
if "$life" clear-caches "$root/impostor.yaml" >/dev/null 2>&1; then
	bad "workspace without a declared cache volume refused"
else
	ok "workspace without a declared cache volume refused"
fi
if "$life" clear-caches "$root/no-such-file.yaml" >/dev/null 2>&1; then
	bad "missing compose file rejected"
else
	ok "missing compose file rejected"
fi
volumes_after="$(docker volume ls -q | sort)"
containers_after="$(docker compose -f "$root/ws.yaml" ps -aq | sort)"
[ "$volumes_before" = "$volumes_after" ] && [ "$containers_before" = "$containers_after" ] &&
	ok "rejected operations changed no volumes or containers" || bad "rejection mutated docker state"

cleanup_compose
echo
echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
