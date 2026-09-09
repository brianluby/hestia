#!/usr/bin/env bash
# SKSJTMN — create an isolated synthetic build/test fixture in fresh temporary storage.
#
# Creates, under one throwaway root directory with a unique name:
#   repo/                   main checkout of a small Go project with a declared
#                           mise toolchain, one commit, then staged, unstaged and
#                           untracked changes on top
#   worktrees/wt-abs/       linked worktree using Git's default absolute gitdir link
#   worktrees/wt-rel/       linked worktree whose gitdir links are relative paths
#   snapshots/00-created/   recorded state for later persistence comparisons
#   FIXTURE.txt             everything this run printed, plus versions and paths
#
# The fixture never uses personal or employer repositories: all content is
# synthetic and lives under the fresh root. Cleanup is exactly
# `rm -rf <root>`; the path is printed at the end.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
template="$here/../synthetic"

tmp_base="${TMPDIR:-/tmp}"
root="$(mktemp -d "${tmp_base%/}/hestia-fixture-XXXXXXXX")"
id="$(basename "$root")"
id="${id#hestia-fixture-}"
main="$root/repo"
log="$root/FIXTURE.txt"
mkdir -p "$main" "$root/worktrees" "$root/snapshots"

{
	echo "Hestia synthetic fixture $id"
	echo "root: $root"
	echo "created: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
	echo "host: $(uname -srm)"
	echo "git: $(git --version)"
	echo "mise: $(mise --version)"
} | tee "$log"

run() {
	echo "+ $*" | tee -a "$log"
	"$@" 2>&1 | tee -a "$log"
}

run_in() {
	local dir="$1"
	shift
	echo "+ (cd $dir && $*)" | tee -a "$log"
	(cd "$dir" && "$@") 2>&1 | tee -a "$log"
}

echo "=== project from template ===" | tee -a "$log"
cp -R "$template/." "$main/"
run git -C "$main" init -b main
git -C "$main" config user.name "Hestia Fixture"
git -C "$main" config user.email "hestia-fixture@invalid"
git -C "$main" config commit.gpgsign false
run git -C "$main" add -A
run git -C "$main" commit -m "synthetic fixture: initial project"

echo "=== dirty Git states ===" | tee -a "$log"
printf '\n// staged change for fixture %s (in the index, uncommitted)\n' "$id" >> "$main/greet/greet.go"
run git -C "$main" add greet/greet.go
printf '\n// unstaged change for fixture %s (working tree only)\n' "$id" >> "$main/cmd/greet/main.go"
printf 'synthetic untracked notes for fixture %s\n' "$id" > "$main/NOTES.md"
run git -C "$main" status --short

echo "=== linked worktrees ===" | tee -a "$log"
run git -C "$main" worktree add -b "fixture/$id-abs" "$root/worktrees/wt-abs"
run git -C "$main" worktree add -b "fixture/$id-rel" "$root/worktrees/wt-rel"

echo "--- convert wt-rel gitdir links to relative paths ---" | tee -a "$log"
printf 'gitdir: ../../repo/.git/worktrees/wt-rel\n' > "$root/worktrees/wt-rel/.git"
printf '../../../../worktrees/wt-rel/.git\n' > "$main/.git/worktrees/wt-rel/gitdir"
run cat "$root/worktrees/wt-rel/.git"
run cat "$main/.git/worktrees/wt-rel/gitdir"
if (cd "$root/worktrees/wt-rel" && git rev-parse --git-dir >/dev/null 2>&1); then
	echo "relative links resolve without repair" | tee -a "$log"
else
	echo "relative links need repair; running git worktree repair" | tee -a "$log"
	run git -C "$main" worktree repair
fi
run cat "$root/worktrees/wt-rel/.git"
run cat "$main/.git/worktrees/wt-rel/gitdir"
run git -C "$main" worktree list --porcelain
run git -C "$root/worktrees/wt-rel" rev-parse --git-dir --git-common-dir HEAD

echo "=== build and test (declared mise toolchain) ===" | tee -a "$log"
run_in "$main" mise exec -- go version
run_in "$main" mise exec -- go build ./...
run_in "$main" mise exec -- go test ./...

echo "=== snapshot ===" | tee -a "$log"
run "$here/fixture-snapshot.sh" capture "$main" "$root/snapshots/00-created"

echo | tee -a "$log"
echo "fixture ready: $root" | tee -a "$log"
echo "cleanup: rm -rf $root" | tee -a "$log"
