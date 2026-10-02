#!/usr/bin/env bash
# WF6TXF9 — explicitly copy selected appearance preferences once; never mount
# host omp state into a workspace. Reads only one supplied config file in a
# network-disabled disposable container using the workspace's pinned omp.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
usage() {
	echo "usage: workspace-omp-preferences.sh --source CONFIG --key KEY [--key KEY...] <compose-file>" >&2
	echo "keys: theme.dark theme.light symbolPreset composer.shape colorBlindMode statusLine.preset" >&2
	exit 2
}
fail() { echo "workspace-omp-preferences: error: $*" >&2; exit 1; }

source_config=""
keys=()
while [ "$#" -gt 0 ]; do
	case "$1" in
	--source)
		[ "$#" -ge 2 ] || usage
		source_config="$2"
		shift 2
		;;
	--key)
		[ "$#" -ge 2 ] || usage
		case "$2" in
		theme.dark | theme.light | symbolPreset | composer.shape | colorBlindMode | statusLine.preset) keys+=("$2") ;;
		*) fail "unsupported preference key; use an explicitly listed appearance key" ;;
		esac
		shift 2
		;;
	-*) usage ;;
	*) break ;;
	esac
done
[ "$#" -eq 1 ] && [ -n "$source_config" ] && [ "${#keys[@]}" -gt 0 ] || usage
compose="$1"
command -v jq >/dev/null 2>&1 || fail "host jq is required"
[ -f "$source_config" ] && [ -r "$source_config" ] || fail "source must be one readable config file"
# Docker --mount uses commas as field separators. Fail before passing an
# ambiguous source specification to Docker, and never print its contents.
case "$source_config" in *','* | *$'\n'* | *$'\r'*) fail "unsupported source path characters" ;; esac
source_config="$(cd "$(dirname "$source_config")" && pwd -P)/$(basename "$source_config")"

"$here/workspace/workspace-lifecycle.sh" validate "$compose" >/dev/null
# Explicit project and file flags avoid ambient Compose project/file selection.
project="$(sed -n 's/^name: //p' "$compose")"
resolved="$(docker compose -p "$project" -f "$compose" config --format json)"
image="$(printf '%s' "$resolved" | jq -er '.services.workspace.image')" || fail "no workspace image"
agent_state="$(printf '%s' "$resolved" | jq -er '[.services.workspace.volumes[] | select(.type == "bind" and .target == "/home/dev/.omp") | .source] | if length == 1 then .[0] else error("ambiguous omp state") end')" || fail "omp state bind is missing or ambiguous"
[ -d "$agent_state" ] && [ ! -L "$agent_state" ] || fail "omp state must be a real directory"
agent_dir="$agent_state/agent"
[ ! -L "$agent_dir" ] || fail "agent directory must not be a symlink"
# Creating YAML ahead of legacy migration would suppress settings in an
# existing database or settings.json. Preserve all such workspaces untouched.
for existing in config.yml config.yaml settings.json agent.db; do
	if [ -e "$agent_dir/$existing" ] || [ -L "$agent_dir/$existing" ]; then
		echo "workspace-omp-preferences: existing native settings/state preserved; no preferences copied" >&2
		exit 0
	fi
done

running="$(docker compose -p "$project" -f "$compose" ps -q --status running workspace)" || fail "cannot inspect workspace runtime"
[ -z "$running" ] || fail "stop the workspace and finish all agent writes before first-time seeding"

# Only this single source file is exposed to the one-shot reader. The global
# agent directory and cwd are isolated /tmp locations; config get is upstream's
# read-only path and does not open agent.db or perform legacy migrations.
# No host credentials, sessions, models.yml, or writable host home are mounted.
records="$(docker run --rm --pull never --network none --workdir /tmp \
	--mount "type=bind,source=$source_config,target=/opt/hestia-preferences.yml,readonly" \
	--env PI_CODING_AGENT_DIR=/tmp/hestia-preference-reader \
	--env PI_CONFIG_FILES=/opt/hestia-preferences.yml \
	--entrypoint /bin/bash "$image" -c \
	'for key in "$@"; do omp config get "$key" --json || exit 1; done' _ "${keys[@]}" 2>/dev/null)" ||
	fail "pinned omp could not read selected preferences; source and destination are unchanged"
# Strict value shapes prevent structures or unrelated fields being smuggled
# through an appearance leaf. JSON mappings are valid YAML for native omp.
preferences="$(printf '%s' "$records" | jq -es '
	all(.[];
		if .key == "colorBlindMode" then (.value | type) == "boolean"
		elif .key == "symbolPreset" then (.value == "unicode" or .value == "nerd" or .value == "ascii")
		elif .key == "composer.shape" then (.value | IN("band","box","claude","pi","borderless","rule","field","rail"))
		elif .key == "statusLine.preset" then (.value | IN("default","minimal","compact","full","nerd","ascii"))
		elif .key == "theme.dark" or .key == "theme.light" then (.value | type) == "string" and (.value | test("^[a-z][a-z0-9-]{0,95}$"))
		else false end
	) as $valid |
	if $valid then reduce .[] as $record ({}; setpath($record.key | split("."); $record.value))
	else error("invalid selected preference") end
')" 2>/dev/null || fail "selected preferences have unsupported values; nothing copied"

# A first agent launch during the reader must not suppress legacy migration.
for existing in config.yml config.yaml settings.json agent.db; do
	if [ -e "$agent_dir/$existing" ] || [ -L "$agent_dir/$existing" ]; then
		echo "workspace-omp-preferences: native state appeared; existing settings preserved" >&2
		exit 0
	fi
done
[ ! -L "$agent_dir" ] || fail "agent directory became a symlink; nothing copied"
running="$(docker compose -p "$project" -f "$compose" ps -q --status running workspace)" || fail "cannot inspect workspace runtime"
[ -z "$running" ] || fail "workspace started while reading preferences; nothing copied"

mkdir -p "$agent_dir"
# Native omp remains the only settings writer after this one-time creation.
# noclobber preserves a config created concurrently instead of overwriting it.
if ! (umask 077; set -o noclobber; printf '%s\n' "$preferences" >"$agent_dir/config.yml") 2>/dev/null; then
	fail "native config appeared or could not be created; existing settings preserved"
fi
echo "workspace-omp-preferences: copied ${#keys[@]} selected appearance keys; native settings remain writable" >&2
