#!/usr/bin/env bash
# WF6TXF9 — synthetic runtime checks; never reads real host omp preferences.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image="${HESTIA_AGENT_TEST_IMAGE:-hestia-agent:2026-09-10}"
for cmd in docker jq; do
	command -v "$cmd" >/dev/null 2>&1 || { echo "SKIP: $cmd unavailable"; exit 0; }
done
docker info >/dev/null 2>&1 || { echo "SKIP: Docker unavailable"; exit 0; }
docker image inspect "$image" >/dev/null 2>&1 || { echo "SKIP: agent image not built"; exit 0; }
base="$HOME/.cache/hestia-omp-preference-tests"
mkdir -p "$base"
root="$(mktemp -d "$base/hestia-XXXXXXXX")"
export HESTIA_STATE_ROOT="$root/state"
project=""
pass=0
ok() { echo "ok - $1"; pass=$((pass + 1)); }
cleanup() {
	if [ -n "$project" ]; then
		docker compose -p "$project" -f "$root/ws.yml" down --remove-orphans >/dev/null 2>&1 || true
		docker volume rm "${project}_linux-caches" >/dev/null 2>&1 || true
	fi
	if [ "${KEEP_ARTIFACTS:-0}" = 1 ]; then echo "artifacts: $root"; else rm -rf "$root"; fi
}
trap cleanup EXIT
mkdir -p "$root/repo" "$root/host/agent/sessions"
git -C "$root/repo" -c init.defaultBranch=main init -q
cat >"$root/host/agent/config.yml" <<'CONFIG'
theme:
  dark: dark-nord
  light: light-github
symbolPreset: ascii
composer:
  shape: borderless
colorBlindMode: true
statusLine:
  preset: minimal
disabledProviders: []
auth:
  broker:
    token: HESTIA_SYNTHETIC_SECRET_DO_NOT_COPY
CONFIG
printf '%s\n' HESTIA_SYNTHETIC_DATABASE >"$root/host/agent/agent.db"
printf '%s\n' HESTIA_SYNTHETIC_SESSION >"$root/host/agent/sessions/session.jsonl"
printf '%s\n' HESTIA_SYNTHETIC_CUSTOM_PROVIDER >"$root/host/agent/models.yml"
source_hash="$(shasum -a 256 "$root/host/agent/config.yml")"
"$here/workspace/workspace-compose.sh" --image "$image" --out "$root/ws.yml" "$root/repo" >/dev/null
project="$(sed -n 's/^name: //p' "$root/ws.yml")"
agent_dir="$HESTIA_STATE_ROOT/$project/omp/agent"
seed="$here/workspace/workspace-omp-preferences.sh"
"$here/workspace/workspace-lifecycle.sh" start "$root/ws.yml" >/dev/null
if "$seed" --source "$root/host/agent/config.yml" --key theme.dark "$root/ws.yml" >/dev/null 2>&1; then exit 1; fi
[ ! -e "$agent_dir/config.yml" ]
ok "first-time import refuses a running workspace without mutation"
"$here/workspace/workspace-lifecycle.sh" stop "$root/ws.yml" >/dev/null
"$seed" --source "$root/host/agent/config.yml" --key theme.dark --key theme.light \
	--key symbolPreset --key composer.shape --key colorBlindMode --key statusLine.preset "$root/ws.yml" >/dev/null
jq -e '.theme.dark == "dark-nord" and .theme.light == "light-github" and .symbolPreset == "ascii" and .composer.shape == "borderless" and .colorBlindMode == true and .statusLine.preset == "minimal" and (keys | length) == 5' "$agent_dir/config.yml" >/dev/null
ok "exact selected appearance leaves copied into native config"
! grep -q HESTIA_SYNTHETIC "$agent_dir/config.yml"
[ ! -e "$agent_dir/agent.db" ] && [ ! -e "$agent_dir/sessions" ] && [ ! -e "$agent_dir/models.yml" ]
ok "credentials, database, sessions and custom providers were not copied"
[ "$source_hash" = "$(shasum -a 256 "$root/host/agent/config.yml")" ]
ok "source preferences unchanged"
config_hash="$(shasum -a 256 "$agent_dir/config.yml")"
"$seed" --source "$root/host/agent/config.yml" --key theme.dark "$root/ws.yml" >/dev/null
[ "$config_hash" = "$(shasum -a 256 "$agent_dir/config.yml")" ]
ok "existing native config preserved byte for byte"
if "$seed" --source "$root/host/agent/config.yml" --key auth.broker.token "$root/ws.yml" >/dev/null 2>&1; then exit 1; fi
[ "$config_hash" = "$(shasum -a 256 "$agent_dir/config.yml")" ]
ok "credential setting rejected without mutation"
"$here/workspace/workspace-lifecycle.sh" start "$root/ws.yml" >/dev/null
exec_ws() { docker compose -p "$project" -f "$root/ws.yml" exec -T workspace "$@"; }
[ "$(exec_ws omp config get theme.dark)" = dark-nord ]
[ "$(exec_ws omp config get composer.shape)" = borderless ]
ok "pinned omp loads copied JSON mapping as native YAML"
exec_ws omp config get disabledProviders --json | jq -e '.value | index("anthropic") != null and index("bedrock") == null' >/dev/null
[ "$(exec_ws omp config get setupVersion)" = 2 ]
ok "image provider policy and onboarding marker still win"
exec_ws omp config set theme.dark dark-github >/dev/null
[ "$(exec_ws omp config get theme.dark)" = dark-github ]
ok "copied native settings remain writable with omp config set"
config_hash="$(shasum -a 256 "$agent_dir/config.yml")"
"$here/workspace/workspace-lifecycle.sh" recreate "$root/ws.yml" >/dev/null
[ "$config_hash" = "$(shasum -a 256 "$agent_dir/config.yml")" ]
[ "$(exec_ws omp config get theme.dark)" = dark-github ]
ok "native preference changes survive recreation"

"$here/workspace/workspace-lifecycle.sh" stop "$root/ws.yml" >/dev/null

# Preserve a legacy workspace rather than shadowing its pending migration.
mv "$agent_dir/config.yml" "$root/saved.yml"
printf '%s\n' HESTIA_SYNTHETIC_EXISTING_DATABASE >"$agent_dir/agent.db"
"$seed" --source "$root/host/agent/config.yml" --key theme.dark "$root/ws.yml" >/dev/null
[ ! -e "$agent_dir/config.yml" ]
ok "existing legacy database is not suppressed by seeding"
rm "$agent_dir/agent.db"
printf 'theme:\n  dark: {token: HESTIA_SYNTHETIC_SECRET_DO_NOT_COPY}\n' >"$root/invalid.yml"
if "$seed" --source "$root/invalid.yml" --key theme.dark "$root/ws.yml" >/dev/null 2>&1; then exit 1; fi
[ ! -e "$agent_dir/config.yml" ]
ok "structured values cannot smuggle unrelated fields through appearance leaves"
printf 'passed: %s, failed: 0\n' "$pass"
