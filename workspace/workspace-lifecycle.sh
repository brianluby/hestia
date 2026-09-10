#!/usr/bin/env bash
# 24GJSHY — lifecycle operations for a generated workspace Compose file.
#
# usage: workspace-lifecycle.sh <command> <compose-file> [args]
#
#   validate <file>         compose config + image present + project looks Hestia
#   start <file>            create and start the workspace detached
#   attach <file> [cmd...]  open a shell (or run cmd) in the running workspace
#   stop <file>             stop the workspace; containers and volumes retained
#   remove-runtime <file>   remove the workspace container; volumes/state retained
#   recreate <file>         stop, remove runtime and start again; asserts the
#                           replacement has a different container ID
#   clear-caches <file>     remove ONLY this workspace's linux-caches volume
#                           (identity-verified) and restart with a fresh one
#
# These are thin, explicit wrappers over docker compose — no custom engine.
# Every `up` runs with --pull never: startup never downloads images; validate
# checks the image is present locally and says to build or pull it explicitly.
# The helper never runs `down -v`, prunes, or touches source, and the only
# volume it ever removes is the workspace's own linux-caches volume — after
# verifying both its exact name and that this Compose file declares it.
# Durable state directories and any other volumes are never touched.
# Destructive-adjacent operations (remove-runtime, recreate, clear-caches)
# additionally refuse projects whose Compose name is not a Hestia workspace
# id, so the helper cannot be pointed at an unrelated project by mistake.
#
# Container state is distinguished explicitly: existing (compose ps -aq,
# includes stopped containers) versus running (docker inspect State.Running).
# `docker compose ps -q` alone excludes stopped containers and must not be
# used as an existence query.
set -euo pipefail

usage() {
	echo "usage: workspace-lifecycle.sh <validate|start|attach|stop|remove-runtime|recreate|clear-caches> <compose-file> [cmd...]" >&2
	exit 2
}

file_error() {
	echo "workspace-lifecycle: error: $*" >&2
	exit 3
}

fail() {
	echo "workspace-lifecycle: error: $*" >&2
	exit 1
}

cmd="${1:-}"
file="${2:-}"
[ -n "$cmd" ] || usage
case "$cmd" in
validate | start | stop | remove-runtime | recreate | clear-caches | attach) : ;;
*) usage ;;
esac
[ -n "$file" ] || usage
[ -f "$file" ] || file_error "compose file not found: $file"
shift 2

# Commands other than attach take no further arguments; refusing them beats
# silently ignoring them.
if [ "$cmd" != "attach" ] && [ "$#" -gt 0 ]; then
	echo "workspace-lifecycle: error: $cmd takes no extra arguments (got: $*)" >&2
	exit 2
fi

project="$(sed -n 's/^name: //p' "$file" | head -1)"
[ -n "$project" ] || fail "no Compose project name in $file (generate it with workspace/workspace-compose.sh)"
printf '%s' "$project" | grep -Eq '^hestia-[a-z0-9][a-z0-9-]{0,23}-[0-9a-f]{12}$' ||
	fail "refusing to operate on non-Hestia Compose project name '$project'"

# Distinguish an unreachable daemon from an absent container up front: query
# failures must never be reported as a successful no-op.
docker info >/dev/null 2>&1 ||
	fail "docker daemon unreachable (DOCKER_HOST='${DOCKER_HOST:-default}') — cannot query workspace state"

dc() {
	# -p pins the project validated above: an ambient COMPOSE_PROJECT_NAME or
	# a Compose-loaded .env would otherwise redirect the operation to a
	# different project while the guard validated this one.
	docker compose -p "$project" -f "$file" "$@"
}

# Existing container for the workspace service, including stopped ones. A
# failed query is an error, not an empty result.
existing_cid() {
	local out
	out="$(dc ps -aq workspace 2>&1)" || fail "docker compose query failed: $out"
	printf '%s\n' "$out" | head -1
}

is_running() {
	local id state
	id="$(existing_cid)"
	[ -n "$id" ] || return 1
	state="$(docker inspect -f '{{.State.Running}}' "$id" 2>&1)" ||
		fail "docker inspect failed for $id: $state"
	[ "$state" = "true" ]
}

wait_running() {
	local i
	for i in 1 2 3 4 5 6 7 8 9 10; do
		if is_running; then return 0; fi
		sleep 1
	done
	fail "workspace did not reach running state"
}

up_detached() {
	dc up -d --pull never workspace
}

case "$cmd" in
validate)
	dc config -q || fail "Compose file does not validate: $file"
	image="$(sed -n 's/^    image: //p' "$file" | head -1 | tr -d "'\"")"
	printf '%s' "$image" | grep -Eq '^[A-Za-z0-9./:@_-]+$' ||
		fail "cannot parse a well-formed image reference from $file"
	if [ -n "$image" ]; then
		docker image inspect "$image" >/dev/null 2>&1 ||
			fail "image '$image' is not present locally — build or pull it explicitly; startup never downloads"
	fi
	echo "ok: $file (project $project)"
	;;
start)
	up_detached
	wait_running
	echo "workspace running: $(existing_cid)"
	;;
attach)
	is_running || fail "workspace is not running — start it first"
	if [ "$#" -gt 0 ]; then
		dc exec workspace "$@"
	else
		dc exec workspace bash
	fi
	;;
stop)
	if is_running; then
		dc stop workspace
	fi
	stopped_id="$(existing_cid)"
	echo "workspace stopped; container, volumes and state retained: $stopped_id"
	;;
remove-runtime)
	dc rm -sf workspace >/dev/null
	echo "runtime removed; volumes and state retained"
	;;
recreate)
	before="$(existing_cid)"
	if [ -n "$before" ]; then
		echo "stopping first — finish active work before recreating"
		if is_running; then
			dc stop workspace
		fi
		dc rm -sf workspace >/dev/null
	fi
	up_detached
	wait_running
	after="$(existing_cid)"
	if [ "$before" = "$after" ]; then
		fail "replacement kept the same container ID ($after); refusing to claim recreation"
	fi
	echo "recreated: $before -> $after"
	;;
clear-caches)
	dc config --volumes 2>/dev/null | grep -qx "linux-caches" ||
		fail "this workspace declares no linux-caches volume; refusing to clear anything"
	volume="${project}_linux-caches"
	docker volume inspect "$volume" >/dev/null 2>&1 ||
		fail "cache volume not found: $volume (nothing to clear)"
	if [ -n "$(existing_cid)" ]; then
		echo "stopping workspace first — finish active work before clearing caches"
		if is_running; then
			dc stop workspace
		fi
		dc rm -sf workspace >/dev/null
	fi
	docker volume rm "$volume" >/dev/null ||
		fail "could not remove cache volume $volume"
	up_detached
	wait_running
	echo "cleared $volume; workspace restarted with a fresh cache volume"
	;;
esac
