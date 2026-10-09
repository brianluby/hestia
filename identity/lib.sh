# shellcheck shell=bash
# Shared shell helpers for the Hestia workspace scripts.
#
# Sourced by identity/workspace-id.sh and workspace/workspace-compose.sh so the
# git-environment sanitising and value validation below exist once. Callers
# must define fail() before sourcing: the error prefix stays theirs
# ("workspace-id: error: ..." vs "workspace-compose: error: ...").

# All git access goes through xgit: ambient GIT_DIR/GIT_WORK_TREE/... would
# otherwise redirect metadata resolution away from the requested checkout.
xgit() {
	env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_OBJECT_DIRECTORY \
		-u GIT_ALTERNATE_OBJECT_DIRECTORIES -u GIT_COMMON_DIR -u GIT_NAMESPACE \
		-u GIT_CONFIG_COUNT git "$@"
}

# Values are emitted into YAML and consumed by Compose interpolation; control
# characters would break the file structure, so they are rejected outright.
# grep is line-based and cannot see the newline separator itself, so the
# structure-breaking characters are matched explicitly first.
reject_unsafe_value() {
	case "$1" in
	*$'\n'* | *$'\r'* | *$'\t'*) fail "line-break or tab characters in $2" ;;
	esac
	if printf '%s' "$1" | grep -q "$(printf '[\001-\037\177]')"; then
		fail "control characters in $2: $1"
	fi
}

# Paths additionally have to be absolute and non-empty, because they become
# bind sources and targets whose meaning must not depend on the reader's
# working directory.
assert_safe_path() {
	case "$1" in
	"") fail "empty path where $2 was expected" ;;
	/*) : ;;
	*) fail "relative path where absolute $2 was expected: $1" ;;
	esac
	reject_unsafe_value "$1" "$2"
}
