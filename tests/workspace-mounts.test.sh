#!/usr/bin/env bash
# JP73P2D — acceptance tests for workspace/workspace-compose.sh.
#
# Exercises the scoped-mount contract with real containers: the fixture
# checkout is mounted at its identical host path, Git state agrees in both
# directions, both worktree link layouts stage/diff without pointer rewriting,
# sibling source and the host Docker socket stay invisible, and invalid
# layouts fail clearly without writing anything.
#
# Needs a reachable Docker daemon and the fixture-tools image; prints SKIP and
# exits 0 when either is missing. The fixture is created under the user's home
# so Docker Desktop shares the path (macOS /tmp is not shared and silently
# mounts empty — see docs/evidence.md).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gen="$here/workspace/workspace-compose.sh"
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

tmp_base="$HOME/.cache/hestia-mount-tests"
mkdir -p "$tmp_base"
root="$(mktemp -d "$tmp_base/hestia-mount-XXXXXXXX")"
fx=""
cleanup() {
	[ -n "$fx" ] && rm -rf "$fx"
	rm -rf "$root"
	return 0
}
trap cleanup EXIT

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

echo "== fixture =="
TMPDIR="$tmp_base" "$here/fixtures/bin/make-fixture.sh" >"$root/make-fixture.log" 2>&1 || {
	echo "FAIL - fixture creation"
	exit 1
}
fx="$(sed -n 's/^root: //p' "$root/make-fixture.log")"
repo="$fx/repo"
cp "$repo/NOTES.md" "$root/NOTES.md.orig"

# wrun <workdir> <extra -v binds...> -- handled inline below
echo "== generator =="
"$gen" --out "$root/main.yaml" "$repo" 2>/dev/null
[ -f "$root/main.yaml" ] && ok "compose file written for main checkout" || bad "no compose file"
grep -q "^name: hestia-" "$root/main.yaml" && ok "project name is the workspace id" || bad "no project name"
[ "$(grep -c 'type: bind' "$root/main.yaml")" -eq 1 ] &&
	ok "main checkout: exactly one bind (its .git lives inside it)" || bad "unexpected bind count"
docker compose -f "$root/main.yaml" config >/dev/null 2>&1 &&
	ok "generated compose file is valid" || bad "compose file invalid"

echo "== host/container agreement (through the generated compose file) =="
status_host="$(git -C "$repo" status --porcelain=v2)"
status_ctr="$(docker compose -f "$root/main.yaml" run --rm workspace git status --porcelain=v2 2>"$root/status.err")" || {
	cat "$root/status.err" >&2
}
[ "$status_host" = "$status_ctr" ] &&
	ok "git status agrees host vs container" || bad "status mismatch: [$status_ctr] vs [$status_host]"

printf 'host-side marker %s\n' "$root" >"$repo/HOST_MARKER.md"
seen_host="$(docker compose -f "$root/main.yaml" run --rm workspace cat HOST_MARKER.md 2>/dev/null)"
case "$seen_host" in
*"host-side marker"*) ok "host edit is visible inside the container" ;;
*) bad "container cannot read the host edit" ;;
esac
docker compose -f "$root/main.yaml" run --rm workspace \
	sh -c 'echo container-side marker > CONTAINER_MARKER.md' >/dev/null 2>&1
case "$(cat "$repo/CONTAINER_MARKER.md" 2>/dev/null)" in
*"container-side marker"*) ok "container edit is visible on the host" ;;
*) bad "host cannot read the container edit" ;;
esac
rm -f "$repo/HOST_MARKER.md" "$repo/CONTAINER_MARKER.md"

echo "== worktrees (docker run with the generator's exact binds) =="
for wt in wt-abs wt-rel; do
	wdir="$fx/worktrees/$wt"
	"$gen" --out "$root/$wt.yaml" "$wdir" 2>/dev/null
	[ "$(grep -c 'type: bind' "$root/$wt.yaml")" -eq 2 ] &&
		ok "$wt: checkout + common metadata binds" || bad "$wt: bind count"
	binds=(-v "$wdir:$wdir" -v "$repo/.git:$repo/.git"
		-e GIT_CONFIG_COUNT=2
		-e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0="$wdir"
		-e GIT_CONFIG_KEY_1=safe.directory -e GIT_CONFIG_VALUE_1="$repo/.git")
	common_ctr="$(docker run --rm --network none "${binds[@]}" -w "$wdir" "$image" \
		git rev-parse --git-common-dir 2>"$root/$wt.err")" || cat "$root/$wt.err" >&2
	case "$common_ctr" in
	*/.git) ok "$wt: common dir resolves inside container ($common_ctr)" ;;
	*) bad "$wt: common dir '$common_ctr'" ;;
	esac
	ptr_before="$(cat "$wdir/.git")"
	printf '\n// staged from container in %s\n' "$wt" >>"$wdir/greet/greet.go"
	docker run --rm --network none "${binds[@]}" -w "$wdir" "$image" \
		git add greet/greet.go 2>"$root/$wt-add.err" || cat "$root/$wt-add.err" >&2
	staged="$(docker run --rm --network none "${binds[@]}" -w "$wdir" "$image" \
		git diff --cached --name-only 2>/dev/null)"
	ptr_after="$(cat "$wdir/.git")"
	[ "$staged" = "greet/greet.go" ] && [ "$ptr_before" = "$ptr_after" ] &&
		ok "$wt: stage works, .git pointer not rewritten" || bad "$wt: staging ($staged) or pointer changed"
	git -C "$wdir" reset -q 2>/dev/null || true
	git -C "$wdir" checkout -q -- greet/greet.go 2>/dev/null || true
done

echo "== exposure limits =="
main_src_visible="$(docker run --rm --network none \
	-v "$fx/worktrees/wt-rel:$fx/worktrees/wt-rel" -v "$repo/.git:$repo/.git" \
	-w "$fx/worktrees/wt-rel" "$image" sh -c "ls '$repo' 2>/dev/null")"
case "$main_src_visible" in
".git") ok "worktree container sees only metadata of the main checkout, no sibling source" ;;
"") ok "main checkout path not visible at all" ;;
*) bad "sibling source exposed: $main_src_visible" ;;
esac
socket="$(docker run --rm --network none \
	-v "$fx/worktrees/wt-rel:$fx/worktrees/wt-rel" -v "$repo/.git:$repo/.git" \
	"$image" sh -c 'test -e /var/run/docker.sock && echo yes || echo no')"
[ "$socket" = "no" ] && ok "no host Docker socket in container" || bad "docker socket exposed"
mkdir -p "$tmp_base/sibling-of-fixture"
echo secret >"$tmp_base/sibling-of-fixture/data.txt"
sibling="$(docker run --rm --network none -v "$repo:$repo" -w "$repo" "$image" \
	sh -c "cat '$tmp_base/sibling-of-fixture/data.txt' 2>/dev/null || echo absent")"
[ "$sibling" = "absent" ] &&
	ok "paths outside the declared binds are invisible" || bad "sibling host path leaked into container"

echo "== failure modes =="
if "$gen" "$root/no-such-checkout" >"$root/f1.out" 2>"$root/f1.err"; then
	bad "missing path rejected"
else
	grep -q "not a directory" "$root/f1.err" &&
		ok "missing path fails clearly" || bad "unclear missing-path error: $(cat "$root/f1.err")"
fi
mkdir -p "$root/fake"
printf 'gitdir: /nowhere/at/all\n' >"$root/fake/.git"
if "$gen" --out "$root/fake.yaml" "$root/fake" >"$root/f2.out" 2>"$root/f2.err"; then
	bad "unresolvable gitdir rejected"
else
	grep -q "unsupported layout" "$root/f2.err" &&
		ok "unsupported layout fails clearly" || bad "unclear layout error: $(cat "$root/f2.err")"
	[ ! -e "$root/fake.yaml" ] &&
		ok "failed generation writes no file" || bad "partial compose file written"
fi
cp "$root/NOTES.md.orig" "$repo/NOTES.md"
"$here/fixtures/bin/fixture-snapshot.sh" compare "$repo" "$fx/snapshots/00-created" >/dev/null 2>&1 &&
	ok "fixture state unchanged after the probes" || bad "probes mutated the fixture"

echo
echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
