#!/usr/bin/env bash
# 24GJSHY — lifecycle operations for a generated workspace Compose file.
#
# usage: workspace-lifecycle.sh <command> <compose-file>
#
#   validate <file>        compose config + image present + project looks Hestia
#   start <file>           create and start the workspace detached
#   attach <file> [cmd...] open a shell (or run cmd) in the running workspace
#   stop <file>            stop the workspace; containers and volumes retained
#   remove-runtime <file>  remove the workspace container; volumes/state retained
#   recreate <file>        stop, remove runtime and start again; asserts the
#                          replacement has a different container ID
#
# These are thin, explicit wrappers over docker compose — no custom engine.
# The helper never runs `down -v`, never prunes, never deletes volumes or
# source: routine lifecycle preserves all durable data by construction.
# Destructive-adjacent operations (remove-runtime, recreate) additionally
# refuse projects whose Compose name is not a Hestia workspace id, so the
# helper cannot be pointed at an unrelated project by mistake.
set -euo pipefail

usage() {
	echo "usage: workspace-lifecycle.sh <validate|start|attach|stop|remove-runtime|recreate> <compose-file> [cmd...]" >&2
	exit 2
}

cmd="${1:-}"
file="${2:-}"
[ -n "$cmd" ] && [ -n "$file" ] && [ -f "$file" ] || usage
shift 2 || true

fail() {
	echo "workspace-lifecycle: error: $*" >&2
	exit 1
}

project="$(sed -n 's/^name: //p' "$file" | head -1)"
[ -n "$project" ] || fail "no Compose project name in $file (generate it with workspace/workspace-compose.sh)"
case "$project" in
hestia-*) : ;;
*) fail "refusing to operate on non-Hestia Compose project '$project'" ;;
esac

dc() {
	docker compose -f "$file" "$@"
}

cid() {
	dc ps -q workspace
}

wait_running() {
	local i
	for i in 1 2 3 4 5 6 7 8 9 10; do
		[ -n "$(cid)" ] && [ "$(docker inspect -f '{{.State.Running}}' "$(cid)" 2>/dev/null)" = "true" ] && return 0
		sleep 1
	done
	fail "workspace did not reach running state"
}

case "$cmd" in
validate)
	dc config -q || fail "Compose file does not validate: $file"
	image="$(sed -n 's/^    image: //p' "$file" | head -1 | tr -d "'\"")"
	if [ -n "$image" ]; then
		docker image inspect "$image" >/dev/null 2>&1 ||
			fail "image '$image' is not present locally — build or pull it explicitly; startup never downloads"
	fi
	echo "ok: $file (project $project)"
	;;
start)
	dc up -d workspace
	wait_running
	echo "workspace running: $(cid)"
	;;
attach)
	[ -n "$(cid)" ] || fail "workspace is not running — start it first"
	if [ "$#" -gt 0 ]; then
		dc exec workspace "$@"
	else
		dc exec workspace bash
	fi
	;;
stop)
	dc stop workspace
	echo "workspace stopped; container, volumes and state retained: $(cid)"
	;;
remove-runtime)
	dc rm -sf workspace >/dev/null
	echo "runtime removed; volumes and state retained"
	;;
recreate)
	before="$(cid)"
	if [ -n "$before" ]; then
		echo "stopping first — finish active work before recreating"
		dc stop workspace
		dc rm -sf workspace >/dev/null
	fi
	dc up -d workspace
	wait_running
	after="$(cid)"
	if [ -n "$before" ] && [ "$before" = "$after" ]; then
		fail "replacement kept the same container ID ($after); refusing to claim recreation"
	fi
	echo "recreated: $before -> $after"
	;;
*)
	usage
	;;
esac
