#!/usr/bin/env bash
# G2ADH4M — byte-fidelity tests for fixtures/bin/fixture-snapshot.sh.
#
# The snapshot must hash the raw bytes on disk: non-ASCII and quoted names
# enumerate correctly, clean/EOL filters do not mask content changes, symlink
# retargeting is detected, and hash or enumeration failures propagate instead
# of recording an empty hash that compares clean. No Docker required.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
snap="$here/fixtures/bin/fixture-snapshot.sh"

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

tmp_base="${TMPDIR:-/tmp}"
root="$(mktemp -d "${tmp_base%/}/hestia-snapshot-test-XXXXXXXX")"
trap 'rm -rf "$root"' EXIT

repo="$root/repo"
git init -q -b main "$repo"
git -C "$repo" config user.name "Hestia Test"
git -C "$repo" config user.email "hestia-test@invalid"
git -C "$repo" config commit.gpgsign false
echo tracked >"$repo/tracked.txt"
git -C "$repo" add -A
git -C "$repo" commit -qm init

echo "== non-ASCII untracked name =="
printf 'umlaut content\n' >"$repo/üntracked.txt"
"$snap" capture "$repo" "$root/s1" >/dev/null
printf 'changed content\n' >"$repo/üntracked.txt"
if "$snap" compare "$repo" "$root/s1" >/dev/null 2>&1; then
	bad "non-ASCII file content change must fail comparison"
else
	ok "non-ASCII file content change fails comparison"
fi
"$snap" capture "$repo" "$root/s2" >/dev/null
"$snap" compare "$repo" "$root/s2" >/dev/null 2>&1 &&
	ok "recapture after change compares clean" || bad "recapture does not stabilize"

echo "== EOL flip under clean filters =="
printf '*.txt text eol=lf\n' >"$repo/.gitattributes"
git -C "$repo" add .gitattributes
git -C "$repo" commit -qm attrs
"$snap" capture "$repo" "$root/s3" >/dev/null
printf 'changed content\r\n' >"$repo/üntracked.txt"
if "$snap" compare "$repo" "$root/s3" >/dev/null 2>&1; then
	bad "LF to CRLF flip must fail comparison despite clean filters"
else
	ok "LF to CRLF flip fails comparison despite clean filters"
fi

echo "== symlink retarget =="
ln -s tracked.txt "$repo/link"
"$snap" capture "$repo" "$root/s4" >/dev/null
rm "$repo/link"
ln -s tracked2.txt "$repo/link"
if "$snap" compare "$repo" "$root/s4" >/dev/null 2>&1; then
	bad "symlink retarget must fail comparison"
else
	ok "symlink retarget fails comparison"
fi
rm "$repo/link"

echo "== tracked file deletion recorded, restoration detected =="
"$snap" capture "$repo" "$root/s5" >/dev/null
rm "$repo/tracked.txt"
if "$snap" compare "$repo" "$root/s5" >/dev/null 2>&1; then
	bad "tracked file deletion must fail comparison"
else
	ok "tracked file deletion fails comparison"
fi
"$snap" capture "$repo" "$root/s6" >/dev/null
grep -q "^missing	tracked.txt$" "$root/s6/files.worktree-sha" &&
	ok "deleted tracked file recorded as missing" || bad "missing file not recorded"
echo tracked >"$repo/tracked.txt"
"$snap" compare "$repo" "$root/s5" >/dev/null 2>&1 &&
	ok "restoration compares clean against the original snapshot" || bad "restored file still differs"

echo
echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
