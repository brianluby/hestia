#!/usr/bin/env bash
# ADR-006 — tests for workspace/image-tag.sh: the launcher's image tag changes
# exactly when a build input of the Dockerfile's `pi` target changes. No Docker.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tag="$here/workspace/image-tag.sh"
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
pass=0
fail=0
ok() { echo "ok   - $1"; pass=$((pass + 1)); }
bad() { echo "FAIL - $1"; fail=$((fail + 1)); }

mkdir "$root/ctx"
cp -R "$here/Dockerfile" "$here/fixtures" "$here/agent" "$here/docs" "$root/ctx/"
base="$("$tag" "$root/ctx")"
printf '%s' "$base" | grep -Eqx 'hestia-pi:[0-9a-f]{12}' && ok "tag is hestia-pi:<12 hex>" || bad "unexpected tag: $base"
[ "$("$tag" "$root/ctx")" = "$base" ] && ok "tag is stable" || bad "tag changed with no input change"
[ "$("$tag")" = "$base" ] && ok "the repository's own inputs give the same tag as a copy" || bad "copy differs from the repository"

changed() { [ "$("$tag" "$root/ctx")" != "$base" ]; }
echo '# x' >>"$root/ctx/Dockerfile"
changed && ok "a Dockerfile change gives a new tag" || bad "Dockerfile change ignored"
cp "$here/Dockerfile" "$root/ctx/Dockerfile"
echo '{}' >"$root/ctx/agent/nono/hestia-pi.json"
changed && ok "a change in a copied directory gives a new tag" || bad "agent/nono change ignored"
cp "$here/agent/nono/hestia-pi.json" "$root/ctx/agent/nono/"
echo '# x' >>"$root/ctx/fixtures/synthetic/mise.toml"
changed && ok "a fixture toolchain change gives a new tag" || bad "fixture change ignored"
cp "$here/fixtures/synthetic/mise.toml" "$root/ctx/fixtures/synthetic/"
echo x >>"$root/ctx/agent/omp/config.yml"
echo x >>"$root/ctx/docs/architecture.md"
touch "$root/ctx/agent/nono/.DS_Store"
changed && bad "an unrelated change rebuilt the image" || ok "omp, docs and .DS_Store changes keep the tag"

# Every COPY source of the stages the pi target builds on must feed the tag.
missing=0
while read -r src; do
	grep -qF "${src%/}" "$tag" || { bad "COPY source not hashed by image-tag.sh: $src"; missing=1; }
done < <(awk '/^FROM /{s=$NF} /^COPY /&&(s=="base"||s=="fixture-tools"||s=="nono"||s=="pi"){for(i=2;i<NF;i++) if($i!~/^--/) print $i}' "$here/Dockerfile" |
	sed -E 's#^(fixtures/synthetic|agent/nono).*#\1#' | sort -u)
[ "$missing" -eq 0 ] && ok "every COPY source of the pi target's stages is hashed" || true

echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
