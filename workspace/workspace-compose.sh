#!/usr/bin/env bash
# JP73P2D — generate a scoped Compose workspace definition for one checkout.
#
# usage: workspace-compose.sh [--image IMG] [--out FILE] [--state SPEC]...
#                            [--env NAME=VALUE]... <checkout-path>
#
# Emits a Compose file (stdout, or --out) whose single `workspace` service
# binds exactly:
#   - the checkout's canonical path, at the identical path inside the
#     container (host tools and the container see the same source), and
#   - when the checkout is a linked worktree, the common Git directory at
#     its identical path too — required metadata only; the main checkout's
#     source is never mounted alongside, and
#   - the workspace's durable state directory (HESTIA_STATE_ROOT/<id>,
#     default ~/.local/share/hestia/<id>), at its identical path, and
#   - one durable agent-state directory per --state SPEC, named after the
#     agent: a subdirectory of the state directory, bound at its own
#     container path (default /home/dev/.<name>). Without --state the single
#     default is omp's `omp` → /home/dev/.omp. The state directory itself
#     stays bound at its identical path (first bullet), so the container can
#     also reach the other agents' state under it: --state chooses where the
#     harness is pointed, not what is reachable. One workspace variant per
#     checkout is the supported model (ADR-003), and each state target must
#     be its own container path.
# --env NAME=VALUE adds one service environment variable for an agent that
# loads, say, a policy overlay by variable; names the generator owns are
# refused rather than silently emitted twice, and a name given twice is
# refused rather than written as a duplicate YAML key. Values are written
# verbatim into the generated file and the container environment, so never
# pass a credential value (ADR-004) — supply credentials at runtime instead.
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
	echo "usage: workspace-compose.sh [--image IMG] [--out FILE] [--state NAME[:CONTAINER_PATH]]... [--env NAME=VALUE]... <checkout-path>" >&2
	exit 2
}

fail() {
	echo "workspace-compose: error: $*" >&2
	exit 1
}

# Shared git-environment sanitising and value validation (identity/lib.sh).
# shellcheck source=identity/lib.sh
. "$here/identity/lib.sh"

image="hestia-fixture-tools:2026-09-09"
out=""
state_specs=()
env_extra=()
while [ "$#" -gt 0 ]; do
	case "$1" in
	--image)
		[ "$#" -ge 2 ] || usage
		image="$2"
		reject_unsafe_value "$image" "image reference"
		printf '%s' "$image" | grep -Eq '^[A-Za-z0-9./:@_-]+$' ||
			fail "invalid image reference (allowed: A-Za-z0-9 . / : @ _ -): $image"
		shift 2
		;;
	--out)
		[ "$#" -ge 2 ] || usage
		out="$2"
		shift 2
		;;
	--state)
		# NAME or NAME:CONTAINER_PATH. NAME is a plain subdirectory name, so
		# by construction the state stays inside the workspace state
		# directory and cannot be pointed at the checkout or the image.
		[ "$#" -ge 2 ] || usage
		spec="$2"
		name="${spec%%:*}"
		reject_unsafe_value "$name" "state name"
		printf '%s' "$name" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9_-]*$' ||
			fail "--state expects NAME or NAME:CONTAINER_PATH, with NAME limited to letters, digits, _ and - : $spec"
		case "$spec" in
		*:*) assert_safe_path "${spec#*:}" "container path in --state $name" ;;
		esac
		state_specs+=("$spec")
		shift 2
		;;
	--env)
		[ "$#" -ge 2 ] || usage
		name="${2%%=*}"
		[ "$name" != "$2" ] || fail "--env expects NAME=VALUE (got: $2)"
		reject_unsafe_value "$name" "environment variable name"
		printf '%s' "$name" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*$' ||
			fail "invalid environment variable name: $name"
		case "$name" in
		PATH | HOME | GIT_CONFIG_* | GOCACHE | GOMODCACHE | PI_CONFIG_FILES)
			fail "--env cannot override the generated $name — edit the generator if that value is wrong for this agent"
			;;
		esac
		# Repeating a name would emit the YAML key twice, which Compose only
		# rejects later ("mapping key already defined").
		for seen in ${env_extra[@]+"${env_extra[@]}"}; do
			[ "${seen%%=*}" = "$name" ] || continue
			fail "--env $name was given twice — one value per variable"
		done
		reject_unsafe_value "${2#*=}" "environment value for $name"
		env_extra+=("$2")
		shift 2
		;;
	-*) usage ;;
	*) break ;;
	esac
done
[ "$#" -eq 1 ] || usage
checkout="$1"

# Default agent state is omp's ~/.omp (XJVWF4K). Any --state above replaces it,
# so a workspace generated for another harness does not inherit an omp bind.
if [ "${#state_specs[@]}" -eq 0 ]; then
	state_specs=("omp:/home/dev/.omp")
fi

[ -d "$checkout" ] || fail "not a directory: $checkout"

# Layout pre-checks before anything else, so unsupported layouts fail with a
# precise error rather than a generic identity failure. A path that is merely
# inside a checkout is not rejected here: the identity helper below resolves
# the checkout root, and it reports a non-checkout with the same clear error.
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
fi

ids="$("$wid" "$checkout")" || fail "cannot derive identity for $checkout"
canonical="$(printf '%s\n' "$ids" | sed -n 's/^canonical: //p')"
workspace_id="$(printf '%s\n' "$ids" | sed -n 's/^workspace: //p')"
[ -n "$canonical" ] && [ -n "$workspace_id" ] || fail "identity helper returned incomplete output"

common="$(xgit -C "$checkout" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" ||
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
# A relative root is rejected outright: the record would be written relative
# to the generator's working directory while Compose resolves bind sources
# relative to the generated file's directory, so the two ends would silently
# disagree (review finding 5).
state_root="${HESTIA_STATE_ROOT:-$HOME/.local/share/hestia}"
case "$state_root" in
/*) : ;;
*)
	fail "HESTIA_STATE_ROOT must be an absolute path; got the relative '$state_root' (its meaning would differ between the generator's and the Compose file's directories)"
	;;
esac
state_dir="$state_root/$workspace_id"
if [ -e "$state_dir" ] && [ ! -w "$state_dir" ]; then
	fail "state directory exists but is not writable: $state_dir — fix its ownership/permissions before starting this workspace"
fi
"$wid" --state-dir "$state_dir" "$checkout" >/dev/null 2>&1 ||
	fail "state identity check failed for $state_dir — it may be recorded for a different checkout; inspect $state_dir/identity.record, then reattach or rehome the state explicitly"

# Agent state (XJVWF4K): each --state NAME[:CONTAINER_PATH] gets a directory
# under the workspace state tree, created here dev-owned, and bound at its
# container path. That is what makes sessions, settings and login survive
# recreations for any harness, not just omp.
#
# omp's specific rationale, still the default: omp keeps sessions, memory and
# its settings under ~/.omp. The whole tree is writable so omp can persist
# settings (model selection, theme) with its atomic tmp+rename write
# (FA5H9TR). Its provider-restriction policy ships in the image at
# /opt/hestia/omp/config.yml — a root-owned directory, so the runtime user can
# neither edit nor replace it — and is loaded as a config overlay via
# PI_CONFIG_FILES: omp merges overlays after the user's own config (overlay
# wins) and refuses to start when a configured overlay is missing, so the
# policy cannot be overridden by editing the writable config. The policy is
# loaded by env var rather than a bind because mounting the state dir at
# ~/.omp would hide any image copy under that tree, and binding a read-only
# file into it made omp's atomic settings writes fail (EBUSY).
state_target() {
	case "$1" in
	*:*) printf '%s' "${1#*:}" ;;
	*) printf '/home/dev/.%s' "${1%%:*}" ;;
	esac
}

# Compose needs one mount per container target: a state target that repeats a
# generated target (the checkout, the Git metadata, the state directory) or
# another state target would hide it or fail at up rather than here. Validate
# every target before creating any directory. A target can name a generated
# mount through a symlinked spelling (macOS /var → /private/var) and still land
# on it inside the container, so physical paths are compared where the target
# exists on this host.
state_dir_phys="$(cd "$state_dir" 2>/dev/null && pwd -P)" || state_dir_phys="$state_dir"
state_targets=()
for spec in "${state_specs[@]}"; do
	target="$(state_target "$spec")"
	probe="$target"
	if [ -d "$target" ]; then
		probe="$(cd "$target" && pwd -P)"
	fi
	for b in "${git_paths[@]}" "$state_dir" "$state_dir_phys" ${state_targets[@]+"${state_targets[@]}"}; do
		[ "$probe" != "$b" ] ||
			fail "--state target '$target' is already a mount target of this workspace; give each state its own container path"
	done
	state_targets+=("$probe")
done

for spec in "${state_specs[@]}"; do
	mkdir -p "$state_dir/${spec%%:*}"
done

# YAML single-quote escaping plus literal-dollar doubling: Compose applies
# $VAR interpolation to values even inside single quotes, so a path like
# .../cash$VARIABLE must be emitted as .../cash$$VARIABLE to survive.
sq() {
	printf '%s' "$1" | sed -e 's/\$/\$\$/g' -e "s/'/''/g"
}

emit() {
	reject_unsafe_value "$canonical" "checkout path"
	reject_unsafe_value "$common" "common Git directory"
	reject_unsafe_value "$state_dir" "state directory"
	echo "# Generated by workspace/workspace-compose.sh from $canonical — do not edit."
	echo "name: $workspace_id"
	echo "services:"
	echo "  workspace:"
	echo "    image: $image"
	echo "    working_dir: '$(sq "$canonical")'"
	# Keep the workspace running so it can be attached to; `compose run`
	# overrides this with the requested command.
	echo "    command: [\"sleep\", \"infinity\"]"
	echo "    volumes:"
	local b s
	for b in "${git_paths[@]}" "$state_dir"; do
		echo "      - type: bind"
		echo "        source: '$(sq "$b")'"
		echo "        target: '$(sq "$b")'"
	done
	for s in "${state_specs[@]}"; do
		echo "      - type: bind"
		echo "        source: '$(sq "$state_dir/${s%%:*}")'"
		echo "        target: '$(sq "$(state_target "$s")")'"
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
	# Provider-restriction policy overlay (FA5H9TR): root-owned in the image,
	# merged after the user's own config so it cannot be overridden, and
	# fail-closed (omp errors out when a configured overlay is missing).
	echo "      PI_CONFIG_FILES: /opt/hestia/omp/config.yml"
	# --env entries, last so a reader sees agent-specific values together.
	# ${arr[@]+...} keeps an empty list valid under set -u on bash 3.2.
	local e
	for e in ${env_extra[@]+"${env_extra[@]}"}; do
		echo "      ${e%%=*}: '$(sq "${e#*=}")'"
	done
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
