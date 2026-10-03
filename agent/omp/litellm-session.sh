#!/usr/bin/env bash
# 4AC12YE — transient native LiteLLM discovery/inference header configuration.
# Pinned omp 18.1.16 sources (commit 61b1b8aef634334eaf1412afd003a763e1d1b9c1):
# packages/coding-agent/src/config/model-discovery.ts:930-984
# packages/coding-agent/src/config/model-registry.ts:1394-1408,1708-1714
# packages/coding-agent/src/config/model-config-values.ts:83-91
# No header values or credentials are stored in this native configuration.
set +x
set -euo pipefail
umask 077
# Report a bounded error without exposing endpoint, credential or trace values.
fail() { echo "hestia-litellm-session: $*" >&2; exit 1; }
[ "$#" -ge 1 ] || fail 'exact model argument required'
model="$1"; shift
[ "${HOME:-}" = /home/dev ] || fail 'default scoped native home required'
[ -n "${LITELLM_API_KEY:-}" ] && [ -n "${LITELLM_BASE_URL:-}" ] ||
    fail 'scoped runtime endpoint and key required'
case "${HESTIA_LITELLM_TRACE_ID:-}" in
*$'\n'* | *$'\r'*) fail 'nonempty UUID trace environment required' ;;
esac
printf '%s' "${HESTIA_LITELLM_TRACE_ID:-}" | grep -Eq '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$' ||
    fail 'nonempty UUID trace environment required'
printf '%s' "$model" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._:/-]*$' ||
    fail 'exact model ID required'
agent="$HOME/.omp/agent"
[ ! -L "$agent" ] || fail 'default agent directory cannot be a symlink'
if [ -e "$agent" ]; then
    [ -d "$agent" ] || fail 'default agent directory required'
fi
mkdir -p "$agent"
lock="$agent/.hestia-litellm.lock"
mkdir "$lock" 2>/dev/null ||
    fail 'another or interrupted LiteLLM handoff owns scoped state; finish it or deliberately resolve the retained helper lock'
private=''
config=''
published=0
link_inode=''
# Preserve exit status and remove only this handoff's configuration and lock.
cleanup() {
    status=$?
    trap - EXIT
    # Never unlink a replacement native file or a pointer we did not publish.
    if [ "$published" -eq 1 ] && [ -L "$agent/models.yml" ] &&
       [ "$(readlink "$agent/models.yml")" = "$config" ] &&
       [ "$(stat -c %i "$agent/models.yml")" = "$link_inode" ]; then
        rm -f -- "$agent/models.yml"
    fi
    if [ -n "$private" ]; then
        rm -f -- "$config"
        rmdir -- "$private" 2>/dev/null || true
    fi
    rmdir -- "$lock" 2>/dev/null || true
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
for filename in models.yml models.yaml models.json; do
    if [ -e "$agent/$filename" ] || [ -L "$agent/$filename" ]; then
        fail 'existing native model configuration retained; resolve it deliberately before handoff'
    fi
done
private="$(mktemp -d /tmp/hestia-litellm.XXXXXXXX)"
config="$private/models.yml"
# JSON is a YAML subset. jq reads only the validated endpoint from its process
# environment; the trace header contains an env-name reference, never a value.
# Generic OpenAI discovery retains the explicitly selected Chat Completions
# API; LiteLLM rich metadata can select Responses for chat-only local servers.
# Native advertised/reference/default metadata supplies limits; these are not
# backend qualification. No custom definitions or credential values are
# introduced. Native cache restoration
# requires an explicit environment-name key reference plus authHeader.
(set -C; jq -n '{providers: {litellm: {
    baseUrl: env.LITELLM_BASE_URL,
    api: "openai-completions",
    apiKey: "LITELLM_API_KEY",
    authHeader: true,
    headers: {"x-litellm-trace-id": "HESTIA_LITELLM_TRACE_ID"},
    discovery: {type: "openai-models-list", injectV1: false}
}}}' > "$config")
chmod 0400 "$config"
# GNU ln -T is exclusive and rejects files, symlinks and directories. The private
# target disappears on cleanup; forced SIGKILL leaves a guard-visible pointer.
ln -sT -- "$config" "$agent/models.yml" 2>/dev/null ||
    fail 'native model configuration appeared during handoff; existing file retained'
link_inode="$(stat -c %i "$agent/models.yml")"
published=1
catalog="$(omp models litellm --json --no-extensions 2>/dev/null)" ||
    fail 'native LiteLLM discovery failed; verify endpoint, key permissions and trace policy'
printf '%s' "$catalog" | jq -e --arg model "$model" \
    '.models | any(.provider == "litellm" and .id == $model)' >/dev/null 2>&1 ||
    fail 'exact selected model unavailable from native LiteLLM discovery'
unset catalog
# Keep this shell as the parent so traps retain config ownership for the full
# native process lifetime. Direct foreground invocation preserves stdin/TTY
# and native session/permission controls; no agent supervisor is introduced.
omp --no-extensions --model "litellm/$model" --smol "litellm/$model" --slow "litellm/$model" "$@"
