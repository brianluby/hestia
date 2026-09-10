#!/usr/bin/env bash
# 503RD0P — derive bounded workspace and repo-group identity from canonical paths.
#
# usage: workspace-id.sh [--state-dir <dir>] [--] <checkout-path>
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
#
# Hardening (WXVTEZ7): git runs with ambient GIT_* location overrides removed
# so inherited variables cannot redirect identity to another repository;
# label sanitization is byte-wise deterministic (LC_ALL=C); resolved paths are
# validated absolute; --state-dir "" is a usage error; the record is created
# atomically (create-if-absent, mode 0600 under a 0700 directory) and parsed
# strictly — known keys, exactly once — with malformed records reported as
# such instead of masquerading as identity mismatches.
set -euo pipefail
export LC_ALL=C

usage() {
	echo "usage: workspace-id.sh [--state-dir <dir>] [--] <checkout-path>" >&2
	exit 2
}

state_dir=""
state_flag=0
while [ "$#" -gt 0 ]; do
	case "$1" in
	--state-dir)
		[ "$#" -ge 2 ] || usage
		state_dir="$2"
		state_flag=1
		shift 2
		;;
	--)
		shift
		break
		;;
	-*) usage ;;
	*) break ;;
	esac
done
[ "$#" -eq 1 ] || usage
if [ "$state_flag" -eq 1 ] && [ -z "$state_dir" ]; then
	echo "workspace-id: error: --state-dir must not be empty (unset variables expand to empty)" >&2
	exit 2
fi
checkout="$1"

fail() {
	echo "workspace-id: error: $*" >&2
	exit 1
}

# All git access goes through xgit: ambient GIT_DIR/GIT_WORK_TREE/... would
# otherwise redirect resolution away from the requested checkout.
xgit() {
	env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_OBJECT_DIRECTORY \
		-u GIT_ALTERNATE_OBJECT_DIRECTORIES -u GIT_COMMON_DIR -u GIT_NAMESPACE \
		-u GIT_CONFIG_COUNT git "$@"
}

assert_safe_path() {
	# absolute, non-empty, no control characters; grep cannot see newline
	# separators (line-based), so they are matched explicitly first.
	case "$1" in
	"") fail "empty path where $2 was expected" ;;
	/*) : ;;
	*) fail "relative path where absolute $2 was expected: $1" ;;
	esac
	case "$1" in
	*$'\n'* | *$'\r'* | *$'\t'*) fail "line-break or tab characters in $2" ;;
	esac
	if printf '%s' "$1" | grep -q "$(printf '[\001-\037\177]')"; then
		fail "control characters in $2: $1"
	fi
}

[ -d "$checkout" ] || fail "not a directory: $checkout"

toplevel="$(xgit -C "$checkout" rev-parse --show-toplevel 2>/dev/null)" ||
	fail "not a Git checkout: $checkout"
canonical="$(cd "$toplevel" && pwd -P)"
assert_safe_path "$canonical" "checkout path"

common="$(xgit -C "$checkout" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" ||
	fail "cannot resolve the common Git directory (needs git >= 2.31): $checkout"
[ -d "$common" ] || fail "common Git directory missing: $common"
common="$(cd "$common" && pwd -P)"
assert_safe_path "$common" "common Git directory"

sha256_hex() {
	if command -v sha256sum >/dev/null 2>&1; then sha256sum
	elif command -v shasum >/dev/null 2>&1; then shasum -a 256
	elif command -v openssl >/dev/null 2>&1; then openssl dgst -sha256 -r
	else
		echo "workspace-id: error: no supported sha256 tool found (need sha256sum, shasum or openssl)" >&2
		exit 1
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

# Strict record reader: exactly the three known keys, each once, nothing else.
# Sets rec_canonical / rec_group / rec_workspace.
read_record() {
	rec_canonical=""
	rec_group=""
	rec_workspace=""
	local line
	while IFS= read -r line || [ -n "$line" ]; do
		case "$line" in
		"canonical: "*) [ -z "$rec_canonical" ] || fail "malformed record (duplicate canonical): $record"
			rec_canonical="${line#canonical: }" ;;
		"repo-group: "*) [ -z "$rec_group" ] || fail "malformed record (duplicate repo-group): $record"
			rec_group="${line#repo-group: }" ;;
		"workspace: "*) [ -z "$rec_workspace" ] || fail "malformed record (duplicate workspace): $record"
			rec_workspace="${line#workspace: }" ;;
		"") : ;;
		*) fail "malformed record (unrecognized line): $record" ;;
		esac
	done <"$record"
	{ [ -n "$rec_canonical" ] && [ -n "$rec_group" ] && [ -n "$rec_workspace" ]; } ||
		fail "malformed record (missing keys): $record"
}

if [ -n "$state_dir" ]; then
	record="$state_dir/identity.record"
	if [ -e "$record" ]; then
		read_record
		if [ "$rec_canonical" != "$canonical" ]; then
			fail "state in $state_dir was recorded for $rec_canonical; refusing to reuse it for $canonical — reattach state explicitly instead"
		fi
		if [ "$rec_workspace" != "$workspace_id" ] || [ "$rec_group" != "$repo_group" ]; then
			fail "identity collision on $canonical: record has $rec_workspace/$rec_group, derivation produced $workspace_id/$repo_group"
		fi
	else
		[ -d "$state_dir" ] || mkdir -p "$state_dir"
		chmod 700 "$state_dir"
		tmp="$(mktemp "$state_dir/identity.record.XXXXXX")"
		printf 'canonical: %s\nrepo-group: %s\nworkspace: %s\n' \
			"$canonical" "$repo_group" "$workspace_id" >"$tmp"
		chmod 600 "$tmp"
		# Atomic create-if-absent: concurrent first writers converge on one
		# record; the loser's verification of the winner's record must agree.
		if ! ln "$tmp" "$record" 2>/dev/null; then
			rm -f "$tmp"
			read_record
			if [ "$rec_canonical" != "$canonical" ] || [ "$rec_workspace" != "$workspace_id" ] || [ "$rec_group" != "$repo_group" ]; then
				fail "state in $state_dir was concurrently created for a different checkout; refusing to reuse it for $canonical"
			fi
		fi
	fi
fi

printf 'canonical: %s\n' "$canonical"
printf 'repo-group: %s\n' "$repo_group"
printf 'workspace: %s\n' "$workspace_id"
