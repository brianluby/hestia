#!/usr/bin/env bash
# JP73P2D — generate a scoped Compose workspace definition for one checkout.
#
# usage: workspace-compose.sh [--image IMG] [--out FILE] <checkout-path>
#
# Emits a Compose file (stdout, or --out) whose single `workspace` service
# binds exactly:
#   - the checkout's canonical path, at the identical path inside the
#     container (host tools and the container see the same source), and
#   - when the checkout is a linked worktree, the common Git directory at
#     its identical path too — required metadata only; the main checkout's
#     source is never mounted alongside, and
#   - the workspace's durable state directory (HESTIA_STATE_ROOT/<id>,
#     default ~/.local/share/hestia/<id>), at its identical path.
# Linux build/dependency caches (GOCACHE, GOMODCACHE) go to a workspace-scoped
# disposable Compose volume at /hestia/cache, separate from source, durable
# state and the image-installed toolchain (nothing is mounted over mise's
# install dirs, so image updates cannot be hidden by old state).
# The Compose project name is the checkout's workspace id from
# identity/workspace-id.sh, so containers, networks and volumes are namespaced
# per checkout with no fixed container names. No home or repository-collection
# mount, no host Docker socket, no credentials, by construction.
#
# Layouts and state are validated before anything is written: the checkout
# must be a Git repository, its .git pointer (if a file) must resolve under
# the common Git directory, the metadata must be readable, and the state
# directory's recorded identity must match this checkout (identity/workspace-
# id.sh --state-dir refuses reuse when the recorded canonical path differs).
# Unsupported layouts, unwritable state and identity mismatches fail with a
# clear error and no files are written.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wid="$here/identity/workspace-id.sh"

usage() {
	echo "usage: workspace-compose.sh [--image IMG] [--out FILE] <checkout-path>" >&2
	exit 2
}

image="hestia-fixture-tools:2026-09-09"
out=""
while [ "$#" -gt 0 ]; do
	case "$1" in
	--image)
		[ "$#" -ge 2 ] || usage
		image="$2"
		shift 2
		;;
	--out)
		[ "$#" -ge 2 ] || usage
		out="$2"
		shift 2
		;;
	-*) usage ;;
	*) break ;;
	esac
done
[ "$#" -eq 1 ] || usage
checkout="$1"

fail() {
	echo "workspace-compose: error: $*" >&2
	exit 1
}

[ -d "$checkout" ] || fail "not a directory: $checkout"

# Layout pre-checks before anything else, so unsupported layouts fail with a
# precise error rather than a generic identity failure.
if [ -f "$checkout/.git" ]; then
	raw_link="$(sed -n 's/^gitdir: *//p' "$checkout/.git")"
	[ -n "$raw_link" ] || fail "unsupported layout: $checkout/.git carries no gitdir pointer"
	case "$raw_link" in
	/*)
		[ -d "$raw_link" ] || fail "unsupported layout: gitdir target '$raw_link' does not exist"
		;;
	*)
		(cd "$checkout" && cd "$raw_link" 2>/dev/null) ||
			fail "unsupported layout: gitdir target '$raw_link' does not resolve from $checkout"
		;;
	esac
elif [ ! -d "$checkout/.git" ]; then
	fail "not a Git checkout: $checkout"
fi

ids="$("$wid" "$checkout")" || fail "cannot derive identity for $checkout"
canonical="$(printf '%s\n' "$ids" | sed -n 's/^canonical: //p')"
workspace_id="$(printf '%s\n' "$ids" | sed -n 's/^workspace: //p')"
[ -n "$canonical" ] && [ -n "$workspace_id" ] || fail "identity helper returned incomplete output"

common="$(git -C "$checkout" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" ||
	fail "cannot resolve the common Git directory (needs git >= 2.31): $checkout"
[ -d "$common" ] || fail "common Git directory missing: $common"
common="$(cd "$common" && pwd -P)"
[ -r "$common/config" ] || fail "common Git metadata is not readable: $common"

dotgit="$canonical/.git"
if [ -f "$dotgit" ]; then
	link="$(sed -n 's/^gitdir: *//p' "$dotgit")"
	[ -n "$link" ] || fail "unsupported layout: $dotgit carries no gitdir pointer"
	case "$link" in
	/*) linked="$link" ;;
	*)
		linked="$(cd "$canonical" && cd "$link" 2>/dev/null && pwd -P)" ||
			fail "unsupported layout: gitdir target '$link' does not resolve from $canonical"
		;;
	esac
	case "$linked" in
	"$common"/*) : ;;
	*) fail "unsupported layout: gitdir target '$linked' lies outside the common Git directory $common" ;;
	esac
fi

# A linked worktree needs the common Git directory mounted; a main checkout
# already contains it under its own mount.
own_common="$(cd "$dotgit" 2>/dev/null && pwd -P)" || own_common=""
git_paths=("$canonical")
if [ "$own_common" != "$common" ]; then
	git_paths+=("$common")
fi

# Durable state directory: workspace-scoped, identity-checked before reuse.
state_root="${HESTIA_STATE_ROOT:-$HOME/.local/share/hestia}"
state_dir="$state_root/$workspace_id"
if [ -e "$state_dir" ] && [ ! -w "$state_dir" ]; then
	fail "state directory exists but is not writable: $state_dir — fix its ownership/permissions before starting this workspace"
fi
"$wid" --state-dir "$state_dir" "$checkout" >/dev/null 2>&1 ||
	fail "state identity check failed for $state_dir — it may be recorded for a different checkout; inspect $state_dir/identity.record, then reattach or rehome the state explicitly"

sq() {
	printf '%s' "$1" | sed "s/'/''/g"
}

emit() {
	echo "# Generated by workspace/workspace-compose.sh from $canonical — do not edit."
	echo "name: $workspace_id"
	echo "services:"
	echo "  workspace:"
	echo "    image: $image"
	echo "    working_dir: '$(sq "$canonical")'"
	echo "    volumes:"
	local b
	for b in "${git_paths[@]}" "$state_dir"; do
		echo "      - type: bind"
		echo "        source: '$(sq "$b")'"
		echo "        target: '$(sq "$b")'"
	done
	echo "      - linux-caches:/hestia/cache"
	# Host and container UIDs differ; git only operates on repositories it
	# considers safely owned. Scope the exception to exactly the mounted
	# Git paths via protected environment config (honored since git 2.31;
	# observed working with the image's git 2.39.5).
	echo "    environment:"
	echo "      GIT_CONFIG_COUNT: \"${#git_paths[@]}\""
	local i=0
	for b in "${git_paths[@]}"; do
		echo "      GIT_CONFIG_KEY_$i: safe.directory"
		echo "      GIT_CONFIG_VALUE_$i: '$(sq "$b")'"
		i=$((i + 1))
	done
	# Disposable Linux build/dependency caches live in the workspace volume,
	# never in the shared source tree or the durable state directory.
	echo "      GOCACHE: /hestia/cache/go/build"
	echo "      GOMODCACHE: /hestia/cache/go/mod"
	echo "volumes:"
	echo "  linux-caches:"
}

if [ -n "$out" ]; then
	tmp="$out.tmp.$$"
	emit >"$tmp"
	mv "$tmp" "$out"
	echo "wrote $out (project $workspace_id)" >&2
else
	emit
fi
