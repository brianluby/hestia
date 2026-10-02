#!/usr/bin/env bash
# AWCEX5Z — explicit session-only LiteLLM handoff to native omp.
# Disable tracing before accessing credentials, including bash -x callers.
set +x
set -euo pipefail

usage() {
	echo 'usage: workspace-attach-litellm.sh --endpoint URL --model ID [--no-tty] <compose-file> [omp-args...]' >&2
	exit 2
}
fail() { echo "workspace-attach-litellm: $*" >&2; exit 1; }
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
endpoint=''
model=''
no_tty=0
while [ "$#" -gt 0 ]; do
	case "$1" in
	--endpoint) [ -z "$endpoint" ] && [ "$#" -ge 2 ] || usage; endpoint="$2"; shift 2 ;;
	--model) [ -z "$model" ] && [ "$#" -ge 2 ] || usage; model="$2"; shift 2 ;;
	--no-tty) no_tty=1; shift ;;
	-*) usage ;;
	*) break ;;
	esac
done
[ -n "$endpoint" ] && [ -n "$model" ] && [ "$#" -ge 1 ] || usage
file="$1"; shift
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
[ -n "${LITELLM_API_KEY:-}" ] || fail 'export a scoped nonempty LITELLM_API_KEY on the host and retry'
# Existing preflight verifies identity, Compose and the local image.
"$here/workspace-lifecycle.sh" validate "$file" >/dev/null
project="$(sed -n 's/^name: //p' "$file" | head -1)"
docker compose -p "$project" -f "$file" exec -T workspace test -r /opt/hestia/omp/litellm.yml >/dev/null 2>&1 ||
	fail 'running workspace with LiteLLM overlay required; build the current agent target explicitly and recreate'
export LITELLM_API_KEY
export LITELLM_BASE_URL="$endpoint" PI_CONFIG_FILES=/opt/hestia/omp/litellm.yml
# Bare -e names keep endpoint/key values out of argv and generated Compose.
# Bash 3.2 + nounset needs a nonempty array; append optional -T conditionally.
exec_args=(exec)
[ "$no_tty" -eq 0 ] || exec_args+=(-T)
exec_args+=(-e PI_CONFIG_FILES -e LITELLM_BASE_URL -e LITELLM_API_KEY workspace)
exec docker compose -p "$project" -f "$file" "${exec_args[@]}" \
	omp --provider litellm --model "$model" --smol "litellm/$model" --slow "litellm/$model" "$@"
