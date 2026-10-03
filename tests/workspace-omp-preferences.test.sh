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
# Record one completed synthetic assertion.
ok() { echo "ok - $1"; pass=$((pass + 1)); }
# Remove only this test workspace runtime/cache and optionally retain artifacts.
cleanup() {
	if [ -n "$project" ]; then
		docker compose -p "$project" -f "$root/ws.yml" down --remove-orphans >/dev/null 2>&1 || true
		docker volume rm "${project}_linux-caches" >/dev/null 2>&1 || true
	fi
	if [ "${KEEP_ARTIFACTS:-0}" = 1 ]; then echo "artifacts: $root"; else rm -rf "$root"; fi
}
# Reject any excluded synthetic credential/database/session/provider value.
assert_appearance_only() {
	if grep -q HESTIA_SYNTHETIC "$1"; then
		echo "FAIL - excluded synthetic value copied into native settings" >&2
		return 1
	fi
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
chmod 0600 "$root/host/agent/config.yml"
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
python3 - "$agent_dir/config.yml" <<'PY_MODE'
import pathlib, stat, sys
assert stat.S_IMODE(pathlib.Path(sys.argv[1]).stat().st_mode) == 0o600
PY_MODE
ok "private mode-0600 source imports exact selected appearance leaves into mode-0600 native config"
assert_appearance_only "$agent_dir/config.yml"
printf '%s\n' HESTIA_SYNTHETIC_CREDENTIAL_CONTROL >"$root/tainted-config.yml"
if assert_appearance_only "$root/tainted-config.yml" >"$root/sentinel-control.log" 2>&1; then exit 1; fi
ok "credential exclusion gate explicitly rejects a matching synthetic value"
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
# Run a native command in this test workspace only.
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
# Test-owned Bash startup injects a partial settings write and an I/O failure.
# Other printf operations and the isolated native reader are unchanged.
cat >"$root/fail-write.bash" <<'FAIL_WRITE'
# Fail only the completed preference payload write after emitting a partial byte.
printf() {
    if [ "$#" -eq 2 ] && [ "$1" = '%s\n' ] && [[ "$2" == *'"theme"'* ]]; then
        builtin printf '{'
        return 1
    fi
    builtin printf "$@"
}
FAIL_WRITE
if BASH_ENV="$root/fail-write.bash" "$seed" --source "$root/host/agent/config.yml" --key theme.dark "$root/ws.yml" >"$root/write-failure.log" 2>&1; then exit 1; fi
grep -q 'private config write failed' "$root/write-failure.log"
[ ! -e "$agent_dir/config.yml" ]
[ -z "$(find "$agent_dir" -maxdepth 1 -name '.hestia-preferences.*' -print -quit)" ]
ok "partial write failure publishes no native config and cleans its private file"
"$seed" --source "$root/host/agent/config.yml" --key theme.dark "$root/ws.yml" >/dev/null
jq -e '.theme.dark == "dark-nord" and (keys | length) == 1' "$agent_dir/config.yml" >/dev/null
[ -z "$(find "$agent_dir" -maxdepth 1 -name '.hestia-preferences.*' -print -quit)" ]
ok "successful retry after a failed write publishes complete preferences"
rm "$agent_dir/config.yml"

# Create a conflicting exact destination only after all helper state guards,
# immediately before the exclusive publication syscall.
mkdir -p "$root/race-bin"
cat >"$root/race-bin/python3" <<'RACE_PUBLISH'
#!/usr/bin/env bash
set -euo pipefail
case "$HESTIA_SEED_RACE_KIND" in
    file) printf '%s\n' HESTIA_CONCURRENT_CONFIG >"$3" ;;
    directory) mkdir "$3" ;;
    symlink) ln -s "$HESTIA_SEED_RACE_TARGET" "$3" ;;
esac
exec "$HESTIA_SEED_REAL_PYTHON" "$@"
RACE_PUBLISH
chmod +x "$root/race-bin/python3"
real_python="$(command -v python3)"
printf '%s\n' HESTIA_CONCURRENT_CONFIG >"$root/concurrent-target"
for kind in file directory symlink; do
    if PATH="$root/race-bin:$PATH" HESTIA_SEED_REAL_PYTHON="$real_python" \
        HESTIA_SEED_RACE_KIND="$kind" HESTIA_SEED_RACE_TARGET="$root/concurrent-target" \
        "$seed" --source "$root/host/agent/config.yml" --key theme.dark "$root/ws.yml" >"$root/publication-$kind.log" 2>&1; then exit 1; fi
    grep -q 'native config appeared or could not be published' "$root/publication-$kind.log"
    [ -z "$(find "$agent_dir" -maxdepth 1 -name '.hestia-preferences.*' -print -quit)" ]
    case "$kind" in
        file) grep -qx HESTIA_CONCURRENT_CONFIG "$agent_dir/config.yml"; rm "$agent_dir/config.yml" ;;
        directory) [ -z "$(find "$agent_dir/config.yml" -mindepth 1 -print -quit)" ]; rmdir "$agent_dir/config.yml" ;;
        symlink) [ "$(readlink "$agent_dir/config.yml")" = "$root/concurrent-target" ]; grep -qx HESTIA_CONCURRENT_CONFIG "$root/concurrent-target"; rm "$agent_dir/config.yml" ;;
    esac
done
ok "exclusive exact-path publication preserves a racing file, directory or symlink and cleans private files"
printf 'theme:\n  dark: {token: HESTIA_SYNTHETIC_SECRET_DO_NOT_COPY}\n' >"$root/invalid.yml"
if "$seed" --source "$root/invalid.yml" --key theme.dark "$root/ws.yml" >/dev/null 2>&1; then exit 1; fi
[ ! -e "$agent_dir/config.yml" ]
ok "structured values cannot smuggle unrelated fields through appearance leaves"
printf 'passed: %s, failed: 0\n' "$pass"
