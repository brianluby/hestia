#!/usr/bin/env bash
# CF62H3E / 3B36AE6 / M9FMY5V — concurrent fixtures and recreation.
# worktree is a terminal/Git partial proof, not authenticated agent acceptance.
# usage: workspace-concurrency.test.sh [isolation|recreate|worktree]
# Uses the canonical fixture image and generated Compose files. No credentials.
# KEEP_ARTIFACTS=1 preserves synthetic source/state and receipts; Docker resources
# are always removed. Missing runtime/image is SKIP, not acceptance.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image="${HESTIA_TEST_IMAGE:-hestia-fixture-tools:2026-09-09}"
mode="${1:-isolation}"
[ "$#" -le 1 ] && { [ "$mode" = isolation ] || [ "$mode" = recreate ] || [ "$mode" = worktree ]; } || { echo "usage: $0 [isolation|recreate|worktree]" >&2; exit 2; }
if [ "$mode" = worktree ]; then image="${HESTIA_TEST_IMAGE:-hestia-agent:2026-09-10}"; fi
for prerequisite in docker git python3; do
	command -v "$prerequisite" >/dev/null || { echo "SKIP: $prerequisite unavailable"; exit 0; }
done
docker info >/dev/null 2>&1 || { echo "SKIP: Docker daemon unavailable"; exit 0; }
docker compose version >/dev/null 2>&1 || { echo "SKIP: Compose unavailable"; exit 0; }
docker image inspect "$image" >/dev/null 2>&1 || { echo "SKIP: build $image explicitly"; exit 0; }

tmp_base="${HESTIA_TEST_TMP_BASE:-$HOME/.cache/hestia-concurrency-tests}"
mkdir -p "$tmp_base"
root="$(mktemp -d "$tmp_base/hestia-concurrency-XXXXXXXX")"
export HESTIA_STATE_ROOT="$root/state"
pass=0
fail=0
# Record a successful check and increment the pass count.
ok() { echo "ok   - $1"; pass=$((pass + 1)); }
# Record a failed check while allowing independent checks to continue.
bad() { echo "FAIL - $1"; fail=$((fail + 1)); }
# Run a labeled assertion and record its result.
check() {
	local label="$1"
	shift
	if "$@"; then ok "$label"; else bad "$label"; fi
}
# Run Compose against only the selected fixture workspace.
dc() {
	local slot="$1"
	shift
	docker compose -p "$(sed -n 's/^name: //p' "$root/$slot.yml")" -f "$root/$slot.yml" "$@"
}
# Snapshot the index through a receipt-local copy: git write-tree may replace
# the live index even during observation. Avoid host/container metadata writers
# racing through a bind mount; status itself also runs with optional locks off.
snapshot() {
	local operation="$1" slot="$2"
	local repo="$root/$slot/repo" index
	index="$(git -C "$repo" rev-parse --path-format=absolute --git-path index)"
	cp "$index" "$root/$slot.observation-index"
	GIT_INDEX_FILE="$root/$slot.observation-index" GIT_OPTIONAL_LOCKS=0 \
		"$here/fixtures/bin/fixture-snapshot.sh" "$operation" "$repo" "$root/$slot.snapshot"
}
# Remove only this run's containers, networks and disposable cache volumes.
cleanup_resources() {
	local slot id
	for slot in a b; do
		[ -f "$root/$slot.yml" ] || continue
		id="$(sed -n 's/^name: //p' "$root/$slot.yml")"
		docker compose -p "$id" -f "$root/$slot.yml" down --remove-orphans >/dev/null 2>&1 || true
		docker volume rm "${id}_linux-caches" >/dev/null 2>&1 || true
	done
}
# Preserve diagnostic receipts whenever the run fails or retention is requested.
cleanup() {
	local status=$?
	if [ -n "${neighbor_pid:-}" ]; then
		dc b exec -T workspace touch /tmp/neighbor-finish >/dev/null 2>&1 || true
		wait "$neighbor_pid" >/dev/null 2>&1 || true
	fi
	cleanup_resources
	if [ "$status" -ne 0 ] || [ "$fail" -gt 0 ] || [ "${KEEP_ARTIFACTS:-0}" = 1 ]; then
		echo "receipts and synthetic durable fixtures: $root"
	else
		rm -rf "$root"
	fi
}
trap cleanup EXIT

{
	echo "suite: CF62H3E / 3B36AE6 / M9FMY5V $mode"
	shasum -a 256 "$here/tests/workspace-concurrency.test.sh"
	echo "tested-head: $(git -C "$here" rev-parse HEAD)"
	echo "host: $(uname -srm)"
	sw_vers 2>/dev/null || true
	docker version --format 'client: {{.Client.Version}} server: {{.Server.Version}}'
	docker compose version
	docker image inspect --format 'image: {{.Id}} architecture: {{.Architecture}}' "$image"
} >"$root/environment.txt"
cat "$root/environment.txt"

# These fixtures are synthetic and need only already-installed image tools.
# Create independent repos, or one main checkout plus a linked worktree.
# Host mise/toolchains are never touched.
if [ "$mode" = worktree ]; then
	mkdir -p "$root/a/repo" "$root/b"
	cp -R "$here/fixtures/synthetic/." "$root/a/repo/"
	git -C "$root/a/repo" init -q -b proof/a
	git -C "$root/a/repo" -c user.name="Hestia Fixture" -c user.email=hestia-fixture@invalid -c commit.gpgsign=false add -A
	git -C "$root/a/repo" -c user.name="Hestia Fixture" -c user.email=hestia-fixture@invalid -c commit.gpgsign=false commit -qm "synthetic linked-worktree fixture"
	git -C "$root/a/repo" worktree add -q -b proof/b "$root/b/repo"
	cp "$root/b/repo/.git" "$root/b.git-link.before"
fi
for slot in a b; do
	repo="$root/$slot/repo"
	mkdir -p "$repo"
	if [ ! -e "$repo/.git" ]; then
		cp -R "$here/fixtures/synthetic/." "$repo/"
		git -C "$repo" init -q -b "proof/$slot"
		git -C "$repo" -c user.name="Hestia Fixture" -c user.email=hestia-fixture@invalid -c commit.gpgsign=false add -A
		git -C "$repo" -c user.name="Hestia Fixture" -c user.email=hestia-fixture@invalid -c commit.gpgsign=false commit -qm "synthetic fixture $slot"
	fi
	"$here/workspace/workspace-compose.sh" --image "$image" --out "$root/$slot.yml" "$repo"
	"$here/identity/workspace-id.sh" "$repo" >"$root/$slot.identity"
	"$here/workspace/workspace-lifecycle.sh" start "$root/$slot.yml" >"$root/$slot.start.log" 2>&1 || {
		start_status=$?
		cat "$root/$slot.start.log" >&2
		exit "$start_status"
	}
	dc "$slot" ps -q workspace >"$root/$slot.cid"
	docker inspect "$(cat "$root/$slot.cid")" >"$root/$slot.inspect.json"
done
repo_a="$root/a/repo"
repo_b="$root/b/repo"
id_a="$(sed -n 's/^name: //p' "$root/a.yml")"
id_b="$(sed -n 's/^name: //p' "$root/b.yml")"
state_a="$HESTIA_STATE_ROOT/$id_a"
state_b="$HESTIA_STATE_ROOT/$id_b"

check "matching repository basenames" test "$(basename "$repo_a")" = "$(basename "$repo_b")"
check "workspace identities are distinct" test "$id_a" != "$id_b"
if [ "$mode" = worktree ]; then
	check "worktrees share repository-group identity" test "$(sed -n 's/^repo-group: //p' "$root/a.identity")" = "$(sed -n 's/^repo-group: //p' "$root/b.identity")"
else
	check "repository identities are distinct" test "$(sed -n 's/^repo-group: //p' "$root/a.identity")" != "$(sed -n 's/^repo-group: //p' "$root/b.identity")"
fi
check "containers are distinct and both running" bash -c '[ "$1" != "$2" ] && [ "$(docker inspect -f "{{.State.Running}}" "$1")" = true ] && [ "$(docker inspect -f "{{.State.Running}}" "$2")" = true ]' _ "$(cat "$root/a.cid")" "$(cat "$root/b.cid")"

# Both terminal workloads launch before waiting; each uses its own index.
build_in_workspace() {
	local slot="$1" state
	state="$HESTIA_STATE_ROOT/$(sed -n 's/^name: //p' "$root/$slot.yml")"
	dc "$slot" exec -T workspace bash -c '
		set -euo pipefail
		mise trust "$PWD" >/dev/null
		printf "\n// WorkspaceLabel identifies this checkout fixture.\nfunc WorkspaceLabel() string { return \"%s\" }\n" "$1" >>greet/greet.go
		printf "\nfunc TestWorkspaceLabel(t *testing.T) { if WorkspaceLabel() != \"%s\" { t.Fatal(WorkspaceLabel()) } }\n" "$1" >>greet/greet_test.go
		go fmt ./...
		git add greet/greet.go
		printf "\n// unstaged concurrency work: %s\n" "$1" >>cmd/greet/main.go
		printf "untracked work: %s\n" "$1" >NOTES.md
		printf "source: %s\n" "$1" >"$1-only.txt"
		printf "durable: %s\n" "$1" >"$2/marker.txt"
		printf "selected state: %s\n" "$1" >/home/dev/.omp/marker.txt
		printf "cache: %s\n" "$1" >/hestia/cache/marker.txt
		go build ./...
		go test -count=1 ./...
		git status --porcelain=v2 --branch
	' _ "$slot" "$state" >"$root/$slot.build.log" 2>&1
}
build_in_workspace a & build_pid_a=$!
build_in_workspace b & build_pid_b=$!
for slot in a b; do
	build_pid="$build_pid_a"
	[ "$slot" != b ] || build_pid="$build_pid_b"
	if wait "$build_pid"; then ok "$slot concurrent edits, staging, build and uncached tests pass"
	else cat "$root/$slot.build.log"; bad "$slot build/test or edit failed"
	fi
done
for slot in a b; do
	if [ "$mode" = worktree ]; then
		dc "$slot" exec -T workspace bash -c 'omp --version && omp config get disabledProviders' >"$root/$slot.native-cli.log" 2>&1 && ok "$slot native omp CLI config initializes without inference" || bad "$slot native CLI failed"
		check "$slot native omp database is scoped to its state" test -f "$HESTIA_STATE_ROOT/$(sed -n 's/^name: //p' "$root/$slot.yml")/omp/agent/agent.db"
		dc "$slot" exec -T workspace git rev-parse --path-format=absolute --git-common-dir >"$root/$slot.common-git"
		check "$slot container resolves expected common Git directory" grep -qx "$root/a/repo/.git" "$root/$slot.common-git"
		dc "$slot" exec -T workspace git diff --cached >"$root/$slot.staged.diff"
		branch="$(dc "$slot" exec -T workspace git symbolic-ref --short HEAD)"
		check "$slot intended branch retained" test "$branch" = "proof/$slot"
		check "$slot staged diff includes real checkout edit" grep -q 'WorkspaceLabel' "$root/$slot.staged.diff"
	fi
	check "$slot host sees container source edit" test -f "$root/$slot/repo/$slot-only.txt"
	snapshot capture "$slot" >/dev/null
	dc "$slot" exec -T workspace env GIT_OPTIONAL_LOCKS=0 git status --porcelain=v2 --branch >"$root/$slot.container-status"
	check "$slot host/container Git status agrees" cmp "$root/$slot.snapshot/status.porcelain-v2" "$root/$slot.container-status"
done
check "A cannot read B's source or state" dc a exec -T workspace bash -c 'test ! -e "$1/b-only.txt" && test ! -e "$2/marker.txt" && test ! -e /var/run/docker.sock' _ "$repo_b" "$state_b"
check "B cannot read A's source or state" dc b exec -T workspace bash -c 'test ! -e "$1/a-only.txt" && test ! -e "$2/marker.txt" && test ! -e /var/run/docker.sock' _ "$repo_a" "$state_a"
for slot in a b; do
	check "$slot selected agent state is separate" dc "$slot" exec -T workspace grep -qx "selected state: $slot" /home/dev/.omp/marker.txt
	check "$slot Linux cache is separate" dc "$slot" exec -T workspace grep -qx "cache: $slot" /hestia/cache/marker.txt
done

# Assert actual mounts/resources, not only generated YAML. Current workspaces
# declare no service ports. Distinct default networks cover Compose resources.
if python3 - "$root" "$id_a" "$id_b" "$mode" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
for slot, ident in zip(("a", "b"), sys.argv[2:4]):
    item = json.loads((root / f"{slot}.inspect.json").read_text())[0]
    repo = str(root / slot / "repo")
    state = str(root / "state" / ident)
    binds = {(m["Source"], m["Destination"]) for m in item["Mounts"] if m["Type"] == "bind"}
    expected = {(repo, repo), (state, state), (state + "/omp", "/home/dev/.omp")}
    if sys.argv[4] == "worktree" and slot == "b":
        common = str(root / "a" / "repo" / ".git")
        expected.add((common, common))
    assert binds == expected, (slot, binds, expected)
    volumes = {(m["Name"], m["Destination"]) for m in item["Mounts"] if m["Type"] == "volume"}
    assert volumes == {(ident + "_linux-caches", "/hestia/cache")}, volumes
    assert set(item["NetworkSettings"]["Networks"]) == {ident + "_default"}
    assert not item["HostConfig"]["PortBindings"], "unexpected published ports"
    assert not item["Config"].get("ExposedPorts"), "unexpected declared service ports"
    print(slot, "mounts:", sorted(binds), "cache:", sorted(volumes),
          "networks:", sorted(item["NetworkSettings"]["Networks"]), "ports: none")
PY
then ok "effective scoped mounts, cache volumes, networks and no declared ports verified"
else bad "effective resource scope differs"
fi
for slot in a b; do
	check "$slot durable snapshot unchanged after isolation probes" snapshot compare "$slot"
done


if [ "$mode" = recreate ] || [ "$mode" = worktree ]; then
	echo "== recreate A while B completes useful build/test work =="
	for slot in a b; do
		state="$HESTIA_STATE_ROOT/$(sed -n 's/^name: //p' "$root/$slot.yml")"
		(cd "$state" && find . -type f -exec shasum -a 256 {} + | sort) >"$root/$slot.state.before"
		docker volume inspect --format '{{.CreatedAt}} {{.Mountpoint}}' "$(sed -n 's/^name: //p' "$root/$slot.yml")_linux-caches" >"$root/$slot.cache.before"
	done
	# The control/progress files are ephemeral in B; durable source/state
	# receives no observer writes. Every progress event follows a real build
	# and uncached Go test. The loop is bounded even if the host fails.
	dc b exec -T workspace bash -c '
		set -euo pipefail
		for iteration in $(seq 1 120); do
			go build ./...
			go test -count=1 ./...
			printf "%s build-test-success %s\n" "$(date -u +%s)" "$iteration" >>/tmp/neighbor-progress
			[ ! -e /tmp/neighbor-finish ] || break
		done
	' >"$root/b.concurrent-builds.log" 2>&1 &
	neighbor_pid=$!
	ready=0
	for attempt in 1 2 3 4 5 6 7 8 9 10; do
		if dc b exec -T workspace test -s /tmp/neighbor-progress; then ready=1; break; fi
		sleep 1
	done
	check "neighbor useful workload started" test "$ready" = 1
	if [ "$ready" -eq 1 ]; then
		before_progress="$(dc b exec -T workspace sh -c 'wc -l </tmp/neighbor-progress')" || before_progress=""
		date -u +%s >"$root/recreate.started"
		if "$here/workspace/workspace-lifecycle.sh" recreate "$root/a.yml" >"$root/a.recreate.log" 2>&1; then
			ok "A recreation completes during B workload"
		else
			cat "$root/a.recreate.log"
			bad "A recreation failed"
		fi
		date -u +%s >"$root/recreate.finished"
		after_a="$(dc a ps -q workspace)"
		after_b="$(dc b ps -q workspace)"
		check "recreated A container identity changed" test "$after_a" != "$(cat "$root/a.cid")"
		check "neighbor B container identity unchanged" test "$after_b" = "$(cat "$root/b.cid")"
		check "neighbor workload still active after A recreation" kill -0 "$neighbor_pid"
		after_progress="$(dc b exec -T workspace sh -c 'wc -l </tmp/neighbor-progress')" || after_progress=""
		check "neighbor completed build/tests within A recreation interval" test "$after_progress" -gt "$before_progress"
		printf "success events before=%s after=%s\n" "$before_progress" "$after_progress" >"$root/neighbor-overlap.txt"
		dc b exec -T workspace touch /tmp/neighbor-finish
		if wait "$neighbor_pid"; then ok "neighbor concurrent build/test loop exits successfully"
		else bad "neighbor concurrent build/test loop failed"
		fi
		dc b exec -T workspace cat /tmp/neighbor-progress >"$root/b.concurrent-progress"
		neighbor_pid=""
		check "recreated A builds/tests successfully" dc a exec -T workspace bash -c 'mise trust "$PWD" >/dev/null && go build ./... && go test -count=1 ./...'
		for slot in a b; do
			state="$HESTIA_STATE_ROOT/$(sed -n 's/^name: //p' "$root/$slot.yml")"
			(cd "$state" && find . -type f -exec shasum -a 256 {} + | sort) >"$root/$slot.state.after"
			check "$slot all selected durable state bytes unchanged" cmp "$root/$slot.state.before" "$root/$slot.state.after"
			check "$slot source/index/HEAD/branch/untracked snapshot unchanged" snapshot compare "$slot"
			docker volume inspect --format '{{.CreatedAt}} {{.Mountpoint}}' "$(sed -n 's/^name: //p' "$root/$slot.yml")_linux-caches" >"$root/$slot.cache.after"
			check "$slot cache volume retains identity" cmp "$root/$slot.cache.before" "$root/$slot.cache.after"
			dc "$slot" exec -T workspace env GIT_OPTIONAL_LOCKS=0 git status --porcelain=v2 --branch >"$root/$slot.final-status"
			check "$slot final host/container Git status agrees" cmp "$root/$slot.snapshot/status.porcelain-v2" "$root/$slot.final-status"
			docker inspect "$(dc "$slot" ps -q workspace)" >"$root/$slot.after.inspect.json"
		done
		check "B network identity retained" bash -c 'test "$(docker inspect -f "{{range .NetworkSettings.Networks}}{{.NetworkID}}{{end}}" "$1")" = "$2"' _ "$after_b" "$(python3 -c 'import json,sys; print(next(iter(json.load(open(sys.argv[1]))[0]["NetworkSettings"]["Networks"].values()))["NetworkID"])' "$root/b.inspect.json")"
	fi
fi

if [ "$mode" = worktree ]; then
	check "linked-worktree gitdir pointer unchanged by workloads/recreation" cmp "$root/b.git-link.before" "$root/b/repo/.git"
	for slot in a b; do
		branch="$(dc "$slot" exec -T workspace git symbolic-ref --short HEAD)"
		check "$slot final intended branch unchanged" test "$branch" = "proof/$slot"
		dc "$slot" exec -T workspace git rev-parse --path-format=absolute --git-common-dir >"$root/$slot.final-common-git"
		check "$slot final common metadata still resolves" cmp "$root/$slot.common-git" "$root/$slot.final-common-git"
		dc "$slot" exec -T workspace git diff --cached >"$root/$slot.final-staged.diff"
		check "$slot final staged diff retained" cmp "$root/$slot.staged.diff" "$root/$slot.final-staged.diff"
	done
	echo "NOT RUN: authenticated terminal-agent inference and native session resume (M9FMY5V remains partial)"
fi
cleanup_resources
for slot in a b; do
	id="$(sed -n 's/^name: //p' "$root/$slot.yml")"
	check "$slot test-owned runtime removed" bash -c 'test -z "$(docker compose -p "$1" -f "$2" ps -aq)" && ! docker volume inspect "${1}_linux-caches" >/dev/null 2>&1 && ! docker network inspect "${1}_default" >/dev/null 2>&1' _ "$id" "$root/$slot.yml"
done
printf "passed: %s, failed: %s\n" "$pass" "$fail" | tee "$root/result.txt"
[ "$fail" -eq 0 ]
