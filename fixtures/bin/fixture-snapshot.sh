#!/usr/bin/env bash
# SKSJTMN — record or compare fixture state for later persistence checks.
#
# usage:
#   fixture-snapshot.sh capture <git-dir> <out-dir>
#   fixture-snapshot.sh compare <git-dir> <snapshot-dir>
#
# capture writes, under <out-dir>:
#   files.worktree-sha   git blob hash and path of every tracked and untracked
#                        file in the working tree (the actual source bytes,
#                        including staged, unstaged and untracked changes)
#   index.ls-files       git ls-files --stage (the full index listing)
#   index.tree           git write-tree (index as a tree object)
#   head.commit/head.tree/head.branch   recorded HEAD state
#   status.porcelain-v2/status.short    full status, including untracked files
#   worktrees.porcelain  git worktree list --porcelain
#
# compare re-captures the current state and diffs it against <snapshot-dir>;
# it exits non-zero and prints the differences when anything has drifted.
# Records are deterministic for an unchanged repository, so identical content
# compares clean and any durable difference shows up in the diff.
set -euo pipefail

die() {
	echo "fixture-snapshot: error: $*" >&2
	exit 1
}

usage() {
	echo "usage: $0 capture <git-dir> <out-dir>" >&2
	echo "       $0 compare <git-dir> <snapshot-dir>" >&2
	exit 2
}

cmd="${1:-}"
repo="${2:-}"
target="${3:-}"
[ "$#" -eq 3 ] || usage
{ [ "$cmd" = "capture" ] || [ "$cmd" = "compare" ]; } || usage
git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || {
	echo "not a usable git directory: $repo" >&2
	exit 2
}

capture() {
	local repo="$1" out="$2"
	mkdir -p "$out"
	git -C "$repo" rev-parse HEAD >"$out/head.commit"
	git -C "$repo" symbolic-ref -q HEAD >"$out/head.branch" || echo "(detached)" >"$out/head.branch"
	git -C "$repo" rev-parse 'HEAD^{tree}' >"$out/head.tree"
	git -C "$repo" write-tree >"$out/index.tree"
	git -C "$repo" ls-files --stage >"$out/index.ls-files"
	git -C "$repo" status --porcelain=v2 --branch >"$out/status.porcelain-v2"
	git -C "$repo" status --short >"$out/status.short"
	git -C "$repo" worktree list --porcelain >"$out/worktrees.porcelain"
	# Raw working-tree bytes: NUL-delimited enumeration survives names git
	# would quote/escape, --no-filters hashes the bytes on disk rather than
	# clean-filtered content, and every failure propagates instead of being
	# masked inside a printf (review finding 2). Symlinks hash their link
	# target; a tracked-but-deleted path is recorded as missing rather than
	# silently skipped.
	: >"$out/files.worktree-sha"
	tmp_base="${TMPDIR:-/tmp}"
	list_file="$(mktemp "${tmp_base%/}/hestia-snapshot-list.XXXXXX")"
	trap 'rm -f "$list_file"' RETURN
	git -C "$repo" ls-files -z --cached --others --exclude-standard >"$list_file" ||
		die "git ls-files failed in $repo"
	local f h tgt
	while IFS= read -r -d '' f; do
		if [ -L "$repo/$f" ]; then
			tgt="$(readlink "$repo/$f")" || die "readlink failed for $f"
			h="$(printf '%s' "$tgt" | git -C "$repo" hash-object --stdin --no-filters)" ||
				die "hash-object failed for symlink $f"
		elif [ -e "$repo/$f" ]; then
			h="$(git -C "$repo" hash-object --no-filters -- "$f")" ||
				die "hash-object failed for $f"
		else
			h="missing"
		fi
		printf '%s\t%s\n' "$h" "$f" >>"$out/files.worktree-sha"
	done <"$list_file"
}

case "$cmd" in
capture)
	capture "$repo" "$target"
	echo "captured fixture state of $repo to $target"
	;;
compare)
	tmp_base="${TMPDIR:-/tmp}"
	tmp="$(mktemp -d "${tmp_base%/}/hestia-fixture-compare-XXXXXXXX")"
	trap 'rm -rf "$tmp"' EXIT
	capture "$repo" "$tmp/current"
	if ! diff -r "$target" "$tmp/current"; then
		echo "fixture state of $repo DIFFERS from $target" >&2
		exit 1
	fi
	echo "fixture state of $repo matches $target"
	;;
esac
