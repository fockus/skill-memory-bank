---
spec_id: reviewer-2.0
topic: Reviewer 2.0 — calibrated, tests-aware, golden-suite verified
status: ready
author: brainstorming-session
created: 2026-05-23
parent_roadmap: harness-upgrade (S1 of S1..S4)
addresses_gaps: [GAP-1, GAP-5, GAP-7]
non_addresses: [GAP-2, GAP-3, GAP-4, GAP-6, GAP-8, GAP-9, GAP-10]
breaking_changes: no (additive orchestrator; migration note required for custom reviewer wrappers)
---

# Reviewer 2.0 — Design

Sub-project **S1** of the harness upgrade roadmap that aligns memory-bank skill with the Anthropic article "Harness Design for Long-Running Agents".

This spec covers three gaps: few-shot calibration (GAP-1), tests-aware reviewer (GAP-5), and golden calibration suite (GAP-7). The remaining gaps (sprint contract, pivoting, fail-fast default, PreCompact actualize, done-gates, append-only guard, multi-model roles) are out of scope and live in S2/S3/S4.

## 1. Goals & Non-goals

### Goals

- **G1 (GAP-1)** — Calibrate `mb-reviewer` with few-shot examples that are loaded deterministically from a layered location, so verdict variance across iterations drops materially. SMART target: see §9 DoD.
- **G2 (GAP-5)** — Make reviewer aware of current test status on touched files. Failing tests pre-inject an auto-generated `blocker` issue into the reviewer payload; reviewer is forbidden to downgrade it.
- **G3 (GAP-7)** — Provide a runnable golden calibration suite (≥5 cases at S1 close, expandable to 15+ in backlog) with a strict but practical match metric: `verdict == expected.verdict AND counts within tolerance AND must_have_categories ⊆ actual_categories`.
- **G4** — Apply SRP to the review step: deterministic payload assembly is separated from LLM-based judgment.
- **G5** — Layered examples (skill baseline in `references/rubric-examples/` + optional project override in `.memory-bank/rubric-examples/`).

### Non-goals (explicit)

- Sprint contract as an artifact (deferred to S2).
- Strategic pivoting on stagnant scores (S2).
- Changing `on_max_cycles` default to `stop_for_human` (S2).
- Auto-actualize before PreCompact (S3).
- Mandatory `done_gates` without an active plan (S3).
- Physical append-only guard on `progress.md` (S3).
- Assigning `mb-reviewer` to a different model than `mb-developer` (S4).
- Changing `severity_gate` logic or `mb-work-severity-gate.sh`.
- Touching `plan-verifier` agent (lives at a higher tier; revisited in S3).

## 2. Architecture overview

```
┌──────────────────┐    invokes subagent  ┌────────────────────────┐
│   /mb work       │ ──────────────────► │ scripts/mb-review.sh   │
│                  │    (Task / opencode  │                        │
│                  │     run / codex run) │                        │
│  step 3c review  │                     │ "Review Orchestrator"  │
└──────────────────┘                     └────────────────────────┘
                                            │  (deterministic)
            ┌───────────────────────────────┼─────────────────────────────┐
            ▼                               ▼                             ▼
  ┌─────────────────┐         ┌──────────────────────┐       ┌────────────────────┐
  │ Examples loader │         │ Test-cache resolver  │       │ Payload builder    │
  │ (layered)       │         │ (sha + TTL)          │       │ (assembles prompt) │
  └─────────────────┘         └──────────────────────┘       └────────────────────┘
            │                               │                             │
            │                               ▼                             │
            │                ┌──────────────────────────┐                 │
            │                │ Task → mb-test-runner    │ ◄── on miss     │
            │                │ writes last-tests.json   │                 │
            │                └──────────────────────────┘                 │
            └───────────────┬───────────────┘                             │
                            ▼                                             │
                ┌──────────────────────┐                                  │
                │ Final review payload │ ◄────────────────────────────────┘
                │ (markdown sections)  │
                └──────────────────────┘
                            │ Task → mb-reviewer
                            ▼
                ┌──────────────────────┐
                │ mb-reviewer.md       │ ← "Pure judge" (simplified)
                │ returns JSON verdict │
                └──────────────────────┘
                            │
                            ▼
                ┌──────────────────────────────┐
                │ mb-work-severity-gate.sh     │ ← unchanged
                └──────────────────────────────┘
```

The orchestrator is the single new entry point for review. It owns deterministic concerns (file discovery, sha hashing, cache resolution, prompt assembly). The reviewer agent owns judgment only.

The same orchestrator backs the golden suite via `--input <case-dir>` so calibration runs use production code paths, not a parallel implementation.

## 3. File inventory

### New files

| Path | Kind | Purpose |
|------|------|---------|
| `scripts/mb-review.sh` | bash | Review orchestrator (entry point) |
| `scripts/mb-review-cache.sh` | bash | sha computation, TTL check, cache write helpers |
| `references/rubric-examples/common.md` | markdown | Stack-agnostic examples |
| `references/rubric-examples/python.md` | markdown | Python-specific examples |
| `references/rubric-examples/go.md` | markdown | Go-specific examples |
| `references/rubric-examples/typescript.md` | markdown | TS/JS examples |
| `references/rubric-examples/frontend.md` | markdown | React/Vue/Svelte UI examples |
| `references/rubric-examples/mobile.md` | markdown | iOS/Android examples |
| `references/rubric-examples/backend.md` | markdown | Backend-architecture examples |
| `tests/calibration/README.md` | docs | How to add cases |
| `tests/calibration/run.sh` | bash | Calibration suite runner |
| `tests/calibration/cases/<id>/case.json` | json | Case metadata + expected |
| `tests/calibration/cases/<id>/diff.patch` | patch | Synthetic diff |
| `tests/calibration/cases/<id>/files-touched.txt` | text | Touched paths |
| `tests/calibration/cases/<id>/prior-tests.json` | json | Stub mb-test-runner output |
| `tests/bats/test_mb_review_examples_loader.bats` | bats | Layered resolver tests |
| `tests/bats/test_mb_review_cache.bats` | bats | sha + TTL tests |
| `tests/bats/test_mb_review_payload_assembly.bats` | bats | Payload section tests |
| `tests/bats/test_mb_review_auto_finding_red.bats` | bats | Pre-injection on red tests |
| `tests/bats/test_mb_review_sha.bats` | bats | sha helper unit tests |
| `docs/reviewer-2.0.md` | docs | User-facing guide |

### Modified files

| Path | Change |
|------|--------|
| `agents/mb-reviewer.md` | Simplified to "pure judge". Reads pre-assembled payload, no longer loads rubric itself. Adds `referenced_example_id` field (optional) to issue JSON. Forbids downgrading auto-injected findings. |
| `commands/work.md` | Step 3c rewritten: dispatch goes through `mb-review.sh`, not directly to `mb-reviewer`. |
| `references/pipeline.default.yaml` | New optional keys: `test_cache_ttl_sec` (default 600), `review_examples.max_count` (default 8), `review_examples.rotation` (default `hash_run_id`). |
| `install.sh` | Distributes new `references/rubric-examples/` files; appends `.memory-bank/tmp/` to project `.gitignore`. |
| `CHANGELOG.md` | Document breaking changes (reviewer prompt simplified, new JSON field). |

### Project-owned, optional (created by users, not by skill)

- `.memory-bank/rubric-examples/<stack>.md` — per-project overrides
- `.memory-bank/rubric-examples/common.md` — per-project overrides
- `.memory-bank/tmp/last-tests.json` — runtime cache (gitignored)

## 4. Few-shot examples — format and resolution

### Layered resolver

Precedence (highest wins on `example_id` collision):

```
1. .memory-bank/rubric-examples/<stack>.md      ← project override (per stack)
2. .memory-bank/rubric-examples/common.md       ← project override (cross-stack)
3. references/rubric-examples/<stack>.md        ← skill baseline (per stack)
4. references/rubric-examples/common.md         ← skill baseline (cross-stack)
```

`<stack>` resolves from `.memory-bank/rules-profile.json:stack`. If the profile is absent, the resolver loads `common` only.

### File format

Markdown with one or more example blocks. Each block is delimited by `---` lines and starts with YAML front-matter.

````markdown
---
example_id: PY-SRP-001
stack: python
category: code_rules
severity: blocker
---

### Bad

```python
class UserService:
    def __init__(self, db): self.db = db
    def create(self, ...): ...
    def list(self, ...): ...
    def update(self, ...): ...
    def delete(self, ...): ...
    def send_welcome_email(self, ...): ...   # different responsibility
    def export_to_csv(self, ...): ...        # different responsibility
```

### Expected verdict fragment

```json
{
  "severity": "blocker",
  "category": "code_rules",
  "message": "UserService aggregates persistence, notification, and export — 3 distinct responsibilities.",
  "fix": "Extract send_welcome_email/export_to_csv into UserNotifier/UserExporter. Keep UserService as orchestrator if needed."
}
```
---
````

Multiple example blocks per file. Each block must have a unique `example_id` within its file (collisions across layers are resolved by precedence).

`category` values are constrained to those used in `pipeline.yaml:review_rubric`: `logic`, `code_rules`, `security`, `scalability`, `tests`. `severity` is one of `blocker`, `major`, `minor`.

### Injection into the reviewer payload

The orchestrator selects up to `review_examples.max_count` examples (default 8). Selection:

- If `rotation == hash_run_id`: deterministic sample seeded by SHA(run_id), aiming for ≥1 example per category present in the pool, then filling by stack-specificity (per-stack examples preferred over common).
- If `rotation == none`: first N examples by `example_id` lexical order, same category-coverage rule.

Only the **`### Bad`** snippet and the **expected verdict fragment** are injected. Good-code snippets are excluded from the payload (to avoid the reviewer parroting them in its `message`/`fix`). Good examples may live in documentation only.

The reviewer is instructed (in its updated prompt) to emit `referenced_example_id: "<id>"` on any issue it produces in response to a pattern it recognised from the injected examples. This field is optional and additive; absence does not affect severity-gate.

## 5. Test-cache contract (GAP-5)

### Cache file

Path: `.memory-bank/tmp/last-tests.json`.

```json
{
  "schema_version": 1,
  "run_id": "2026-05-23T05:42:11Z-a3b9c1",
  "stack_detected": "python",
  "touched_files_sha": "sha256:7a8b...",
  "tests_pass": true,
  "counts": { "passed": 142, "failed": 0, "skipped": 3 },
  "coverage": { "overall": 0.87, "touched": 0.94 },
  "failures": [],
  "elapsed_sec": 12.4
}
```

### Hit/miss algorithm

```
1. touched_files = git diff --name-only <baseline>..HEAD
   (baseline read from active plan's frontmatter; fallback to HEAD~1)
2. touched_sha = sha256(
       sorted(touched_files)
       || for each path:
            if exists: sha256_of_file(path)
            else:      "DELETED:" + path
   )
3. If .memory-bank/tmp/last-tests.json exists AND
      cache.schema_version == 1 AND
      cache.touched_files_sha == touched_sha AND
      now() - parse(cache.run_id) < test_cache_ttl_sec (default 600)
   → HIT: use cache as prior_evidence
   Else
   → MISS:
       a. Dispatch test-runner via `mb-dispatch.sh` with hint `scope=touched`
          (Claude Code: Task(mb-test-runner); OpenCode: `opencode run --agent mb-test-runner`;
          falls back to `scope=full` if framework lacks file-level selection)
      b. mb-test-runner writes fresh JSON to last-tests.json
      c. Re-read cache, proceed with HIT path
4. If tests_pass == false:
      Construct auto_finding:
        {
          "severity": "blocker",
          "category": "tests",
          "auto_generated": true,
          "message": "N failing tests on touched files (see failures[])",
          "details": cache.failures (top 5)
        }
      Inject into payload under `## Auto-generated findings (MUST INCLUDE)`.
```

### TTL — chosen value

`test_cache_ttl_sec: 600` (10 minutes). Rationale: long enough to amortise across consecutive review cycles in one fix-loop iteration; short enough to expire if the developer pauses, switches branches, or leaves the desk. Configurable per project via `pipeline.yaml`.

### Force-refresh

`/mb work --refresh-tests` removes the cache file before the orchestrator runs.

### Reviewer obligation

The reviewer prompt is updated with a hard rule:

> Any issue under `## Auto-generated findings (MUST INCLUDE)` MUST appear in your output JSON as the first item(s) of `issues[]`, with severity and category preserved verbatim. You may add detail to `message` and `fix`, but you may not downgrade severity or move the category. Failing to do so produces an invalid verdict.

The orchestrator post-validates this: if `tests_pass == false` but the returned JSON lacks at least one `category == "tests"` issue with `severity == "blocker"`, the orchestrator rewrites the verdict to `CHANGES_REQUESTED` and prepends the missing finding, logging a warning. This is a safety net, not the primary mechanism.

## 6. Golden calibration suite (GAP-7)

### Directory layout

```
tests/calibration/
├── README.md
├── run.sh
├── cases/
│   ├── PY-001-srp-violation/
│   │   ├── case.json
│   │   ├── diff.patch
│   │   ├── files-touched.txt
│   │   └── prior-tests.json
│   ├── PY-002-missing-tests/
│   ├── GO-001-error-wrap/
│   ├── TS-001-any-leak/
│   └── ... (at least 5 cases at S1 close; 15+ in backlog)
└── results/                 ← gitignored
    └── <timestamp>_run.json
```

### `case.json` schema

```json
{
  "case_id": "PY-001-srp-violation",
  "description": "UserService aggregates 3 distinct concerns",
  "stack": "python",
  "expected": {
    "verdict": "CHANGES_REQUESTED",
    "counts": {
      "blocker_min": 1, "blocker_max": 2,
      "major_max": 3,
      "minor_max": 5
    },
    "must_have_categories": ["code_rules"],
    "must_not_have_categories": [],
    "expected_example_refs": ["PY-SRP-001"]
  }
}
```

### Match metric

```
PASS if all hold:
  actual.verdict == expected.verdict
  expected.blocker_min ≤ actual.counts.blocker ≤ expected.blocker_max
  actual.counts.major ≤ expected.major_max
  actual.counts.minor ≤ expected.minor_max
  set(expected.must_have_categories) ⊆ set(i.category for i in actual.issues)
  set(expected.must_not_have_categories) ∩ set(...) == ∅

WARN (does not fail) if PASS holds but:
  set(expected.expected_example_refs) ⊄ set(i.referenced_example_id for i in actual.issues)
  → calibration patterns are not being attributed correctly
```

### Runner — `tests/calibration/run.sh`

```
Usage:
  bash tests/calibration/run.sh                     # all cases
  bash tests/calibration/run.sh --stack=python      # filter by stack
  bash tests/calibration/run.sh --case=PY-001       # single case
  bash tests/calibration/run.sh --emit-payload      # don't dispatch reviewer; dump prompt
```

Per case the runner:

1. Sets up a temporary working dir with `cases/<id>/diff.patch` as the "current diff" and `prior-tests.json` as the test cache.
2. Invokes `scripts/mb-review.sh --input cases/<id> --emit-payload` to assemble the prompt deterministically. The `--input` flag tells the orchestrator to read inputs from the case dir instead of git/`.memory-bank/tmp/`.
3. Either:
   - With `--emit-payload`: writes the assembled payload to stdout; the run is a payload-shape smoke test (verifies sections present, examples loaded), no LLM call.
   - Default mode: dispatches `Task(mb-reviewer)` with the assembled payload and collects the JSON verdict.
4. Compares the JSON verdict (or the payload shape, in smoke mode) against `case.json:expected` using the match metric.
5. Writes a row to `tests/calibration/results/<timestamp>_run.json`.

The runner ends by printing a PASS/WARN/FAIL table and exits with code 0 (all PASS), 1 (≥1 WARN, no FAIL), or 2 (≥1 FAIL).

### CI integration

`.github/workflows/calibration.yml`:
- Trigger: `workflow_dispatch` (manual) and `schedule: cron: '0 6 * * 1'` (weekly Monday).
- Job: runs `bash tests/calibration/run.sh` against a small budget (cap on tokens via env), uploads `results/<timestamp>_run.json` as an artifact.
- Non-blocking: failures notify but do not block PR merges. LLM non-determinism makes blocking unsuitable.

### What this protects

- Editing `references/rubric-examples/*.md` — run the suite locally before commit to confirm we haven't degraded calibration.
- Upgrading the model behind `mb-reviewer` — re-run, observe the shift, decide whether to update examples or thresholds.

## 7. Reviewer agent — simplified prompt contract

The new `mb-reviewer.md` describes a "pure judge" with these inputs and outputs.

### Input — single pre-assembled markdown payload

The payload has 5 sections in fixed order:

```
## Plan context
(plan path, stage heading, item body — verbatim from /mb work)

## Diff
(unified diff of touched files)

## Calibration examples (reference patterns — not part of current diff)
(rendered from layered examples loader, up to N entries)

## Prior evidence (from mb-test-runner)
(rendered from .memory-bank/tmp/last-tests.json)

## Auto-generated findings (MUST INCLUDE)
(present only when tests_pass == false; otherwise omitted)
```

### Output — strict JSON

```json
{
  "verdict": "APPROVED" | "CHANGES_REQUESTED",
  "counts": { "blocker": 0, "major": 0, "minor": 0 },
  "issues": [
    {
      "severity": "blocker" | "major" | "minor",
      "category": "logic" | "code_rules" | "security" | "scalability" | "tests",
      "file": "<path>",
      "line": 42,
      "message": "<concise problem>",
      "fix": "<concrete corrective action>",
      "referenced_example_id": "PY-SRP-001"   // optional
    }
  ]
}
```

### Hard rules in the prompt

1. The reviewer MUST NOT load files from disk; everything it needs is in the payload.
2. The reviewer MUST include every entry from `## Auto-generated findings (MUST INCLUDE)` verbatim as the first items of `issues[]`. Severity and category cannot be lowered.
3. The reviewer MUST emit `referenced_example_id` on any issue it produces in response to a recognized calibration pattern.
4. The reviewer MUST output JSON only — no prose wrapping.

## 8. Testing strategy

### Integration (≈70%, primary)

Bats coverage on the orchestrator:

| Bats file | Covers |
|-----------|--------|
| `test_mb_review_examples_loader.bats` | Layered merge, project override beats baseline, missing-stack fallback to common, missing-everything degrades gracefully |
| `test_mb_review_cache.bats` | sha stability across re-runs with identical inputs, TTL expiry, `--refresh-tests` invalidates cache, schema_version mismatch triggers MISS |
| `test_mb_review_payload_assembly.bats` | All 5 sections present in the right order; example truncation respects `max_count`; rotation deterministic for given run_id |
| `test_mb_review_auto_finding_red.bats` | When `tests_pass=false`, the payload contains the `## Auto-generated findings (MUST INCLUDE)` block with at least one blocker/tests entry; the orchestrator post-validates reviewer output and rewrites verdict if reviewer drops the finding |

### Unit (≈20%)

| Bats file | Covers |
|-----------|--------|
| `test_mb_review_sha.bats` | `compute_touched_sha` deterministic for same input; reorders normalised; deleted files marked |

If any helper grows past ~50 lines of bash with structural complexity, port to Python in `scripts/mb_review_helpers.py` with pytest coverage. Otherwise bash stays.

### E2E (≈10%, manual / offline)

`tests/calibration/run.sh` — the golden suite itself. Not part of PR-blocking CI.

### Static checks

- `shellcheck` on `scripts/mb-review.sh` and `scripts/mb-review-cache.sh`.
- Existing `mb-rules-check.sh` runs on new bash files — must be CLEAN (no TODO, no oversized functions).

## 9. Definition of Done (SMART)

- [ ] `scripts/mb-review.sh` exists and passes `shellcheck` with no findings.
- [ ] `scripts/mb-review-cache.sh` exists and passes `shellcheck`.
- [ ] `references/rubric-examples/{common,python,go,typescript,frontend,mobile,backend}.md` each contain ≥3 example blocks; across the suite all 5 categories (`logic`, `code_rules`, `security`, `scalability`, `tests`) have ≥3 examples each.
- [ ] `agents/mb-reviewer.md` rewritten under the §7 contract; no rubric loading logic remains in the prompt; `referenced_example_id` documented.
- [ ] `commands/work.md` step 3c invokes `scripts/mb-review.sh` (not `Task → mb-reviewer` directly); existing severity-gate flow preserved.
- [ ] Bats files in §8 exist and pass locally (`bats tests/bats/test_mb_review_*.bats`).
- [ ] `tests/calibration/cases/` contains ≥5 cases, one per category, with `case.json + diff.patch + files-touched.txt + prior-tests.json`.
- [ ] `tests/calibration/run.sh --emit-payload` runs without network/LLM, exits 0 on all 5 cases (smoke).
- [ ] `tests/calibration/run.sh` (live LLM mode) PASSes ≥4 of 5 cases, no FAIL; WARNs allowed.
- [ ] `.github/workflows/calibration.yml` exists, `workflow_dispatch` works, non-blocking.
- [ ] `install.sh` adds `.memory-bank/tmp/` to project `.gitignore`; ships new `references/rubric-examples/` files.
- [ ] `references/pipeline.default.yaml` carries new keys with defaults; existing `pipeline.yaml` files without them still work (resolver uses defaults).
- [ ] `docs/reviewer-2.0.md` covers: how examples are loaded, how to add a custom example, how the test cache works, how to run the calibration suite, what `referenced_example_id` means.
- [ ] `CHANGELOG.md` entry under unreleased: breaking changes enumerated.
- [ ] `/mb verify` on the implementation branch finds no regressions in existing bats suites.

## 10. Risks and mitigations

| Risk | Mitigation |
|------|------------|
| Reviewer ignores or paraphrases auto-injected findings | Orchestrator post-validation rewrites verdict (§5). Logged as warning. |
| Examples become outdated as RULES.md evolves | Calibration suite catches drift; weekly CI run highlights regressions. |
| Layered resolver behaves surprisingly on collision | §8 bats `test_mb_review_examples_loader` codifies precedence; documented in `docs/reviewer-2.0.md`. |
| Test cache stale despite touched_sha unchanged (e.g., dependency change) | TTL bounds staleness to 10 min; `--refresh-tests` is the manual escape hatch. |
| Calibration LLM cost balloons on weekly cron | Token cap via env; reduce frequency or skip if budget alarm triggers (operational, not in S1 scope). |
| Bash grows unwieldy past 300 lines | Port helpers to `scripts/mb_review_helpers.py`; bats stays as integration harness. |

## 11. Out-of-scope follow-ups (handed to S2/S3/S4)

- `sprint contract` artifact between generator and evaluator (S2).
- `progress_trend` field in reviewer output + `on_stagnant: pivot` config (S2).
- `on_max_cycles: stop_for_human` becoming default (S2).
- Auto-trigger `/mb update` on PreCompact + `.memory-bank/handoff/latest.md` (S3).
- Mandatory `done_gates` even without an active plan (S3).
- Physical append-only guard on `progress.md` (S3).
- Multi-model `roles.<role>.model` assignment (S4).

## 12. Open questions to resolve during implementation

- Exact baseline-commit resolution rule when no active plan exists (current orchestrator falls back to `HEAD~1`; may need richer detection).
- Whether `--scope=touched` works uniformly across `pytest`, `go test`, `jest`, `vitest`, `cargo test`. Where it doesn't, document the fallback to `--scope=full` in `docs/reviewer-2.0.md`.
- Initial example-pool size per stack: target ≥3 per category at S1 close; the right ceiling lives in S2 (backlog).

## Alignment with dynamic-flow & six-pattern (2026-06-16)

reviewer-2.0 was authored before dynamic-flow Phase 1 shipped. Its scope is unchanged; these are the load-bearing seams that keep
the two specs coherent (forward-references only — no new in-scope requirements added here, so the EARS set + task list stay frozen):

- **Deterministic payload → Adversarial-Verification branch input.** `scripts/mb-review.sh` (Task 1) produces a deterministic,
  cache-keyed review payload. That payload is exactly the per-branch input the dynamic-flow **Adversarial-Verification** pattern
  (`flow-templates/patterns/adversarial-verify.md`, dynamic-flow Task 10) fans out via `mb-fanout.sh` to N independent reviewers.
  reviewer-2.0 owns single-verdict reliability; the pattern owns the ensemble — compose, do not duplicate the payload builder
  inside the pattern.
- **Binding review principle** (this session's lesson — memory `governed-review-independent-refix.md`). A fix-cycle's FIXED code
  MUST face a fresh INDEPENDENT review before GO; never render a final GO on a lead/self-review alone; loop until an independent
  round stops finding criticals/majors. reviewer-2.0's golden suite (GAP-7) calibrates a single verdict; this principle governs the
  *loop* around it and lives in the work-loop / pattern layer (work-loop-v2 pivoting + dynamic-flow Loop-Until-Done). The golden
  suite SHOULD include at least one case asserting a self-review GO is rejected when the fixed diff was not re-reviewed independently.
- **Completion authority.** Whatever verdict the reviewer emits, "done" is gated by the dynamic-flow firewall (`mb-flow-verify.sh`,
  exit code), never by the reviewer's own assessment (REQ-DF-060). reviewer-2.0 feeds the gate; it is not the gate.

## Actualization 2026-07-05 (active roles: implement=sonnet · review=codex gpt-5.5 · judge=opus)

reviewer-2.0 was authored assuming `mb-reviewer` (Claude) is the judge. The active `pipeline.yaml` routes review to
`codex-cli` (gpt-5.5) as the default single reviewer, with `mb-judge` (opus) as the gate. This does **not** change
reviewer-2.0's scope — G4 already separates deterministic payload assembly (`mb-review.sh`) from the LLM judge. Seams:

- **`mb-review.sh` is model-agnostic.** It assembles the deterministic payload (diff + calibration examples + test evidence
  + auto-findings) and feeds WHOEVER `pipeline.yaml` names as reviewer — `codex-cli` (default) OR `mb-reviewer` (fallback) OR
  each branch of the `adversarial-verify` ensemble. The 5-section payload contract (§7) is the review INPUT regardless of judge model.
- **Reuse `mb-work-review-parse.sh` for verdict-out.** Its existing `--external` normalizer (I-093) already parses codex output
  into the strict verdict schema. reviewer-2.0's post-validation (auto-blocker cannot be dropped, §5) hooks a thin post-step onto
  that normalizer — do NOT author a second parser.
- **Calibration examples feed the codex prompt.** The `## Calibration examples` payload section is part of what `codex exec`
  receives, so calibration (G1) applies to the GPT-5.5 reviewer too, not only Claude `mb-reviewer`.
- **`progress_trend` is a hook point only in this phase.** `mb-review.sh` writes the last-verdict cache
  (`.memory-bank/tmp/last-verdict-<item>.json`); work-loop-v2 (Phase 2) computes the trend from it. Phase 1 ships the cache write,
  not the trend math.
