#!/usr/bin/env bash
# ADR-006 step 2 — acceptance tests for the `hestia` launcher.
#
# Launches a synthetic checkout through a symlink to the launcher (as when it
# is on PATH) with `-- --version` instead of the TUI: the Compose file lands
# beside the state directory (out of the container's reach) with pi's shared
# home and a MISE_TRUSTED_CONFIG_PATHS scoped to the checkout, a second launch
# reuses the same running container, and mise in the container trusts the
# checkout's mise.toml without `mise trust` (but not other directories). A second checkout under the same state root shares ~/.pi
# (login once per user) without seeing the first workspace's state directory.
#
# Needs a reachable Docker daemon and the default image hestia-pi:local (the
# launcher builds it on first use; this test never builds it) and prints SKIP
# and exits 0 otherwise. The fixture lives under the user's home
# (Docker-shared path on macOS).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
life="$here/workspace/workspace-lifecycle.sh"
image="hestia-pi:local"

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
	echo "SKIP: image $image not built (docker build --platform linux/arm64 --target pi -t $image .)"
	exit 0
fi

tmp_base="$HOME/.cache/hestia-launcher-tests"
mkdir -p "$tmp_base"
root="$(cd -P "$(mktemp -d "$tmp_base/hestia-launcher-XXXXXXXX")" && pwd)"
compose=""
ws_id=""
compose2=""
ws_id2=""
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
	local c w
	for c in "$compose:$ws_id" "$compose2:$ws_id2"; do
		w="${c##*:}"
		c="${c%:*}"
		[ -n "$c" ] && [ -f "$c" ] || continue
		"$life" remove-runtime "$c" >/dev/null 2>&1 || true
		docker compose -f "$c" down --remove-orphans >/dev/null 2>&1 || true
		docker volume rm "${w}_linux-caches" >/dev/null 2>&1 || true
	done
	if [ "$fail" -gt 0 ] || [ "${KEEP_ARTIFACTS:-0}" = "1" ]; then
		echo "preserving artifacts for inspection: $root" >&2
		return 0
	fi
	rm -rf "$root"
}
trap cleanup EXIT

export HESTIA_STATE_ROOT="$root/state"
ln -s "$here/hestia" "$root/hestia-link"
repo="$root/repo"
mkdir "$repo"
git_q() { GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git -C "$repo" -c user.email=t@example.invalid -c user.name=t "$@"; }
git_q init -q
printf '[env]\nHESTIA_PROBE = "trusted"\n' >"$repo/mise.toml"
git_q add mise.toml
git_q commit -qm fixture

echo "== launch through a symlink =="
(cd "$repo" && "$root/hestia-link" -- --version) >"$root/run1.log" 2>&1 &&
	ok "hestia runs pi in the container and passes agent args" || bad "first launch failed: $(cat "$root/run1.log")"
grep -qx '1\.[0-9.]*' "$root/run1.log" && ok "agent output is pi's version" || bad "no pi version in output: $(cat "$root/run1.log")"
ws_id="$("$here/identity/workspace-id.sh" "$repo" | sed -n 's/^workspace: //p')"
compose="$HESTIA_STATE_ROOT/$ws_id.compose.yaml"
[ -f "$compose" ] && ok "Compose file is beside the workspace state directory" || bad "no $compose"
grep -qF "wrote $compose" "$root/run1.log" && ok "launcher names the generated Compose file" || bad "Compose path not reported"
grep -qF "source: '$HESTIA_STATE_ROOT/shared/pi'" "$compose" &&
	grep -qF "target: '/home/dev/.pi'" "$compose" && ok "pi's shared home is bound" || bad "pi shared bind missing"
grep -qF "MISE_TRUSTED_CONFIG_PATHS: '$repo'" "$compose" &&
	[ "$(grep -c MISE_TRUSTED_CONFIG_PATHS "$compose")" -eq 1 ] &&
	ok "mise trust is scoped to exactly the checkout" || bad "MISE_TRUSTED_CONFIG_PATHS not scoped"

echo "== second launch reuses the container =="
id_a="$(docker compose -f "$compose" ps -q workspace)"
(cd "$repo" && "$root/hestia-link" "$repo" -- --version) >"$root/run2.log" 2>&1 &&
	ok "second launch (explicit path) succeeds" || bad "second launch failed: $(cat "$root/run2.log")"
id_b="$(docker compose -f "$compose" ps -q workspace)"
{ [ -n "$id_a" ] && [ "$id_a" = "$id_b" ] && [ "$(docker inspect -f '{{.State.Running}}' "$id_a")" = true ]; } &&
	ok "same running container ID" || bad "container changed: '$id_a' -> '$id_b'"

"$life" attach "$compose" test -e "$compose" >/dev/null 2>&1 &&
	bad "Compose file is reachable from the container" || ok "Compose file is not reachable from the container"

echo "== mise trust =="
out="$("$life" attach "$compose" mise env 2>&1)" || true
printf '%s' "$out" | grep -q 'HESTIA_PROBE=trusted' &&
	ok "checkout mise.toml is trusted without mise trust" || bad "checkout not trusted: $out"
out="$("$life" attach "$compose" sh -c 'mkdir -p /tmp/other && cd /tmp/other && printf "[env]\nX=\"1\"\n" >mise.toml && mise env' 2>&1)" && other=0 || other=1
{ [ "$other" -eq 1 ] && printf '%s' "$out" | grep -q 'not trusted'; } &&
	ok "other directories stay untrusted" || bad "other directory was trusted: $out"

echo "== second checkout shares pi's home =="
repo2="$root/repo2"
mkdir "$repo2"
git -C "$repo2" init -q
(cd "$repo2" && "$root/hestia-link" -- --version) >"$root/run3.log" 2>&1 &&
	ok "second checkout launches" || bad "second launch failed: $(cat "$root/run3.log")"
ws_id2="$("$here/identity/workspace-id.sh" "$repo2" | sed -n 's/^workspace: //p')"
compose2="$HESTIA_STATE_ROOT/$ws_id2.compose.yaml"
[ "$ws_id" != "$ws_id2" ] && [ -f "$compose2" ] && ok "second checkout is its own workspace" || bad "no distinct workspace for repo2"
"$life" attach "$compose" sh -c 'echo shared-login >~/.pi/probe' &&
	[ "$("$life" attach "$compose2" cat /home/dev/.pi/probe)" = shared-login ] &&
	ok "a file written in one workspace's ~/.pi is visible in the other" || bad "the pi home is not shared"
[ "$(cat "$HESTIA_STATE_ROOT/shared/pi/probe")" = shared-login ] &&
	ok "it lives in <state-root>/shared/pi on the host" || bad "probe not in the shared directory"
"$life" attach "$compose" test -e "$HESTIA_STATE_ROOT/$ws_id2" >/dev/null 2>&1 &&
	bad "workspace 1 sees workspace 2's state dir" || ok "workspace 1 cannot see workspace 2's state dir"
"$life" attach "$compose2" test -e "$HESTIA_STATE_ROOT/$ws_id" >/dev/null 2>&1 &&
	bad "workspace 2 sees workspace 1's state dir" || ok "workspace 2 cannot see workspace 1's state dir"
"$life" attach "$compose" test -e "$HESTIA_STATE_ROOT/shared" >/dev/null 2>&1 &&
	bad "the shared dir is reachable at its host path" || ok "only ~/.pi is bound, not the shared directory's host path"

echo "== not a checkout =="
mkdir "$root/plain"
if "$root/hestia-link" "$root/plain" >"$root/plain.log" 2>&1; then
	bad "non-checkout accepted"
else
	grep -q 'not a Git checkout' "$root/plain.log" && ok "non-checkout fails with the identity helper's error" || bad "unclear error: $(cat "$root/plain.log")"
fi

echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
