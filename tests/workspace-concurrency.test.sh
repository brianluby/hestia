#!/usr/bin/env bash
# CF62H3E — two concurrent repositories with matching basenames.
# Uses the canonical fixture image and generated Compose files. No credentials.
# KEEP_ARTIFACTS=1 preserves synthetic source/state and receipts; Docker resources
# are always removed. Missing runtime/image is SKIP, not acceptance.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image="${HESTIA_TEST_IMAGE:-hestia-fixture-tools:2026-09-09}"
for prerequisite in docker git; do
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
ok() { echo "ok   - $1"; pass=$((pass + 1)); }
bad() { echo "FAIL - $1"; fail=$((fail + 1)); }
check() {
	local label="$1"
	shift
	if "$@"; then ok "$label"; else bad "$label"; fi
}
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
cleanup_resources() {
	local slot id
	for slot in a b; do
		[ -f "$root/$slot.yml" ] || continue
		id="$(sed -n 's/^name: //p' "$root/$slot.yml")"
		docker compose -p "$id" -f "$root/$slot.yml" down --remove-orphans >/dev/null 2>&1 || true
		docker volume rm "${id}_linux-caches" >/dev/null 2>&1 || true
	done
}
cleanup() {
	cleanup_resources
	if [ "$fail" -gt 0 ] || [ "${KEEP_ARTIFACTS:-0}" = 1 ]; then
		echo "receipts and synthetic durable fixtures: $root"
	else
		rm -rf "$root"
	fi
}
trap cleanup EXIT

{
	echo "suite: CF62H3E concurrent independent repositories"
	echo "tested-head: $(git -C "$here" rev-parse HEAD)"
	echo "host: $(uname -srm)"
	sw_vers 2>/dev/null || true
	docker version --format 'client: {{.Client.Version}} server: {{.Server.Version}}'
	docker compose version
	docker image inspect --format 'image: {{.Id}} architecture: {{.Architecture}}' "$image"
} >"$root/environment.txt"
cat "$root/environment.txt"

# These fixtures are synthetic and need only already-installed image tools.
# Create two independent Git repositories without touching host mise/toolchain.
for slot in a b; do
	repo="$root/$slot/repo"
	mkdir -p "$repo"
	cp -R "$here/fixtures/synthetic/." "$repo/"
	git -C "$repo" init -q -b "proof/$slot"
	git -C "$repo" -c user.name="Hestia Fixture" -c user.email=hestia-fixture@invalid -c commit.gpgsign=false add -A
	git -C "$repo" -c user.name="Hestia Fixture" -c user.email=hestia-fixture@invalid -c commit.gpgsign=false commit -qm "synthetic fixture $slot"
	"$here/workspace/workspace-compose.sh" --image "$image" --out "$root/$slot.yml" "$repo"
	"$here/identity/workspace-id.sh" "$repo" >"$root/$slot.identity"
	"$here/workspace/workspace-lifecycle.sh" start "$root/$slot.yml" >"$root/$slot.start.log" 2>&1
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
check "repository identities are distinct" test "$(sed -n 's/^repo-group: //p' "$root/a.identity")" != "$(sed -n 's/^repo-group: //p' "$root/b.identity")"
check "containers are distinct and both running" bash -c '[ "$1" != "$2" ] && [ "$(docker inspect -f "{{.State.Running}}" "$1")" = true ] && [ "$(docker inspect -f "{{.State.Running}}" "$2")" = true ]' _ "$(cat "$root/a.cid")" "$(cat "$root/b.cid")"

# Real reviewable edits, staging, and durable/cache writes from each workspace.
for slot in a b; do
	state="$HESTIA_STATE_ROOT/$(sed -n 's/^name: //p' "$root/$slot.yml")"
	if dc "$slot" exec -T workspace bash -c '
		set -euo pipefail
		mise trust "$PWD" >/dev/null
		printf "\n// WorkspaceLabel identifies this independent fixture.\nfunc WorkspaceLabel() string { return \"%s\" }\n" "$1" >>greet/greet.go
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
	' _ "$slot" "$state" >"$root/$slot.build.log" 2>&1; then
		ok "$slot container edits, staging, build and uncached tests pass"
	else
		cat "$root/$slot.build.log"
		bad "$slot build/test or edit failed"
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
if python3 - "$root" "$id_a" "$id_b" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
for slot, ident in zip(("a", "b"), sys.argv[2:]):
    item = json.loads((root / f"{slot}.inspect.json").read_text())[0]
    repo = str(root / slot / "repo")
    state = str(root / "state" / ident)
    binds = {(m["Source"], m["Destination"]) for m in item["Mounts"] if m["Type"] == "bind"}
    expected = {(repo, repo), (state, state), (state + "/omp", "/home/dev/.omp")}
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

cleanup_resources
for slot in a b; do
	id="$(sed -n 's/^name: //p' "$root/$slot.yml")"
	check "$slot test-owned runtime removed" bash -c 'test -z "$(docker compose -p "$1" -f "$2" ps -aq)" && ! docker volume inspect "${1}_linux-caches" >/dev/null 2>&1 && ! docker network inspect "${1}_default" >/dev/null 2>&1' _ "$id" "$root/$slot.yml"
done
printf "passed: %s, failed: %s\n" "$pass" "$fail" | tee "$root/result.txt"
[ "$fail" -eq 0 ]
