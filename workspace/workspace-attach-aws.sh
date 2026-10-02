#!/usr/bin/env bash
# AWCEX5Z — explicit session-only AWS handoff; no secret files or Compose env.
# Disable tracing before resolving any credentials, including bash -x callers.
set +x
set -euo pipefail

usage() {
	echo 'usage: workspace-attach-aws.sh <--env|--profile NAME> [--region REGION] [--no-tty] <compose-file> [command...]' >&2
	exit 2
}
fail() { echo "workspace-attach-aws: $*" >&2; exit 1; }
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mode=''
profile=''
region=''
tty_args=()
while [ "$#" -gt 0 ]; do
	case "$1" in
	--env) [ -z "$mode" ] || usage; mode=env; shift ;;
	--profile) [ -z "$mode" ] && [ "$#" -ge 2 ] || usage; mode=profile; profile="$2"; shift 2 ;;
	--region) [ "$#" -ge 2 ] || usage; region="$2"; shift 2 ;;
	--no-tty) tty_args=(-T); shift ;;
	-*) usage ;;
	*) break ;;
	esac
done
[ -n "$mode" ] && [ "$#" -ge 1 ] || usage
file="$1"; shift
[ "$#" -gt 0 ] || set -- bash
# Reuse existing read-only lifecycle preflight before asking for credentials.
"$here/workspace-lifecycle.sh" validate "$file" >/dev/null
project="$(sed -n 's/^name: //p' "$file" | head -1)"
if [ "$mode" = profile ]; then
	command -v aws >/dev/null || fail 'host AWS CLI v2 required for --profile; use --env with an already scoped session instead'
	command -v jq >/dev/null || fail 'host jq required for --profile'
	# Capture supported JSON, never eval shell exports or print provider errors.
	credentials="$(AWS_CLI_AUTO_PROMPT=off AWS_PAGER='' aws configure export-credentials --profile "$profile" --format process 2>/dev/null)" ||
		fail 'could not export host profile credentials; refresh/login on the host and retry'
	printf '%s' "$credentials" | jq -e '
		.Version == 1 and
		(.AccessKeyId | type == "string" and length > 0) and
		(.SecretAccessKey | type == "string" and length > 0) and
		(.SessionToken | type == "string" and length > 0)' >/dev/null 2>&1 ||
		fail 'profile must export temporary access-key credentials with a session token'
	AWS_ACCESS_KEY_ID="$(printf '%s' "$credentials" | jq -r .AccessKeyId)"
	AWS_SECRET_ACCESS_KEY="$(printf '%s' "$credentials" | jq -r .SecretAccessKey)"
	AWS_SESSION_TOKEN="$(printf '%s' "$credentials" | jq -r .SessionToken)"
	unset credentials
	[ -n "$region" ] || region="$(AWS_CLI_AUTO_PROMPT=off AWS_PAGER='' aws configure get region --profile "$profile" 2>/dev/null)" || true
else
	[ -n "$region" ] || region="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
fi
[ -n "${AWS_ACCESS_KEY_ID:-}" ] && [ -n "${AWS_SECRET_ACCESS_KEY:-}" ] && [ -n "${AWS_SESSION_TOKEN:-}" ] ||
	fail 'temporary AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY and AWS_SESSION_TOKEN are required; refresh/export on the host and retry'
[ -n "$region" ] || fail 'AWS region required: pass --region or configure/export it on the host'
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
export AWS_REGION="$region" AWS_DEFAULT_REGION="$region"
# Compose reads values from its environment with bare -e NAME (verified in the
# runtime suite). Values never appear in argv or the generated service config.
# Bash 3.2 + nounset cannot expand an empty optional array: append conditionally.
exec_args=(exec)
if [ "${#tty_args[@]}" -gt 0 ]; then exec_args+=("${tty_args[@]}"); fi
exec_args+=(-e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN -e AWS_REGION -e AWS_DEFAULT_REGION workspace)
exec docker compose -p "$project" -f "$file" "${exec_args[@]}" "$@"
