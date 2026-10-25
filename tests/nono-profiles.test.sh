#!/usr/bin/env bash
# Validate the shipped nono profiles (agent/nono/*.json).
#
# The profiles ship root-owned in every agent image and are inert until an
# operator runs `nono run --profile ...`. This suite pins the properties a
# later edit could silently break: each profile validates with the pinned
# binary, each extends a sibling, and every agent profile filters egress while
# still admitting its own hosts. `hestia-base` is checked for validity only: it
# is unfiltered by design, because nono merges `block` with a sticky OR
# (base.block || child.block), so a blocking base could not have children that
# allow anything.
#
# nono is not installed on the host. Point the suite at a built image
# (`NONO_TEST_IMAGE=hestia-agent:<tag>`) or have `nono` on PATH; otherwise it
# reports skipped.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$here/agent/nono"

pass=0
fail=0
ok() { echo "ok   - $1"; pass=$((pass + 1)); }
bad() { echo "FAIL - $1"; fail=$((fail + 1)); }

echo "== profile files =="
for f in "$dir"/*.json; do
	name="$(basename "$f" .json)"
	if grep -Eq "\"name\":[[:space:]]*\"$name\"" "$f"; then
		ok "meta.name matches $(basename "$f")"
	else
		bad "meta.name missing or different in $(basename "$f")"
	fi
	extends="$(sed -n 's/.*"extends":[[:space:]]*"\([^"]*\)".*/\1/p' "$f")"
	if [ -n "$extends" ] && [ ! -f "$dir/$extends.json" ]; then
		case "$extends" in
		hestia-*) bad "$name extends '$extends', which is not a sibling profile" ;;
		esac # otherwise it names a built-in; nono validation checks it
	fi
done

# One script, run against either the host binary or inside an image, so each
# check exists once. $PDIR holds the profile directory for that environment.
checks='
set -u
fail=0
note() { echo "     $*"; fail=1; }
for f in "$PDIR"/*.json; do
	nono profile validate "$f" >/dev/null 2>&1 || note "invalid profile: $f"
done
host_is() { # profile, host, expected
	out="$(nono why --profile "$PDIR/$1.json" --host "$2" 2>/dev/null | head -1)"
	[ "$out" = "$3" ] || note "$1: $2 expected $3, got ${out:-nothing}"
}
for p in hestia-omp hestia-pig hestia-pi hestia-claude; do
	host_is "$p" github.com DENIED
done
host_is hestia-omp bedrock-runtime.us-west-2.amazonaws.com ALLOWED
host_is hestia-omp bedrock-runtime.amazonaws.com DENIED
host_is hestia-claude api.anthropic.com ALLOWED
host_is hestia-claude statsig.anthropic.com DENIED
host_is hestia-pig api.openai.com ALLOWED
host_is hestia-pi pi.dev ALLOWED
exit $fail'

echo "== nono checks =="
if command -v nono >/dev/null 2>&1; then
	if PDIR="$dir" bash -c "$checks"; then
		ok "all profiles validate and filter as documented (host nono)"
	else
		bad "profile checks failed (host nono)"
	fi
elif [ -n "${NONO_TEST_IMAGE:-}" ]; then
	if docker run --rm -e PDIR=/opt/hestia/nono --entrypoint sh "$NONO_TEST_IMAGE" -c "$checks"; then
		ok "all profiles validate and filter as documented ($NONO_TEST_IMAGE)"
	else
		bad "profile checks failed ($NONO_TEST_IMAGE)"
	fi
else
	echo "skipped: nono not on PATH and NONO_TEST_IMAGE unset"
	echo "         (set NONO_TEST_IMAGE=hestia-agent:<tag> to run inside a built image)"
	exit 0
fi

echo
echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
