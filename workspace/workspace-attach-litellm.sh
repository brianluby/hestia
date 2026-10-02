#!/usr/bin/env bash
# AWCEX5Z — explicit session-only LiteLLM handoff to native omp.
# Disable tracing before accessing credentials, including bash -x callers.
set +x
set -euo pipefail

usage() {
	echo 'usage: workspace-attach-litellm.sh --endpoint URL --model ID [--trace-id UUID] [--no-tty] <compose-file> [omp-args...]' >&2
	exit 2
}
fail() { echo "workspace-attach-litellm: $*" >&2; exit 1; }
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
endpoint=''
model=''
trace_id=''
no_tty=0
while [ "$#" -gt 0 ]; do
	case "$1" in
	--endpoint) [ -z "$endpoint" ] && [ "$#" -ge 2 ] || usage; endpoint="$2"; shift 2 ;;
	--model) [ -z "$model" ] && [ "$#" -ge 2 ] || usage; model="$2"; shift 2 ;;
	--trace-id) [ -z "$trace_id" ] && [ "$#" -ge 2 ] && [ -n "$2" ] || usage; trace_id="$2"; shift 2 ;;
	--no-tty) no_tty=1; shift ;;
	-*) usage ;;
	*) break ;;
	esac
done
[ -n "$endpoint" ] && [ -n "$model" ] && [ "$#" -ge 1 ] || usage
file="$1"; shift
# This explicit handoff supports the default scoped profile and native session
# controls, but rejects flags that could replace its routing/model boundary.
for arg in "$@"; do
    case "$arg" in
    --) break ;;
    --provider|--provider=*|--model|--model=*|--models|--models=*|--smol|--smol=*|--slow|--slow=*|--plan|--plan=*|--api-key|--api-key=*|--profile|--profile=*|--alias|--alias=*|--config|--config=*|--cwd|--cwd=*|--session-dir|--session-dir=*|--plugin-dir|--plugin-dir=*|--extension|--extension=*|-e*|--trusted-extension|--trusted-extension=*|--hook|--hook=*|--no-extensions=*)
        fail 'caller routing, role, profile, storage and extension overrides are unsupported by this scoped handoff' ;;
    esac
done
case "$endpoint$model" in
*$'\n'* | *$'\r'*) fail 'endpoint and model cannot contain line breaks' ;;
esac
# URL values are never reported on errors. Limit this helper to plain HTTP(S)
# hostnames/IPv4 and paths; credentials, queries, fragments and controls fail.
printf '%s' "$endpoint" | grep -Eq '^https?://[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:[0-9]{1,5})?(/[^?#@[:space:][:cntrl:]]*)?$' ||
	fail 'endpoint must be an HTTP(S) URL with a hostname and no credentials, query, fragment or whitespace'
authority="${endpoint#*://}"; authority="${authority%%/*}"
case "$authority" in
*:*) port="${authority##*:}"; [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || fail 'endpoint port must be between 1 and 65535' ;;
esac
printf '%s' "$model" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._:/-]*$' ||
	fail 'model must be an explicit nonempty model ID without whitespace or control characters'
case "$trace_id" in
*$'\n'* | *$'\r'*) fail 'trace ID must be a UUID' ;;
esac
if [ -n "$trace_id" ]; then
    printf '%s' "$trace_id" | grep -Eq '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$' ||
        fail 'trace ID must be a UUID'
fi
[ -n "${LITELLM_API_KEY:-}" ] || fail 'export a scoped nonempty LITELLM_API_KEY on the host and retry'
# Existing preflight verifies identity, Compose and the local image.
"$here/workspace-lifecycle.sh" validate "$file" >/dev/null
project="$(sed -n 's/^name: //p' "$file" | head -1)"
docker compose -p "$project" -f "$file" exec -T workspace bash -c 'test -r /opt/hestia/omp/litellm.yml && test -r /opt/hestia/omp/litellm-session.sh' >/dev/null 2>&1 ||
	fail 'running workspace with LiteLLM overlay required; build the current agent target explicitly and recreate'
# Bound metadata checks and launch to the same default native storage. Reject
# ambient redirection and dotenv files without reading or printing values.
docker compose -p "$project" -f "$file" exec -T workspace bash -c '
    set -euo pipefail
    test "$HOME" = /home/dev
    test ! -L "$HOME/.omp/agent"
    if test -e "$HOME/.omp/agent"; then test -d "$HOME/.omp/agent"; fi
    for name in PI_CONFIG_DIR PI_CODING_AGENT_DIR OMP_PROFILE PI_PROFILE XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME XDG_CONFIG_HOME OMP_AUTH_BROKER_URL OMP_AUTH_BROKER_TOKEN; do
        if [[ -v "$name" ]]; then exit 1; fi
    done
    for directory in "$PWD" "$HOME/.omp/agent" "$HOME/.omp" "$HOME"; do
        if test ! -e "$directory"; then continue; fi
        found="$(find "$directory" -maxdepth 1 \( -name .env -o -name ".env.*" \) -print -quit)"
        test -z "$found"
    done
    for filename in models.yml models.yaml models.json; do
        if test -e "$HOME/.omp/agent/$filename" || test -L "$HOME/.omp/agent/$filename"; then exit 1; fi
    done' >/dev/null 2>&1 ||
    fail 'custom model files, dotenv, redirected storage/profile or broker environment unsupported; use fresh default scoped state or deliberately resolve native configuration before handoff'
# Stored LiteLLM auth can take precedence over the exported key. Inspect only
# provider presence in scoped SQLite storage; preserve session/settings rows.
command -v python3 >/dev/null || fail 'host Python 3 required for read-only native credential metadata checks'
docker compose -p "$project" -f "$file" config --format json 2>/dev/null | python3 -c '
import json, pathlib, sqlite3, sys
try:
    mounts = json.load(sys.stdin)["services"]["workspace"]["volumes"]
    sources = [m["source"] for m in mounts if m.get("type") == "bind" and m.get("target") == "/home/dev/.omp"]
    if len(sources) != 1:
        raise ValueError()
    state = pathlib.Path(sources[0])
    agent = state / "agent"
    if state.is_symlink() or agent.is_symlink() or (agent.exists() and not agent.is_dir()):
        raise ValueError()
    if (agent / "auth.json").exists() or (agent / "auth.json").is_symlink():
        raise ValueError()
    db = agent / "agent.db"
    if db.is_symlink():
        raise ValueError()
    if db.exists():
        with sqlite3.connect(db.as_uri() + "?mode=ro", uri=True, timeout=1) as connection:
            if connection.execute("SELECT MAX(version) FROM schema_version").fetchone()[0] != 6:
                raise ValueError()
            if not (agent / "config.yml").exists() and not (agent / "config.yaml").exists():
                if connection.execute("SELECT EXISTS(SELECT 1 FROM settings)").fetchone()[0]:
                    raise ValueError()
            present = connection.execute("SELECT EXISTS(SELECT 1 FROM auth_credentials WHERE provider = ? AND disabled_cause IS NULL)", ("litellm",)).fetchone()[0]
        if present:
            raise ValueError()
except Exception:
    sys.exit(1)
' >/dev/null 2>&1 ||
    fail 'stored native LiteLLM auth, legacy settings/auth or unreadable metadata; use fresh scoped state or deliberately resolve native auth before handoff'
# Safe host YAML/JSON parsing inspects broker key presence only. The native
# config CLI initializes/migrates state, so it is not used for this guard.
command -v ruby >/dev/null || fail 'host Ruby with standard-library Psych required for read-only broker metadata checks'
docker compose -p "$project" -f "$file" config --format json 2>/dev/null | ruby -rjson -rpsych -e '
begin
  compose = JSON.parse(STDIN.read)["services"]["workspace"]
  sources = compose["volumes"].select { |m| m["type"] == "bind" && m["target"] == "/home/dev/.omp" }
  raise if sources.length != 1
  agent = File.join(sources[0]["source"], "agent")
  project = File.join(compose["working_dir"], ".omp")
  paths = [File.join(agent, "config.yml"), File.join(agent, "config.yaml"),
           File.join(agent, "settings.json"), File.join(project, "config.yml"),
           File.join(project, "settings.json")]
  paths.each do |path|
    raise if File.symlink?(File.dirname(path)) || File.symlink?(path)
    next unless File.exist?(path)
    data = path.end_with?(".json") ? JSON.parse(File.read(path)) :
      Psych.safe_load(File.read(path), permitted_classes: [], permitted_symbols: [], aliases: false)
    next if data.nil?
    raise unless data.is_a?(Hash)
    raise if data.key?("auth.broker.url")
    auth = data["auth"]
    raise if auth.is_a?(Hash) && auth["broker"].is_a?(Hash) && auth["broker"].key?("url")
  end
rescue StandardError
  exit 1
end
' >/dev/null 2>&1 ||
    fail 'broker selection or unsupported native settings metadata; use fresh default scoped state or deliberately resolve native configuration before handoff'
# A fresh nonsecret correlation ID is scoped to this native handoff. Header
# values are resolved from this name by the temporary native provider config.
[ -n "$trace_id" ] || trace_id="$(python3 -c 'import uuid; print(uuid.uuid4())')"
export HESTIA_LITELLM_TRACE_ID="$trace_id"
export LITELLM_API_KEY
export LITELLM_BASE_URL="$endpoint" PI_CONFIG_FILES=/opt/hestia/omp/litellm.yml
# Bare -e names keep endpoint/key/trace values out of Docker argv and Compose.
# The image wrapper retains ownership across discovery and native omp, then
# removes only its own temporary model config on normal exit or caught signals.
exec_args=(exec)
[ "$no_tty" -eq 0 ] || exec_args+=(-T)
exec_args+=(-e PI_CONFIG_FILES -e LITELLM_BASE_URL -e LITELLM_API_KEY -e HESTIA_LITELLM_TRACE_ID workspace)
exec docker compose -p "$project" -f "$file" "${exec_args[@]}" \
    bash /opt/hestia/omp/litellm-session.sh "$model" "$@"
