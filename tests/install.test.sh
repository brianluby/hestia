#!/usr/bin/env bash
# ADR-006 step 1 — acceptance tests for install.sh. No Docker needed.
#
# Runs the installer with a temporary HOME and PATH (a fake `docker`), so the
# real ~/.local/bin, /opt/homebrew/bin and /usr/local/bin are never on PATH
# and never touched.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
pass=0
fail=0
ok() { echo "ok   - $1"; pass=$((pass + 1)); }
bad() { echo "FAIL - $1"; fail=$((fail + 1)); }

fake="$root/fakebin"
mkdir -p "$fake"
printf '#!/bin/sh\nexit 1\n' >"$fake/docker" # installed, daemon unreachable
chmod +x "$fake/docker"
base="$fake:/usr/bin:/bin"
export HOME="$root/home"
mkdir -p "$HOME/.local/bin"
run() { PATH="$1" "$here/install.sh" 2>&1; }

echo "== preferred writable directory on PATH =="
out="$(run "$HOME/.local/bin:$base")" && ok "installer succeeds" || bad "installer failed: $out"
[ "$(readlink "$HOME/.local/bin/hestia")" = "$here/hestia" ] && ok "$HOME/.local/bin/hestia links to the clone's launcher" || bad "no link"
printf '%s' "$out" | grep -q 'daemon is not reachable' && ok "unreachable daemon is a warning, install continues" || bad "no daemon warning: $out"
printf '%s' "$out" | grep -q "git -C $here pull" && ok "update command is printed" || bad "no update line"
out="$(run "$HOME/.local/bin:$base")" && [ "$(readlink "$HOME/.local/bin/hestia")" = "$here/hestia" ] && ok "re-run is idempotent" || bad "re-run failed: $out"
other="$root/other-clone"
mkdir -p "$other/identity" "$other/workspace"
touch "$other/hestia" "$other/install.sh" "$other/identity/workspace-id.sh" "$other/workspace/workspace-lifecycle.sh"
ln -sfn "$other/hestia" "$HOME/.local/bin/hestia"
run "$HOME/.local/bin:$base" >/dev/null && [ "$(readlink "$HOME/.local/bin/hestia")" = "$here/hestia" ] && ok "a link to another Hestia clone is replaced" || bad "other clone's link kept"
ln -sfn "$root/moved-clone/hestia" "$HOME/.local/bin/hestia"
run "$HOME/.local/bin:$base" >/dev/null && bad "dangling link replaced" || { [ "$(readlink "$HOME/.local/bin/hestia")" = "$root/moved-clone/hestia" ] && ok "a dangling link is refused (ownership cannot be checked)"; }
mkdir -p "$root/unrelated" && touch "$root/unrelated/hestia"
ln -sfn "$root/unrelated/hestia" "$HOME/.local/bin/hestia"
run "$HOME/.local/bin:$base" >/dev/null && bad "unrelated */hestia link replaced" || { [ "$(readlink "$HOME/.local/bin/hestia")" = "$root/unrelated/hestia" ] && ok "a link to an unrelated */hestia is refused"; }
rm "$HOME/.local/bin/hestia"
run "$HOME/.local/bin:$base" >/dev/null
out="$(run /usr/bin:/bin)"
printf '%s' "$out" | grep -q 'Docker is not installed' && ok "missing Docker is a warning" || bad "no missing-Docker warning"

echo "== a foreign hestia is never overwritten =="
rm "$HOME/.local/bin/hestia"
printf '#!/bin/sh\necho mine\n' >"$HOME/.local/bin/hestia"
if out="$(run "$HOME/.local/bin:$base")"; then bad "foreign file overwritten: $out"; else
	printf '%s' "$out" | grep -q 'not a link to a Hestia clone' && [ "$(cat "$HOME/.local/bin/hestia")" = "$(printf '#!/bin/sh\necho mine')" ] &&
		ok "refuses and leaves the file" || bad "unclear refusal: $out"
fi
rm "$HOME/.local/bin/hestia"
ln -s /bin/ls "$HOME/.local/bin/hestia"
run "$HOME/.local/bin:$base" >/dev/null && bad "foreign symlink replaced" || { [ "$(readlink "$HOME/.local/bin/hestia")" = /bin/ls ] && ok "refuses a foreign symlink"; }
rm "$HOME/.local/bin/hestia"

echo "== no writable directory on PATH =="
out="$(run "$base")" && ok "installer succeeds" || bad "installer failed: $out"
[ "$(printf '%s' "$out" | grep -c '^export PATH=')" -eq 1 ] && printf '%s\n' "$out" | grep -qxF "export PATH=\"$here:\$PATH\"" &&
	ok "prints the one profile line" || bad "no export line: $out"
[ ! -e "$HOME/.local/bin/hestia" ] && ok "nothing is linked and no profile is edited" || bad "linked anyway"
chmod 555 "$HOME/.local/bin"
out="$(run "$HOME/.local/bin:$base")" && printf '%s' "$out" | grep -q '^export PATH=' && ok "a read-only PATH directory is skipped" || bad "read-only dir used: $out"
chmod 755 "$HOME/.local/bin"
[ "$(ls -A "$HOME")" = .local ] && ok "HOME gained no profile files" || bad "HOME changed: $(ls -A "$HOME")"

echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
