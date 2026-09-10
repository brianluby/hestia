# Full repository review — 2026-09-09, commit a868bfa

Verdict: request changes; five actionable findings, all reproduced by the
reviewer with disposable resources. No tracked files, GitHub comments or
tracker state were changed by the review.

**Disposition:** all five findings accepted and ticketed (`from-review`):

| # | Sev | Finding | Ticket |
| --- | --- | --- | --- |
| 1 | P1 | Ambient `COMPOSE_PROJECT_NAME`/`.env` can redirect lifecycle operations to a foreign project | `AG2HKSM` |
| 2 | P2 | Snapshot hashes are filter-converted and hash failures are masked, so changed bytes can compare clean | `G2ADH4M` |
| 3 | P2 | Saved Compose files skip identity revalidation, reusing mismatched state | `Q6ZE1W0` |
| 4 | P2 | Docker query failures are treated as absent containers; `stop` reports success with no daemon | `GGGET9D` |
| 5 | P2 | Relative `HESTIA_STATE_ROOT` produces relative binds; start fails after creating resources | `QAPTN0Y` |

Reviewer's validation context: PRs #1–#10 merged; remote main matches the
reviewed HEAD; Docker context Colima, server 29.5.2 linux/arm64, Compose
5.5.1; suites 19/29/18/12 passing; no CI workflow tracked in-repo; SLSA chain
not freshly rerun (image identity matched the last recorded verification).

## Findings (as reported)

### 1. P1 — Pin the validated project on every Compose invocation

Location: `workspace/workspace-lifecycle.sh:66–73` (also affects cache clearing
at 151–168). The guard reads `name:` from the generated file, but `dc()`
invokes Compose without `-p`. `COMPOSE_PROJECT_NAME` takes precedence over the
file's name, so the project validated by the guard is not necessarily the
project receiving the operation. An inherited shell variable, or a
Compose-loaded `.env` setting, can redirect stop/remove/recreate to an
unrelated project with a `workspace` service. Cache clearing additionally
mixes the file-derived volume name with the environment-selected container
project. Reproduction used only disposable resources: create a separate
project named `review-foreign-23m5br62`, set `COMPOSE_PROJECT_NAME` to that
name, and invoke `remove-runtime` with the unmodified generated Hestia Compose
file. The helper exited 0 and the unrelated project's container no longer
existed. Fix: invoke `docker compose -p "$project" -f "$file" ...`
consistently, and add a regression proving a foreign project's container and
volumes survive an ambient override.
Reference: https://docs.docker.com/compose/how-tos/project-name/

### 2. P2 — Snapshot raw bytes and fail when hashing fails

Location: `fixtures/bin/fixture-snapshot.sh:52–55`. `git ls-files` produces
quoted/escaped names by default for non-ASCII and certain other characters,
while the loop treats each line as a literal pathname. `hash-object` then
fails, but its failure is masked inside a successful `printf`. Capture and
compare can both record an empty hash and report unchanged state after source
changes. Separately, `hash-object` applies Git clean/EOL conversion, so it
does not necessarily hash the actual working-tree bytes promised by this
helper. Reproduction: create an untracked `üntracked.txt`, capture, change its
contents, and compare. Both operations returned 0; compare printed `matches`
despite a fatal hash error on stderr. With `.gitattributes` containing
`*.txt text eol=lf`, changing an untracked file from LF to CRLF also returned
0 and printed `matches`. Fix: enumerate paths with NUL delimiters, propagate
enumeration/hash failures, hash without clean filters, and explicitly handle
symlinks and missing files. Add negative assertions that these mutations fail
comparison. Reference: https://git-scm.com/docs/git-hash-object (`--no-filters`)

### 3. P2 — Revalidate durable identity before using a saved Compose file

Location: `workspace/workspace-lifecycle.sh:95–113`; generation-only identity
validation is at `workspace/workspace-compose.sh:147–154`. The identity record
is checked only during generation. Every subsequent lifecycle operation trusts
the saved file. Replacing/restoring the state directory with one recorded for
another checkout bypasses the intended mismatch guard until the user happens
to regenerate the Compose file. Reproduction: generate a valid file, change
its state record's canonical path to another synthetic checkout, then use the
saved file. Fresh generation rejected the mismatch (rc 1), but `validate` and
`start` both returned 0. Fix: use a non-mutating identity/path check before
start/recreate/cache-clear can reuse state or remove a working container;
validate should perform the same check. Test changes to the record after
generation.

### 4. P2 — Propagate Docker query errors instead of reporting a successful stop

Location: `workspace/workspace-lifecycle.sh:75–83,124–128`. `is_running` is
used as a conditional, so failure of the Docker query is treated like an
absent/stopped container. The final echo also masks the failed container-id
substitution. If the daemon/socket is unreachable, `stop` prints success and
exits 0 without having stopped anything. Reproduction: set `DOCKER_HOST` to a
nonexistent socket and invoke `stop`. Result: rc 0 and a success message. Fix:
distinguish query failure from a successful empty result, propagate errors,
and retain useful diagnostics. Add an unavailable-daemon regression that
requires a nonzero exit.

### 5. P2 — Resolve or reject relative durable-state roots before writing

Location: `workspace/workspace-compose.sh:147–154,178–181`. `HESTIA_STATE_ROOT`
is concatenated and used for state creation and both bind endpoints without
resolving it to an absolute path. A relative value creates an identity record
relative to the generator's working directory, while Compose interprets the
source relative to the generated file and the container target remains
relative. Generation and Compose config validation succeed, but start fails.
With an output file in another directory, the source also resolves to a
different host location. Reproduction: relative `HESTIA_STATE_ROOT` with an
output file in the fixture directory; generation rc 0, start rc 1 with
`invalid mount path ... mount path must be absolute` after creating network
resources. Fix: resolve the state root to a physical absolute path before
deriving the state directory, or reject relative roots before writing any
state. Test from different generator/output directories.
