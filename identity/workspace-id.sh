#!/usr/bin/env bash
# 503RD0P — derive bounded workspace and repo-group identity from canonical paths.
#
# usage: workspace-id.sh [--state-dir <dir>] <checkout-path>
#
# Prints three lines on success:
#   canonical:  symlink-resolved absolute path of the checkout
#   repo-group: hestia-<label>-<hash>  identity of the shared Git metadata
#   workspace:  hestia-<label>-<hash>  identity of this checkout
#
# With --state-dir, the first run writes identity.record (canonical path,
# repo-group, workspace) under that directory. Later runs verify the record and
# fail before reuse when the recorded path does not match the checkout's
# canonical path or the derived ids no longer agree, so state written for one
# checkout is never silently reused for another.
#
# Identity derives from the canonical checkout path only: branch, tool, agent
# or variant changes never change it; moving or copying the checkout does.
# Exact encoding and bounds are documented in identity/README.md.
set -euo pipefail

usage() {
	echo "usage: workspace-id.sh [--state-dir <dir>] <checkout-path>" >&2
	exit 2
}

state_dir=""
while [ "$#" -gt 0 ]; do
	case "$1" in
	--state-dir)
		[ "$#" -ge 2 ] || usage
		state_dir="$2"
		shift 2
		;;
	-*) usage ;;
	*) break ;;
	esac
done
[ "$#" -eq 1 ] || usage
checkout="$1"

fail() {
	echo "workspace-id: error: $*" >&2
	exit 1
}

[ -d "$checkout" ] || fail "not a directory: $checkout"

toplevel="$(git -C "$checkout" rev-parse --show-toplevel 2>/dev/null)" ||
	fail "not a Git checkout: $checkout"
canonical="$(cd "$toplevel" && pwd -P)"

common="$(git -C "$checkout" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" ||
	fail "cannot resolve the common Git directory (needs git >= 2.31): $checkout"
[ -d "$common" ] || fail "common Git directory missing: $common"
common="$(cd "$common" && pwd -P)"

sha256_hex() {
	if command -v sha256sum >/dev/null 2>&1; then sha256sum
	elif command -v shasum >/dev/null 2>&1; then shasum -a 256
	else openssl dgst -sha256 -r
	fi | cut -d' ' -f1
}

# ASCII label from a basename: lowercase, [a-z0-9] kept, other runs become one
# dash, leading/trailing dashes trimmed, bounded to 24 characters.
sanitize_label() {
	printf '%s' "$1" |
		tr '[:upper:]' '[:lower:]' |
		sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' |
		cut -c1-24 |
		sed -E 's/-+$//'
}

label_for() {
	local label
	label="$(sanitize_label "$1")"
	printf '%s' "${label:-repo}"
}

id_ok() {
	printf '%s' "$1" | grep -Eq '^hestia-[a-z0-9][a-z0-9-]{0,23}-[0-9a-f]{12}$'
}

ws_hash="$(printf '%s' "$canonical" | sha256_hex | cut -c1-12)"
workspace_id="hestia-$(label_for "$(basename "$canonical")")-${ws_hash}"
id_ok "$workspace_id" || fail "derived workspace id out of form: $workspace_id"

# The repo group is anchored on the shared Git metadata directory; the parent
# of that directory is the main checkout for normal repositories and worktrees.
grp_hash="$(printf '%s' "$common" | sha256_hex | cut -c1-12)"
repo_group="hestia-$(label_for "$(basename "$(dirname "$common")")")-${grp_hash}"
id_ok "$repo_group" || fail "derived repo-group id out of form: $repo_group"

if [ -n "$state_dir" ]; then
	record="$state_dir/identity.record"
	if [ -e "$record" ]; then
		rec_canonical="$(sed -n 's/^canonical: //p' "$record")"
		rec_group="$(sed -n 's/^repo-group: //p' "$record")"
		rec_workspace="$(sed -n 's/^workspace: //p' "$record")"
		{ [ -n "$rec_canonical" ] && [ -n "$rec_group" ] && [ -n "$rec_workspace" ]; } ||
			fail "unreadable identity record: $record"
		if [ "$rec_canonical" != "$canonical" ]; then
			fail "state in $state_dir was recorded for $rec_canonical; refusing to reuse it for $canonical — reattach state explicitly instead"
		fi
		if [ "$rec_workspace" != "$workspace_id" ] || [ "$rec_group" != "$repo_group" ]; then
			fail "identity collision on $canonical: record has $rec_workspace/$rec_group, derivation produced $workspace_id/$repo_group"
		fi
	else
		mkdir -p "$state_dir"
		tmp="$state_dir/identity.record.tmp.$$"
		printf 'canonical: %s\nrepo-group: %s\nworkspace: %s\n' \
			"$canonical" "$repo_group" "$workspace_id" >"$tmp"
		mv "$tmp" "$record"
	fi
fi

printf 'canonical: %s\n' "$canonical"
printf 'repo-group: %s\n' "$repo_group"
printf 'workspace: %s\n' "$workspace_id"
