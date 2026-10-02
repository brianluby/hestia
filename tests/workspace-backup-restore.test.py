#!/usr/bin/env python3
"""B6J27FG/R3N7X5F: quiesced synthetic tar capture and fresh relocated restore.

Requires Docker/Compose, host Git/Python and the existing optional agent image.
No host preferences, sessions or credentials are inspected. KEEP_ARTIFACTS=1
retains this test's private non-secret fixture; its Docker resources are removed.
This is an acceptance fixture, not a general backup or restore tool.
"""
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import stat
import subprocess
import tarfile
import tempfile
import time

HERE = Path(__file__).resolve().parents[1]
IMAGE = os.environ.get("HESTIA_TEST_IMAGE", "hestia-agent:2026-09-10")
ENV = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
ENV.pop("COMPOSE_PROJECT_NAME", None)
PASS = 0
COMMANDS = []
RESOURCES = []
ROOT = None


def run(*args, env=None):
    argv = [str(a) for a in args]
    print("+ " + shlex.join(argv), flush=True)
    result = subprocess.run(argv, env=env or ENV, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    COMMANDS.append({"argv": argv, "exit": result.returncode})
    if result.stdout:
        print(result.stdout.rstrip(), flush=True)
    if result.returncode:
        raise RuntimeError("command exited " + str(result.returncode))
    return result.stdout.strip()


def check(condition, message):
    global PASS
    if not condition:
        raise AssertionError(message)
    PASS += 1
    print("ok - " + message, flush=True)


def inventory(directory):
    result = {}
    for path in sorted(directory.rglob("*")):
        rel = path.relative_to(directory).as_posix()
        mode = stat.S_IMODE(path.lstat().st_mode)
        if path.is_symlink():
            result[rel] = {"type": "symlink", "target": os.readlink(path), "mode": mode}
        elif path.is_file():
            raw = path.read_bytes()
            result[rel] = {"type": "file", "sha256": hashlib.sha256(raw).hexdigest(),
                           "size": len(raw), "mode": mode}
        elif path.is_dir():
            result[rel] = {"type": "directory", "mode": mode}
        else:
            raise RuntimeError("unsupported fixture member: " + rel)
    return result


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def generate(tree, state_root, compose):
    env = dict(ENV, HESTIA_STATE_ROOT=str(state_root))
    run(HERE / "workspace/workspace-compose.sh", "--image", IMAGE,
        "--out", compose, tree, env=env)
    project = next(line[6:] for line in compose.read_text().splitlines()
                   if line.startswith("name: "))
    RESOURCES.append((project, compose))
    return project, state_root / project


def dc(project, compose, *args):
    return run("docker", "compose", "-p", project, "-f", compose, *args)


def git(tree, *args):
    return run("git", "-C", tree, *args)


def snapshot(tree, target):
    run(HERE / "fixtures/bin/fixture-snapshot.sh", "capture", tree, target)


def compare_snapshot(tree, expected, destination, old_root, new_root):
    snapshot(tree, destination)
    for file in expected.iterdir():
        before = file.read_bytes()
        after = (destination / file.name).read_bytes()
        if file.name == "worktrees.porcelain":
            before = before.replace(os.fsencode(old_root), os.fsencode(new_root))
        check(before == after, tree.name + ": " + file.name + " retained")


def build(project, compose):
    dc(project, compose, "exec", "-T", "workspace", "bash", "-c",
       'mise trust >/dev/null && mise exec -- go version && '
       'mise exec -- go build ./... && mise exec -- go test ./...')


def main():
    global ROOT
    for prerequisite in ("docker", "git", "python3"):
        if not shutil.which(prerequisite):
            print("SKIP: missing " + prerequisite)
            return
    # Preflight fails closed: unavailable Docker/image never yields a passing proof.
    docker_server = run("docker", "info", "--format", "{{.ServerVersion}} {{.Architecture}}")
    compose_version = run("docker", "compose", "version")
    image_id = run("docker", "image", "inspect", IMAGE,
                   "--format", "{{.Id}} {{.Architecture}}")
    parent = Path(os.environ.get("HESTIA_TEST_ROOT", str(Path.home() / ".cache/hestia-backup-tests")))
    parent.mkdir(parents=True, exist_ok=True)
    ROOT = Path(tempfile.mkdtemp(prefix="hestia-backup-", dir=parent)).resolve()
    ROOT.chmod(0o700)
    source = ROOT / "source"
    repo = source / "repo"
    linked = source / "worktrees/linked"
    evidence = ROOT / "evidence"
    evidence.mkdir()
    shutil.copytree(HERE / "fixtures/synthetic", repo)
    (repo / ".gitignore").write_text(".cache/\nPRIVATE-NOTES\n")
    (repo / "deleted.txt").write_text("tracked deletion fixture\n")
    (repo / "source-link").symlink_to("greet/greet.go")
    git(repo, "init", "-b", "main")
    git(repo, "config", "user.name", "Hestia Backup Fixture")
    git(repo, "config", "user.email", "hestia-backup@invalid")
    git(repo, "config", "commit.gpgsign", "false")
    git(repo, "add", "-A")
    git(repo, "commit", "-m", "synthetic backup fixture")
    linked.parent.mkdir()
    git(repo, "worktree", "add", "-b", "fixture/linked", linked)
    trees = {"main": repo, "linked": linked}
    original = {}
    for name, tree in trees.items():
        with (tree / "greet/greet.go").open("a") as file:
            file.write("\n// staged " + name + " change\n")
        git(tree, "add", "greet/greet.go")
        with (tree / "cmd/greet/main.go").open("a") as file:
            file.write("\n// unstaged " + name + " change\n")
        (tree / "deleted.txt").unlink()
        (tree / "üntracked.txt").write_bytes(b"raw\r\n" + bytes(range(256)))
        (tree / "PRIVATE-NOTES").write_text("ignored but selected durable source\n")
        (tree / ".cache").mkdir()
        (tree / ".cache/native-output").write_text("excluded disposable native cache\n")
        project, state = generate(tree, ROOT / "old-state", ROOT / (name + ".yml"))
        agent = state / "omp/agent"
        agent.mkdir(exist_ok=True)
        (agent / "config.yml").write_text("theme:\n  dark: serius\n")
        (agent / "synthetic-session.json").write_text(json.dumps({
            "kind": "synthetic; not a native omp session", "workspace": name,
            "messages": ["non-secret fixture-only state"]}) + "\n")
        # Controlled exclusion sentinels; never copied from a real host profile.
        (agent / "agent.db").write_text("synthetic excluded auth/database sentinel\n")
        (state / "omp/natives").mkdir()
        (state / "omp/natives/cache").write_text("excluded extracted cache\n")
        run(HERE / "workspace/workspace-lifecycle.sh", "start", ROOT / (name + ".yml"))
        cid = dc(project, ROOT / (name + ".yml"), "ps", "-q", "workspace")
        build(project, ROOT / (name + ".yml"))
        cache = dc(project, ROOT / (name + ".yml"), "exec", "-T", "workspace",
                   "sh", "-c", "find /hestia/cache -type f | wc -l")
        check(int(cache) > 0, name + ": original build populated disposable cache")
        original[name] = {"project": project, "state": state, "container": cid,
                          "cache_files": int(cache), "canonical": str(tree.resolve()),
                          "identity_record": (state / "identity.record").read_text(),
                          "git_dir": git(tree, "rev-parse", "--path-format=absolute", "--git-dir"),
                          "common_dir": git(tree, "rev-parse", "--path-format=absolute", "--git-common-dir")}
    for name in trees:
        run(HERE / "workspace/workspace-lifecycle.sh", "stop", ROOT / (name + ".yml"))
        check(run("docker", "inspect", "-f", "{{.State.Running}}", original[name]["container"]) == "false",
              name + ": container stopped before capture")
        snapshot(trees[name], evidence / (name + "-before"))
    refs_before = git(repo, "show-ref")
    # Only our known synthetic source and selected preference/session files enter staging.
    stage = ROOT / "staging"
    stage.mkdir()
    for rel in ("repo", "worktrees"):
        shutil.copytree(source / rel, stage / rel, symlinks=True,
                        ignore=shutil.ignore_patterns(".cache"))
    for name in trees:
        selected = stage / "selected-agent" / name / "agent"
        selected.mkdir(parents=True)
        for filename in ("config.yml", "synthetic-session.json"):
            shutil.copy2(original[name]["state"] / "omp/agent" / filename, selected / filename)
    entries = inventory(stage)
    manifest = {"format": "hestia-synthetic-backup-v1", "created_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "classification": "reviewed non-secret synthetic fixture",
                "source_root": str(source), "image": IMAGE, "image_identity": image_id,
                "quiescence": "both containers stopped; no services or background host writers",
                "checkouts": {name: {k: v for k, v in record.items() if k != "state"}
                              for name, record in original.items()},
                "service_data": [], "excluded": ["linux-caches volumes", ".cache", "omp/natives",
                    "agent.db/auth/credentials", "old identity.record", "generated Compose"], "entries": entries}
    manifest_path = ROOT / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    archive = ROOT / "durable.tar.gz"
    with tarfile.open(archive, "w:gz", dereference=False) as tar:
        for rel in entries:
            tar.add(stage / rel, arcname=rel, recursive=False)
    digest = sha(archive)
    (ROOT / "durable.tar.gz.sha256").write_text(digest + "  durable.tar.gz\n")
    check(all(".cache" not in Path(p).parts and "agent.db" not in Path(p).parts
              and "natives" not in Path(p).parts and "identity.record" not in Path(p).parts
              for p in entries), "manifest excludes caches, auth database and stale identities")
    check("repo/.git/index" in entries and "repo/.git/worktrees/linked/index" in entries,
          "archive includes both indexes and complete common/linked Git metadata")
    for name in trees:
        run(HERE / "fixtures/bin/fixture-snapshot.sh", "compare", trees[name], evidence / (name + "-before"))
    original_bytes = {p: v for p, v in inventory(source).items() if ".cache" not in Path(p).parts}
    archived_bytes = {p: v for p, v in entries.items() if Path(p).parts[0] in ("repo", "worktrees")}
    check(original_bytes == archived_bytes, "source and all Git metadata bytes/modes stable across capture")
    # Fresh destination, verified before repair: archive path inventory must match our receipt.
    restored = ROOT / "restored"
    restored.mkdir()
    check(not any(restored.iterdir()), "restore destination starts empty")
    check(sha(archive) == digest, "archive SHA-256 matches the retained receipt")
    with tarfile.open(archive) as tar:
        check({m.name for m in tar.getmembers()} == set(entries), "archive member set exactly matches manifest")
        # Archive is produced solely from this test's synthetic, reviewed staging tree.
        tar.extractall(restored, filter="data")
    # The data filter makes regular files owner-writable; reapply our recorded
    # fixture modes explicitly, without following symlinks, before verification.
    for rel, metadata in entries.items():
        if metadata["type"] != "symlink":
            (restored / rel).chmod(metadata["mode"])
    check(inventory(restored) == entries, "all restored files/modes/symlinks match capture manifest")
    corrupt = restored / "repo/üntracked.txt"
    saved = corrupt.read_bytes()
    corrupt.write_bytes(saved + b"corruption")
    check(inventory(restored) != entries, "manifest detects deliberate raw-byte corruption")
    corrupt.write_bytes(saved)
    check(inventory(restored) == entries, "verification returns clean after controlled corruption is removed")
    # Make the old paths unavailable before supported repair; only this test's tree is moved.
    source.rename(ROOT / "source-offline")
    moved_repo = restored / "repo"
    moved_linked = restored / "worktrees/linked"
    git(moved_repo, "worktree", "repair", moved_linked)
    moved = {"main": moved_repo, "linked": moved_linked}
    check(git(moved_repo, "show-ref") == refs_before, "all branch refs survive relocation")
    check(git(moved_repo, "worktree", "list", "--porcelain").count("worktree ") == 2,
          "repaired Git relationship lists exactly main and linked checkout")
    repaired = inventory(restored)
    changes = {p for p in entries if repaired.get(p) != entries[p]}
    check(set(repaired) == set(entries) and changes == {"worktrees/linked/.git", "repo/.git/worktrees/linked/gitdir"},
          "repair changes only the two expected Git relocation pointers")
    new_records = {}
    for name, tree in moved.items():
        common = git(tree, "rev-parse", "--path-format=absolute", "--git-common-dir")
        check(Path(common).resolve() == moved_repo / ".git", name + ": common Git directory resolves in restored storage")
        metadata = git(tree, "rev-parse", "--path-format=absolute", "--git-dir")
        check(Path(metadata).resolve().is_relative_to(moved_repo / ".git"),
              name + ": checkout-specific Git metadata resolves inside restored common directory")
        compare_snapshot(tree, evidence / (name + "-before"), evidence / (name + "-restored"), source, restored)
        compose = ROOT / ("restored-" + name + ".yml")
        project, state = generate(tree, ROOT / "restored-state", compose)
        check(project != original[name]["project"], name + ": relocated workspace identity regenerated")
        record = (state / "identity.record").read_text()
        check(str(tree) in record and str(source) not in record and record != original[name]["identity_record"],
              name + ": state record explicitly maps to new canonical path")
        old_repo_id = next(line for line in original[name]["identity_record"].splitlines() if line.startswith("repo-group: "))
        new_repo_id = next(line for line in record.splitlines() if line.startswith("repo-group: "))
        check(old_repo_id != new_repo_id, name + ": repository identity relocated")
        shutil.copytree(restored / "selected-agent" / name / "agent", state / "omp/agent")
        check(inventory(state / "omp/agent") == inventory(restored / "selected-agent" / name / "agent"),
              name + ": selected preference and synthetic session payload retained")
        check(not (state / "omp/agent/agent.db").exists() and not (state / "omp/natives").exists(),
              name + ": auth database and extracted caches not restored")
        check(not (tree / ".cache").exists(), name + ": native source cache not restored")
        run(HERE / "workspace/workspace-lifecycle.sh", "start", compose)
        cid = dc(project, compose, "ps", "-q", "workspace")
        check(cid != original[name]["container"], name + ": fresh runtime has different container ID")
        cold = dc(project, compose, "exec", "-T", "workspace", "sh", "-c", "find /hestia/cache -type f | wc -l")
        check(int(cold) == 0, name + ": excluded Linux cache starts cold")
        build(project, compose)
        warm = dc(project, compose, "exec", "-T", "workspace", "sh", "-c", "find /hestia/cache -type f | wc -l")
        check(int(warm) > 0, name + ": real build/tests regenerate cache")
        # Successful staging proves writable relocated metadata; restage identical bytes.
        dc(project, compose, "exec", "-T", "workspace", "git", "add", "greet/greet.go")
        compare_snapshot(tree, evidence / (name + "-before"), evidence / (name + "-after-build"), source, restored)
        check(inventory(state / "omp/agent") == inventory(restored / "selected-agent" / name / "agent"),
              name + ": selected state unchanged after container build/Git operation")
        source_expected = {p: v for p, v in inventory(stage / tree.relative_to(restored)).items()
                           if ".git" not in Path(p).parts}
        source_actual = {p: v for p, v in inventory(tree).items() if ".git" not in Path(p).parts}
        check(source_actual == source_expected, name + ": all selected raw source including ignored notes retained after build")
        new_records[name] = {"project": project, "container": cid, "cache_before": int(cold), "cache_after": int(warm)}
    receipt = {"hestia_head": git(HERE, "rev-parse", "HEAD"), "test_sha256": sha(Path(__file__)),
               "host": run("uname", "-srm"), "git": run("git", "--version"), "python": run("python3", "--version"),
               "docker_server": docker_server, "compose": compose_version, "image_identity": image_id,
               "archive_sha256": digest, "archive_entries": len(entries), "original": manifest["checkouts"],
               "restored": new_records, "passed": PASS, "commands": COMMANDS,
               "limitations": ["synthetic session only; native omp resume not exercised", "no real credentials, reauthentication or encryption", "no service data", "macOS arm64 only"]}
    (evidence / "receipt.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
    print("passed: " + str(PASS) + ", failed: 0", flush=True)
    print("receipt: " + str(evidence / "receipt.json"), flush=True)


if __name__ == "__main__":
    success = False
    try:
        main()
        success = True
    finally:
        cleanup_errors = []
        for project, compose in reversed(RESOURCES):
            for args in (("docker", "compose", "-p", project, "-f", compose, "down", "--remove-orphans"),
                         ("docker", "volume", "rm", project + "_linux-caches")):
                try:
                    run(*args)
                except Exception as error:
                    cleanup_errors.append(str(error))
        if ROOT and success and not cleanup_errors:
            receipt_path = ROOT / "evidence/receipt.json"
            if receipt_path.exists():
                receipt = json.loads(receipt_path.read_text())
                receipt["commands"] = COMMANDS
                receipt["cleanup"] = "all four own Compose projects removed and their four cache volumes deleted; all exit 0"
                receipt_path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
        if ROOT:
            if success and not cleanup_errors and os.environ.get("KEEP_ARTIFACTS") != "1":
                shutil.rmtree(ROOT)
            else:
                print("preserving synthetic artifacts: " + str(ROOT), flush=True)
        if cleanup_errors:
            raise RuntimeError("fixture resource cleanup failed: " + "; ".join(cleanup_errors))
