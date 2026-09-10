#!/usr/bin/env bash
# 503RD0P — acceptance tests for identity/workspace-id.sh.
#
# Builds throwaway repositories in fresh temporary storage and checks the
# identity rules from ADR-002: distinct ids for distinct paths (including
# matching basenames and worktrees), stable across branch changes, symlink
# aliases collapsing, and reuse of recorded state failing safely on path
# mismatch or id collision.
set -euo pipefail
# Hermetic Git: ignore the developer's global/system configuration entirely.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wid="$here/identity/workspace-id.sh"

# Preflight: a missing or broken helper must not masquerade as passing tests.
[ -f "$wid" ] && [ -x "$wid" ] || {
	echo "FAIL - identity helper missing or not executable: $wid" >&2
	exit 1
}
bash -n "$wid" || {
	echo "FAIL - identity helper has syntax errors" >&2
	exit 1
}

tmp_base="${TMPDIR:-/tmp}"
root="$(mktemp -d "${tmp_base%/}/hestia-id-test-XXXXXXXX")"
trap 'rm -rf "$root"' EXIT

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

wsid() { "$wid" "$1" | sed -n 's/^workspace: //p'; }
grpid() { "$wid" "$1" | sed -n 's/^repo-group: //p'; }

make_repo() {
	mkdir -p "$1"
	git -C "$1" init -q -b main
	git -C "$1" config user.name "Hestia Test"
	git -C "$1" config user.email "hestia-test@invalid"
	git -C "$1" config commit.gpgsign false
	echo hello >"$1/file.txt"
	git -C "$1" add -A
	git -C "$1" commit -qm "init"
}

echo "== form, bounds, sanitization =="
make_repo "$root/a/My_Project_2026!"
id="$(wsid "$root/a/My_Project_2026!")"
echo "$id" | grep -Eq '^hestia-[a-z0-9][a-z0-9-]{0,23}-[0-9a-f]{12}$' &&
	ok "id form: $id" || bad "id form: $id"
[ "${#id}" -le 44 ] && ok "id length bounded (${#id})" || bad "id length ${#id} not bounded"
echo "$id" | grep -q '^hestia-my-project-2026-' &&
	ok "label lowercased and sanitized" || bad "label wrong: $id"
make_repo "$root/a/abcdefghijklmnopqrstuvwxyz012345"
longid="$(wsid "$root/a/abcdefghijklmnopqrstuvwxyz012345")"
echo "$longid" | grep -q '^hestia-abcdefghijklmnopqrstuvwx-[0-9a-f]\{12\}$' &&
	ok "long label truncated to 24" || bad "long label: $longid"
make_repo "$root/a/!!!"
bangid="$(wsid "$root/a/!!!")"
echo "$bangid" | grep -q '^hestia-repo-[0-9a-f]\{12\}$' &&
	ok "empty sanitized label falls back to repo" || bad "fallback label: $bangid"
make_repo "$root/a/Ünïcode-Répo"
uniid="$(wsid "$root/a/Ünïcode-Répo")"
echo "$uniid" | grep -Eq '^hestia-[a-z0-9][a-z0-9-]{0,23}-[0-9a-f]{12}$' &&
	ok "non-ASCII basename yields a valid deterministic id" || bad "non-ASCII id: $uniid"
dashid="$("$wid" -- "$root/a/Ünïcode-Répo" | sed -n 's/^workspace: //p')"
[ "$dashid" = "$uniid" ] &&
	ok "-- terminator accepted before the path" || bad "-- terminator changed the result"

echo "== distinct paths, worktrees, stability =="
make_repo "$root/x/collide"
make_repo "$root/y/collide"
x_ws="$(wsid "$root/x/collide")"
y_ws="$(wsid "$root/y/collide")"
[ "$x_ws" != "$y_ws" ] &&
	ok "matching basenames at different paths differ ($x_ws vs $y_ws)" ||
	bad "same-basename paths collided: $x_ws"
git -C "$root/x/collide" worktree add -q -b wt "$root/x/collide-wt"
wt_ws="$(wsid "$root/x/collide-wt")"
[ "$x_ws" != "$wt_ws" ] &&
	ok "linked worktree has a distinct workspace id" || bad "worktree id equal: $wt_ws"
[ "$(grpid "$root/x/collide")" = "$(grpid "$root/x/collide-wt")" ] &&
	ok "main checkout and worktree share the repo-group id" || bad "repo-group differs"
git -C "$root/x/collide" switch -c other >/dev/null 2>&1
[ "$x_ws" = "$(wsid "$root/x/collide")" ] &&
	ok "branch change preserves the workspace id" || bad "branch changed id"
git -C "$root/x/collide" switch main >/dev/null 2>&1
ln -s "$root/x/collide" "$root/alias"
[ "$x_ws" = "$(wsid "$root/alias")" ] &&
	ok "symlink alias matches the canonical id" || bad "symlink alias diverged"

echo "== clear failures =="
if "$wid" "$root" >/dev/null 2>&1; then
	bad "non-git directory rejected"
else
	ok "non-git directory rejected"
fi
if "$wid" "$root/does-not-exist" >/dev/null 2>&1; then
	bad "missing path rejected"
else
	ok "missing path rejected"
fi

echo "== state record reuse =="
st="$root/state"
out1="$("$wid" --state-dir "$st" "$root/x/collide")"
out2="$("$wid" --state-dir "$st" "$root/x/collide")"
[ "$out1" = "$out2" ] && [ -f "$st/identity.record" ] &&
	ok "first --state-dir use records, reuse passes" || bad "state record round-trip"
mv "$root/x/collide" "$root/x/collide-moved"
if "$wid" --state-dir "$st" "$root/x/collide-moved" >"$root/err.txt" 2>&1; then
	bad "moved checkout fails against old state"
else
	grep -q "refusing to reuse" "$root/err.txt" &&
		ok "moved checkout fails with a clear error" ||
		bad "unclear error: $(cat "$root/err.txt")"
fi
grep -q "canonical: .*/collide$" "$st/identity.record" &&
	ok "old state record survives the move" || bad "old record rewritten"
moved_ws="$(wsid "$root/x/collide-moved")"
[ "$moved_ws" != "$x_ws" ] &&
	ok "moved checkout derives a new id ($moved_ws)" || bad "moved id unchanged"
st2="$root/state2"
"$wid" --state-dir "$st2" "$root/x/collide-moved" >/dev/null
canonical_moved="$(cd "$root/x/collide-moved" && pwd -P)"
printf 'canonical: %s\nrepo-group: hestia-forged-000000000000\nworkspace: hestia-forged-000000000000\n' \
	"$canonical_moved" >"$st2/identity.record"
if "$wid" --state-dir "$st2" "$root/x/collide-moved" >"$root/err2.txt" 2>&1; then
	bad "recorded-id mismatch fails"
else
	grep -q "collision" "$root/err2.txt" &&
		ok "recorded-id mismatch fails as a collision" ||
		bad "unclear collision error: $(cat "$root/err2.txt")"
fi

echo
echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
