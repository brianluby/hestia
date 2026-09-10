# Disposition: OCR review of PRs #1–#8

[Report](2026-09-09-ocr-prs-1-8.md) · [Verbatim transcript](2026-09-09-ocr-prs-1-8.txt) · Reviewed range `d41279d..0578b1b`

Disposition of all 57 OCR comments, combining the OCR report with the
user-validated triage (which reproduced selected findings in isolated probes
and pushed back on others). Verdicts: **fix** (ticketed below), **decide**
(owner decision ticketed), **deferred** (valid, documented limitation),
**out of scope** (recorded, not actioned), **by design** / **unsupported**.

| Ticket | Scope |
| --- | --- |
| `222X8FA` | Lifecycle: stopped-container correctness, pull policy, argument validation |
| `WXVTEZ7` | Identity helper hardening + generated Compose value validation |
| `WWC6ASS` | Test evidence: exercise generated output, rejected-op invariants, artifact retention |
| `GVYSD02` | Image hygiene: platform pin, toolchain policy, layer caches, dead root state |
| `F5KMRS3` | Documentation reconciliation + ignore hygiene + committing this archive |
| `A5H3NY9` | Owner decision: provenance posture before authenticated-agent integration |

## 1. `tests/workspace-lifecycle.test.sh` (10)

| # | Finding | Verdict | Action |
| --- | --- | --- | --- |
| 1 | No preflight for compose plugin | fix | `WWC6ASS` — compose version SKIP |
| 2 | Substitutions under `set -e` abort before reporting | partly valid | `WWC6ASS` — abrupt nonzero exit is a failure (user triage); guard where a missing value is the tested outcome; no mechanical `|| true` |
| 3 | Multi-step chains collapsed into one status | partly valid | `WWC6ASS` — split where attribution matters; `go test -count=1` where persistence is proven |
| 4 | Fallible commands lack explicit reporting | partly valid | `WWC6ASS` — same diagnostics class |
| 5 | Extracted identity values unvalidated | fix | `WWC6ASS` — require exactly one well-formed value |
| 6 | `exec`/`run` need `-T` and safe quoting | partly valid | `WWC6ASS` — audit; most calls already use `-T` |
| 7 | Advertised `remove-runtime` leg missing | fix | `WWC6ASS` — explicit assertion |
| 8 | Teardown destroys evidence | fix | `WWC6ASS` — keep artifacts on failure |
| 9 | stderr discarded | partly valid | `WWC6ASS` — diagnostics class |
| 10 | Image tag duplicated test/product | fix | `WWC6ASS` — derive from generator |

## 2. `tests/workspace-id.test.sh` (8)

| # | Finding | Verdict | Action |
| --- | --- | --- | --- |
| 1 | Helpers don't validate non-empty output | fix | `WWC6ASS` |
| 2 | No preflight for the tested script | fix | `WWC6ASS` — existence/executable/syntax |
| 3 | Failure contracts asserted by prose only | partly valid | `WWC6ASS` — exit code primary, prose secondary |
| 4 | Hand-rolled record parsing | partly valid | `WWC6ASS` — use strict parser shape from the tool |
| 5 | Git diagnostics suppressed, version assumed | partly valid | `WWC6ASS` |
| 6 | Trap deletes failure evidence | fix | `WWC6ASS` — keep-on-failure |
| 7 | `make_repo` inherits global Git config | fix | `WWC6ASS` — `GIT_CONFIG_GLOBAL=/dev/null`, no hooks/templates |
| 8 | Sanitization/bounds edge cases untested | partly valid | `WWC6ASS` — empty-sanitize, non-ASCII, leading-dash |

## 3. `tests/workspace-cache-clear.test.sh` (5)

| # | Finding | Verdict | Action |
| --- | --- | --- | --- |
| 1 | Trap installed too late | fix | `WWC6ASS` |
| 2 | Fixture root extracted without validation | fix | `WWC6ASS` — single match, exists, inside sandbox |
| 3 | No decoy resources proving scoped removal | fix | `WWC6ASS` — sentinel volumes |
| 4 | Multi-line output embedded in test names | fix | `WWC6ASS` |
| 5 | Guards assert exit only, not unchanged state | fix | `WWC6ASS` — before/after docker state |

## 4. `tests/workspace-mounts.test.sh` (5)

| # | Finding | Verdict | Action |
| --- | --- | --- | --- |
| 1 | Hand-written binds instead of generator output | fix (validated) | `WWC6ASS` — derive binds from generated YAML |
| 2 | Compose resources not cleaned up | fix | `WWC6ASS` — project down + volume rm in trap |
| 3 | Git restore best-effort, errors hidden | partly valid | `WWC6ASS` — surface restore failures |
| 4 | Hand-copied record format can poison state | fix | `WWC6ASS` |
| 5 | Stale `wrun` comment | fix | `WWC6ASS` |

## 5. `workspace/workspace-lifecycle.sh` (4)

| # | Finding | Verdict | Action |
| --- | --- | --- | --- |
| 1 | Usage vs file errors conflated | fix | `222X8FA` — distinct exits/messages |
| 2 | Metadata scraped, not validated | partly valid | `222X8FA` — validate charset/single-line; scraping our own generated file is acceptable |
| 3 | `ps -q` conflates running with existing | fix (validated) | `222X8FA` — existing vs running queries |
| 4 | `up` may pull images | fix (validated) | `222X8FA` — `--pull never` at every `up` |

## 6. `identity/workspace-id.sh` (10)

| # | Finding | Verdict | Action |
| --- | --- | --- | --- |
| 1 | Inherits ambient Git env | fix (validated) | `WXVTEZ7` — sanitize `GIT_*` overrides |
| 2 | Resolved paths not validated | fix | `WXVTEZ7` — absolute/non-empty checks |
| 3 | Hash fallback lacks clean failure | fix | `WXVTEZ7` |
| 4 | Empty `--state-dir` silently disables | fix | `WXVTEZ7` — reject |
| 5 | Predictable temp names | fix | `WXVTEZ7` — mktemp + atomic create |
| 6 | Record permissions/integrity weak | partly valid | `WXVTEZ7` — 0700/0600 permissions; checksum rejected (rewriting both defeats it — user triage) |
| 7 | Record parsing too loose | fix | `WXVTEZ7` — strict keys, distinct errors |
| 8 | Submodule labels collide | valid, out of scope | No submodule support is claimed; revisit when a milestone needs it |
| 9 | Locale-dependent sanitization | fix | `WXVTEZ7` — `LC_ALL=C` |
| 10 | No `--` terminator, leading-dash paths | fix | `WXVTEZ7` |

## 7. `workspace/workspace-compose.sh` (1)

| # | Finding | Verdict | Action |
| --- | --- | --- | --- |
| 1 | Generated scalars injectable | fix (validated) | `WXVTEZ7` — charset validation, newline/control rejection, `$$` escaping (validated: `cash$VARIABLE` resolves differently) |

## 8. `.gitignore` (5)

| # | Finding | Verdict | Action |
| --- | --- | --- | --- |
| 1 | `.env.*` exceptions too narrow | out of scope | Speculative files that don't exist (user triage) |
| 2 | Key rules miss extensionless keys | out of scope | Same; no secrets workflow exists yet |
| 3 | Hydrated-state allow-list too narrow | by design | epiq's tracked state files are intentional; only hydrated `events/`/`log/` are local |
| 4 | `*.log` too loose and incomplete | out of scope | Speculative |
| 5 | `.zcode/` possibly stale | unsupported | It is the agent worktree root; `F5KMRS3` annotates it |

## 9. `.dockerignore` (2)

| # | Finding | Verdict | Action |
| --- | --- | --- | --- |
| 1 | Context includes `.epiq/`, `.zcode/` local state | fix | `F5KMRS3` |
| 2 | Broad `**/*.key` may hit fixtures | out of scope | No such fixture files exist |

## 10. `Dockerfile` (7)

| # | Finding | Verdict | Action |
| --- | --- | --- | --- |
| 1 | Architecture not enforced | fix | `GVYSD02` — `--platform=linux/arm64` |
| 2 | Overridable ARGs bypass integrity | decide | Builder already controls the build — not a boundary (user triage); `A5H3NY9` |
| 3 | Dev-writable mise state not a trust boundary | decide | Not an automatic high severity; `A5H3NY9` |
| 4 | Dead root-owned mise state from ENV ordering | fix | `GVYSD02` |
| 5 | Ownership guarantee only for empty volumes | deferred | Pre-existing volumes/binds/`--user` overrides documented as a limitation; same class as unwritable-state recovery |
| 6 | `GOTOOLCHAIN` default `auto` allows silent downloads | fix | `GVYSD02` — `GOTOOLCHAIN=local` as explicit policy |
| 7 | Build caches ship in the layer | fix | `GVYSD02` — throwaway caches inside the RUN |

## Corrections to OCR claims (from the user-validated triage)

- **Trust persistence:** `mise trust` in one `compose exec` does remain
  effective in a second exec against the same container; only container
  recreation loses it. The per-session claim was overstated.
- **`--no-pull` is not a documented compose option**; the correct policy flag
  is `--pull never`.
- The report's expanded summary ends abruptly at Dockerfile finding 5; the
  verbatim transcript's raw findings (used here) are complete.
