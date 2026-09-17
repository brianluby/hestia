#!/usr/bin/env bash
# XJVWF4K — acceptance tests for the omp agent layer and its state scoping.
# FA5H9TR — settings persistence and the overlay-based provider policy.
#
# Verifies against the hestia-agent image: the generated Compose file carries
# the omp state bind and the PI_CONFIG_FILES policy overlay (no file bind
# inside ~/.omp); omp runs in the workspace; the policy config is
# byte-identical to the repo template and neither writable nor replaceable at
# runtime; a user config attempting to re-enable providers does not take
# effect (the root-owned overlay wins every merge); omp's atomic settings
# write onto ~/.omp/agent/config.yml succeeds and its content survives
# recreation; missing AWS credentials fail with a clear, actionable error
# while shell and source stay usable. Needs a reachable Docker daemon and the
# agent image; SKIPs otherwise. The fixture lives under the user's home
# (Docker-shared path).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gen="$here/workspace/workspace-compose.sh"
life="$here/workspace/workspace-lifecycle.sh"
image="hestia-agent:2026-09-10"

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
	echo "SKIP: image $image not built (docker build --target agent -t $image .)"
	exit 0
fi

tmp_base="$HOME/.cache/hestia-agent-tests"
mkdir -p "$tmp_base"
root="$(mktemp -d "$tmp_base/hestia-agent-XXXXXXXX")"
fx=""
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
cleanup() {
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

TMPDIR="$tmp_base" "$here/fixtures/bin/make-fixture.sh" >"$root/make-fixture.log" 2>&1 || {
	echo "FAIL - fixture creation"
	exit 1
}
fx_count="$(grep -c '^root: ' "$root/make-fixture.log")"
fx="$(sed -n 's/^root: //p' "$root/make-fixture.log" | head -1)"
if [ "$fx_count" -ne 1 ] || [ -z "$fx" ] || [ ! -d "$fx" ]; then
	echo "FAIL - fixture root not uniquely parsed" >&2
	exit 1
fi
repo="$fx/repo"
ws_id=""

cleanup_compose() {
	if [ -n "${ws_id:-}" ]; then
		docker compose -p "$ws_id" -f "$root/ws.yaml" down --remove-orphans >/dev/null 2>&1 || true
		docker volume rm "${ws_id}_linux-caches" >/dev/null 2>&1 || true
	fi
	return 0
}
trap cleanup EXIT

echo "== generation =="
"$gen" --image "$image" --out "$root/ws.yaml" "$repo" 2>/dev/null
ws_id="$(sed -n 's/^name: //p' "$root/ws.yaml")"
grep -q "target: /home/dev/.omp$" "$root/ws.yaml" &&
	ok "omp state bind targets ~/.omp" || bad "no ~/.omp bind"
grep -q "source: '$HESTIA_STATE_ROOT/$ws_id/omp'" "$root/ws.yaml" &&
	ok "omp state bind sources from the workspace state dir" || bad "omp bind source wrong"
grep -q "PI_CONFIG_FILES: /opt/hestia/omp/config.yml" "$root/ws.yaml" &&
	ok "policy overlay wired via PI_CONFIG_FILES" || bad "no PI_CONFIG_FILES policy overlay"
grep -q "omp/agent/config.yml" "$root/ws.yaml" &&
	bad "no file bind inside the omp state tree" || ok "nothing bound inside ~/.omp"

echo "== runtime =="
"$life" start "$root/ws.yaml" >/dev/null 2>&1 || bad "start failed"
# Deliberate trust of the mounted repo (paranoid default); trust state is
# per-container, so this is repeated after recreation below.
docker compose -p "$ws_id" -f "$root/ws.yaml" exec -T workspace \
	bash -c "mise trust '$repo' >/dev/null" 2>/dev/null ||
	bad "mise trust of the mounted repo failed"
ver="$(docker compose -p "$ws_id" -f "$root/ws.yaml" exec -T workspace omp --version 2>/dev/null)" || ver=""
[ "$ver" = "omp/18.1.16" ] &&
	ok "omp runs in the workspace ($ver)" || bad "omp version: $ver"
env_ctr="$(docker compose -p "$ws_id" -f "$root/ws.yaml" exec -T workspace bash -c 'printf %s "$PI_CONFIG_FILES"')"
[ "$env_ctr" = "/opt/hestia/omp/config.yml" ] &&
	ok "PI_CONFIG_FILES reaches exec shells" || bad "PI_CONFIG_FILES wrong in exec env: $env_ctr"
cfg_ctr="$(docker compose -p "$ws_id" -f "$root/ws.yaml" exec -T workspace sha256sum /opt/hestia/omp/config.yml 2>/dev/null | cut -d' ' -f1)"
cfg_repo="$(sha256sum "$here/agent/omp/config.yml" | cut -d' ' -f1)"
[ "$cfg_ctr" = "$cfg_repo" ] &&
	ok "policy config byte-identical to the repo template" || bad "config drift: $cfg_ctr vs $cfg_repo"
docker compose -p "$ws_id" -f "$root/ws.yaml" exec -T workspace \
	test -w /opt/hestia/omp/config.yml 2>/dev/null &&
	bad "policy config writable at runtime" || ok "policy config not writable at runtime"
docker compose -p "$ws_id" -f "$root/ws.yaml" exec -T workspace \
	test -w /opt/hestia/omp 2>/dev/null &&
	bad "policy directory writable (file could be replaced by rename)" ||
	ok "policy directory not writable (no rename-over either)"
docker compose -p "$ws_id" -f "$root/ws.yaml" exec -T workspace \
	touch /home/dev/.omp/marker.txt 2>/dev/null &&
	ok "omp state dir writable by the runtime user" || bad "state dir not writable"

echo "== missing auth: clear failure, usable shell =="
docker compose -p "$ws_id" -f "$root/ws.yaml" exec -T workspace \
	bash -c 'cd "$1" && echo "" | timeout 40 omp -p hi >/tmp/omp-out.log 2>&1; rc=$?; grep -q "No models available" /tmp/omp-out.log && echo clear-error; echo "omp-rc=$rc"; git status --porcelain=v2 >/dev/null && echo git-ok' _ "$repo" >"$root/auth.log" 2>&1
grep -q "clear-error" "$root/auth.log" &&
	ok "missing AWS auth yields a clear actionable error" || bad "no clear auth error: $(tail -3 "$root/auth.log")"
grep -q "omp-rc=1" "$root/auth.log" &&
	ok "omp exits nonzero without credentials" || bad "omp rc wrong: $(grep omp-rc "$root/auth.log")"
grep -q "git-ok" "$root/auth.log" &&
	ok "shell and source remain usable after the auth failure" || bad "git broken after auth failure"

echo "== settings persistence (FA5H9TR) =="
# omp persists settings with an atomic write: create
# config.yml.<pid>.<uuid>.tmp in ~/.omp/agent/ (verified against omp
# v18.1.16 #writeYamlAtomically), then rename onto config.yml. Under the
# previous read-only bind that rename failed with EBUSY; exercise the same
# write shape against the now-plain file.
write_out="$(docker compose -p "$ws_id" -f "$root/ws.yaml" exec -T workspace \
	bash -c 'f=/home/dev/.omp/agent/config.yml; t="$f.$$.$RANDOM.tmp"; printf "theme:\n  dark: serius\n" >"$t" && mv "$t" "$f" && cat "$f"' 2>/dev/null)" || write_out=""
case "$write_out" in
*"serius"*) ok "atomic tmp+rename onto config.yml succeeds (no EBUSY)" ||
	bad "atomic settings write broken" ;;
*) bad "atomic settings write failed: $write_out" ;;
esac
# A user config that tries to re-enable every provider must not take effect:
# the root-owned overlay merges after user config and wins. `omp config get`
# reports the effective merged value and needs no credentials (the model
# list is auth-driven and would be empty either way).
docker compose -p "$ws_id" -f "$root/ws.yaml" exec -T workspace \
	bash -c 'printf "disabledProviders: []\n" >/home/dev/.omp/agent/config.yml' 2>/dev/null ||
	bad "writing the user config failed"
eff="$(docker compose -p "$ws_id" -f "$root/ws.yaml" exec -T workspace \
	omp config get disabledProviders 2>/dev/null)" || eff=""
case "$eff" in
*"\"anthropic\""*) ok "re-enable attempt is shadowed (providers stay disabled)" ||
	bad "effective policy lost" ;;
*) bad "policy leaked providers: $eff" ;;
esac
# Control, and a documented boundary: the same user config without the
# overlay env leaks — whoever controls the omp process environment can bypass
# the policy, exactly as they could against the previous read-only bind.
eff_ctl="$(docker compose -p "$ws_id" -f "$root/ws.yaml" exec -T workspace \
	env -u PI_CONFIG_FILES omp config get disabledProviders 2>/dev/null)" || eff_ctl=""
[ "$eff_ctl" = "[]" ] &&
	ok "control: the probe detects a real leak when the overlay is absent" ||
	bad "control surprised: $eff_ctl"

echo "== durable agent state survives recreation =="
[ -f "$HESTIA_STATE_ROOT/$ws_id/omp/agent/agent.db" ] &&
	ok "omp agent.db lives in the host state dir" || bad "agent.db not in host state dir"
[ -f "$HESTIA_STATE_ROOT/$ws_id/omp/marker.txt" ] &&
	ok "state marker visible on the host" || bad "marker not host-visible"
grep -q "disabledProviders" "$HESTIA_STATE_ROOT/$ws_id/omp/agent/config.yml" &&
	ok "persisted settings are host-visible in the state dir" || bad "settings file not on the host"
"$life" recreate "$root/ws.yaml" >"$root/recreate.log" 2>&1 ||
	bad "recreate failed: $(tail -1 "$root/recreate.log")"
marker="$(docker compose -p "$ws_id" -f "$root/ws.yaml" exec -T workspace cat /home/dev/.omp/marker.txt 2>/dev/null)" ||
	marker="missing"
[ "$marker" = "" ] &&
	ok "omp state marker survives recreation" || bad "marker lost on recreation"
docker compose -p "$ws_id" -f "$root/ws.yaml" exec -T workspace \
	test -f /home/dev/.omp/agent/agent.db 2>/dev/null &&
	ok "agent.db survives recreation" || bad "agent.db lost on recreation"
persisted="$(docker compose -p "$ws_id" -f "$root/ws.yaml" exec -T workspace \
	cat /home/dev/.omp/agent/config.yml 2>/dev/null)" || persisted="missing"
case "$persisted" in
*disabledProviders*) ok "persisted settings survive recreation" ||
	bad "settings lost on recreation" ;;
*) bad "settings file lost on recreation: $persisted" ;;
esac
post_recreate_ver="$(docker compose -p "$ws_id" -f "$root/ws.yaml" exec -T workspace bash -c "mise trust '$repo' >/dev/null 2>&1; omp --version" 2>/dev/null)" ||
	post_recreate_ver=""
[ "$post_recreate_ver" = "omp/18.1.16" ] &&
	ok "omp runs in the replacement container after re-trust" || bad "post-recreate omp: $post_recreate_ver"

"$here/fixtures/bin/fixture-snapshot.sh" compare "$repo" "$fx/snapshots/00-created" >/dev/null 2>&1 &&
	ok "source and Git state unchanged by the agent work" || bad "agent probes mutated the fixture"

cleanup_compose
echo
echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
