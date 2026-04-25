# Plan: refactor — agents-quality

<!-- PLAN_START_REF: will be auto-filled by mb-plan.sh in future versions -->
**Baseline commit:** `941ba42` (fix(lint): SC2015 in mb-config.sh cmd_set)

## Context

**Problem:** The skill ships 4 subagents (`mb-manager`, `mb-doctor`, `mb-codebase-mapper`, `plan-verifier`), but audit surfaced:

1. **`plan-verifier` is the weakest agent** — does not run tests (`pytest --cov`, `go test -cover`), does not check RULES.md (SOLID/Clean Arch/TDD), uses `git diff HEAD~N` as a guess instead of a stored baseline ref. This is the gate before `/mb done` — a weak gate means silent DoD drift.
2. **`mb-codebase-mapper` does not use `graph.json`** even though `/mb graph` produces it with AST-grade accuracy. CONVENTIONS/CONCERNS still rely on grep (backlog entry in code).
3. **`mb-doctor` does not check `research.md` ↔ `experiments/`** consistency (hypothesis confirmed/refuted without an EXP-NNN file), does not enforce `index.json` regeneration after edits, lacks git-safety guidance for destructive fixes.
4. **`mb-manager` does not specify `action: done`** — current `/mb done` is described as "combined flow actualize + note", which is vague for a subagent.
5. **No rules-enforcement subagent.** `/review.md` does SOLID/Clean-Arch/DRY/KISS checks inline in the main agent (~70 lines of system prompt payload per invocation). Wasted context + no reuse from `/commit`, `/pr`, `/verify`.
6. **No test-runner subagent.** `/test.md` describes the flow but main agent runs commands, parses output, interprets coverage. Duplicate work every time; `plan-verifier` also needs this.
7. **No session-recoverer** for `/catchup` on large MBs (>100 notes). Current `/catchup.md` is a 17-line dispatcher — does not do smart context selection.

**Expected result:**

- All 4 existing subagents pass the quality audit: frontmatter present, actions explicit, templates deterministic, failure modes handled.
- `plan-verifier` runs tests, reads RULES.md, uses a tracked baseline ref.
- `mb-codebase-mapper` consumes `graph.json` when present (fallback to grep if absent).
- `mb-doctor` covers RESEARCH↔experiments drift, regenerates `index.json`, recommends git-stash before destructive fixes.
- 2 new subagents shipped: `mb-rules-enforcer`, `mb-test-runner`. `/review`, `/test`, `/verify` updated to delegate.
- `mb-manager` documents `action: done` explicitly.
- Optional: `mb-session-recoverer` (Stage 7, feature-flagged — ship only if usage data justifies it).

**Related files:**
- `agents/mb-manager.md`, `agents/mb-doctor.md`, `agents/plan-verifier.md`, `agents/mb-codebase-mapper.md`
- `commands/mb.md`, `commands/review.md`, `commands/test.md`, `commands/done.md`, `commands/catchup.md`, `commands/roadmap.md`
- `scripts/mb-plan.sh`, `scripts/mb-metrics.sh`, `scripts/mb-codegraph.py`, `scripts/mb-index-json.py`
- `references/planning-and-verification.md`, `SKILL.md`, `AGENTS.md`
- `tests/` (new subagent contract tests — spec to be defined in Stage 1 TDD)

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: plan-verifier upgrade — run tests, read RULES.md, tracked baseline ref

**Why first:** this is the hardest gate in the flow (before `/mb done`). Every other stage benefits from it being trustworthy. Also unlocks `mb-test-runner` extraction in Stage 3.

**What to do:**
1. Add **Step 3.5: Run tests via `mb-metrics.sh --run`**. Parse stdout for `test_status=pass|fail` and `src_count`. If the plan's DoD contains `coverage ≥ X%`, also parse `coverage=` line (if project exposes it; otherwise report as "not measured" — do not silently pass).
2. Add **Step 3.6: Check RULES.md adherence**. Read `./.memory-bank/RULES.md` (fallback `~/.claude/RULES.md`) and grep diff for flagged patterns: SRP (>300 lines per changed file → warn), DIP (constructor-taking-concrete → warn), TDD (source file changed without matching test file touch → CRITICAL unless file in `exceptions` list), Clean Arch (domain/ imports from infrastructure/ → CRITICAL).
3. Add **`Baseline commit`** field to plan template (`mb-plan.sh`). `plan-verifier` reads it and uses `git diff <baseline>...HEAD` instead of `HEAD~N`. Fallback: if no baseline recorded, read plan-file ctime → find last git commit before that time (`git log --before=<ctime> -1 --format=%H`).
4. Update response format — add `**Tests run:** pass|fail|not-run` and `**RULES violations:** <count>` rows. Update Gate block to explicitly consume those.
5. Update `references/planning-and-verification.md` + `SKILL.md` with the new capabilities.

**Testing (TDD — tests BEFORE implementation):**
- **Unit (shell):** `tests/agents/test_plan_verifier_baseline.sh` — creates a temp git repo + plan with `Baseline commit: <hash>`, verifies the agent would emit the correct `git diff` command. Edge: missing baseline → falls back to ctime lookup. Edge: baseline ref missing from history → WARNING + fall back to `HEAD~10`.
- **Unit (shell):** `tests/agents/test_plan_verifier_rules.sh` — creates fixture diff violating SRP (file >300 lines) and Clean Arch (domain→infra import); asserts each violation appears once in verifier report. Edge: RULES.md missing → WARN, do not CRITICAL.
- **Integration:** `tests/agents/test_plan_verifier_tests.sh` — fixture project (tiny python pkg with pytest), runs full flow, asserts `tests_pass=true` populated. Edge: no test runner detected → `tests_run=not-measured`, not silently pass.
- **Contract:** no test executes real subagent LLM; all checks validate the prompt + script composition via stubs/fixtures.

**DoD (SMART):**
- [ ] `agents/plan-verifier.md` contains explicit Steps 3.5 + 3.6 with exact commands (`bash ~/.claude/skills/memory-bank/scripts/mb-metrics.sh --run`) — verify via `grep -c "mb-metrics.sh --run" agents/plan-verifier.md` ≥ 1
- [ ] `scripts/mb-plan.sh` writes `**Baseline commit:** <git rev-parse HEAD>` into the plan template — verify: create temp plan, grep for line
- [ ] 3 new test files exist and pass (`bash tests/agents/test_plan_verifier_*.sh` → exit 0)
- [ ] Response-format section of the prompt declares `Tests run:` and `RULES violations:` rows verbatim
- [ ] `references/planning-and-verification.md` lists the 2 new checks in the algorithm
- [ ] No regression: existing `/mb verify` dry-run smoke passes (manual, `tests/smoke/verify_dry.sh`)
- [ ] `shellcheck scripts/mb-plan.sh` = 0 warnings
- [ ] Complete within 1 working session (≤4h) — time-boxed; if blocked, split remainder into Stage 1b

**Code rules:** SOLID (SRP — keep each Step self-contained, no hidden coupling to earlier steps), KISS (no RULES-enforcement DSL — grep patterns are enough), YAGNI (do NOT add a rules-DSL just because we could — real parsing lives in `mb-rules-enforcer` in Stage 2)

---

<!-- mb-stage:2 -->
### Stage 2: new subagent — mb-rules-enforcer

**Why now:** `/review` inlines ~70 lines of SOLID/Clean-Arch/DRY/KISS prompt every call. A dedicated subagent cuts main-agent context and is reusable from `/commit`, `/pr`, and `plan-verifier` Step 3.6.

**What to do:**
1. Create `agents/mb-rules-enforcer.md` with full YAML frontmatter (`name`, `description`, `tools: Read, Bash, Grep, Glob`, `color: magenta`).
2. **Inputs** (prompt contract): list of changed files + optional `diff_range` + resolved RULES paths.
3. **Algorithm:** (a) read RULES.md (proj + global); (b) for each changed file — apply checks: SRP (line count threshold per RULES), ISP (interface>5 methods), DIP (constructor type hints / Go interfaces), Clean Arch (layer-crossing imports derived from `codebase/ARCHITECTURE.md` if present), DRY (>2 identical 3-line blocks via `grep -c` across diff); (c) TDD delta (source changed without matching test in same commit range).
4. **Output contract:** strict JSON to stdout + human summary. Schema: `{violations: [{rule, severity: "CRITICAL|WARNING|INFO", file, line, excerpt, rationale}], stats: {files_scanned, checks_run, duration_ms}}`. JSON-first enables machine composition.
5. Update `commands/review.md` — replace inline "Principles analysis" section (stages 2-3) with an `Agent(... mb-rules-enforcer ...)` invocation. Keep tests/security/plan-alignment sections inline (different concern).
6. Update `SKILL.md` Agents table + `AGENTS.md` routing.

**Testing (TDD):**
- **Unit (shell):** `tests/agents/test_rules_enforcer_srp.sh` — fixture file 350 lines → expects SRP CRITICAL; 250 lines → no violation.
- **Unit (shell):** `tests/agents/test_rules_enforcer_clean_arch.sh` — fixture `src/domain/user.py` with `from src.infrastructure.db import X` → CRITICAL with rule=`clean_arch/direction`.
- **Unit (shell):** `tests/agents/test_rules_enforcer_tdd.sh` — diff changes `src/foo.py` and no `tests/test_foo.py` touched → CRITICAL; if file matches `tdd_exceptions` (docs, migrations) → skip.
- **Integration:** `tests/agents/test_rules_enforcer_review_integration.sh` — runs `/review` fixture, asserts main-agent prompt no longer contains SOLID inline checklist (delegation works).
- **Contract test:** JSON output validated against schema (`jq` stub assertions).

**DoD (SMART):**
- [ ] `agents/mb-rules-enforcer.md` exists with frontmatter + all 5 rule categories documented
- [ ] JSON output schema documented in the prompt (copy-paste-verifiable example)
- [ ] 4 test files pass; all run in <10s total
- [ ] `commands/review.md` diff shows ≥40 lines removed from inline rules + 1 Agent() block added
- [ ] `SKILL.md` Agents table lists `mb-rules-enforcer` with 1-line invocation hint
- [ ] Manual smoke on this repo (`/review` on current diff) produces the same or more findings than pre-refactor baseline (record baseline before Stage 2 start in a note)
- [ ] Complete within ≤6h; if blocked on RULES.md parsing corner cases, degrade to grep-only and defer AST to Stage 2b

**Code rules:** SOLID (ISP — prompt exposes only what the caller needs; each rule has a single responsibility block), DRY (share common file-reading helpers via `_lib.sh`), KISS (grep/shellcheck patterns first; no AST parsing in v1)

---

<!-- mb-stage:3 -->
### Stage 3: new subagent — mb-test-runner

**Why now:** `plan-verifier` (Stage 1) and `/test` both need "run tests + parse output" logic. Extracting removes duplication + makes output structured for any downstream agent.

**What to do:**
1. Create `agents/mb-test-runner.md` (frontmatter: `tools: Bash, Read, Grep`, `color: green`).
2. **Algorithm:** (a) call `mb-metrics.sh --run` to detect stack + run tests; (b) parse coverage from stack-specific output (pytest `coverage.xml`, `go -coverprofile`, `jest --coverage --json`); (c) identify failing tests (file + name + first 10 lines of error); (d) correlate failures with `git diff --name-only` (which failures touch files changed in this session).
3. **Output contract:** JSON `{stack, tests_pass: bool, tests_total, tests_failed, coverage: {overall, per_file}, failures: [{file, name, error_head, likely_cause}], duration_ms}` + human summary.
4. Update `commands/test.md` — replace inline flow with `Agent(... mb-test-runner ...)`.
5. Update `plan-verifier.md` Step 3.5 to delegate to `mb-test-runner` (instead of parsing `mb-metrics.sh` output directly) — thin composition.
6. Add `AGENTS.md` and `SKILL.md` entries.

**Testing (TDD):**
- **Unit (shell):** `tests/agents/test_runner_python.sh` — fixture pytest project (1 pass, 1 fail), asserts `tests_pass=false, tests_failed=1, failure[0].file=*`.
- **Unit (shell):** `tests/agents/test_runner_go.sh` — fixture Go pkg, same contract.
- **Integration:** `tests/agents/test_runner_plan_verifier_delegation.sh` — patched `plan-verifier` calls `mb-test-runner`, asserts it does NOT also call `mb-metrics.sh --run` directly (no double-run).
- **Edge:** no test infra detected → output `{stack: unknown, tests_pass: null, tests_total: 0}` + human "skipped: no runner" (NOT false=pass).

**DoD (SMART):**
- [ ] `agents/mb-test-runner.md` exists with deterministic JSON schema + example per stack (python/go/node)
- [ ] 3 test files pass
- [ ] `commands/test.md` inline flow replaced with Agent() block; diff shows net -20 lines or more
- [ ] `plan-verifier` updated to call `mb-test-runner` (grep for "Agent.*mb-test-runner" in `agents/plan-verifier.md` ≥ 1)
- [ ] Manual run `/mb verify` on a real plan in this repo — test results section populated with structured JSON excerpt
- [ ] Zero regression: `bash tests/agents/test_plan_verifier_tests.sh` still passes after delegation refactor
- [ ] Complete within ≤5h

**Code rules:** SRP (runner doesn't evaluate gates; it reports facts), DIP (depends on `mb-metrics.sh` abstraction, not on pytest/go directly), YAGNI (no coverage-trend tracking v1)

---

<!-- mb-stage:4 -->
### Stage 4: mb-codebase-mapper — consume graph.json

**Why now:** `graph.json` already exists (`/mb graph --apply`). Integration is pure refactor — no new infra. Mapper upgrades immediately sharpen CONVENTIONS/CONCERNS accuracy on Python/Go/JS/TS projects.

**What to do:**
1. Update `agents/mb-codebase-mapper.md` **Step 2 `explore_by_focus`** — add a precondition: `if .memory-bank/codebase/graph.json exists AND not older than 24h → read it first; use grep only to fill gaps`.
2. For **CONVENTIONS:** derive naming patterns from `graph.json` node `name` field (snake_case vs camelCase counts). Replace brittle file-content scan.
3. For **CONCERNS:** derive god-nodes (degree > threshold, e.g., 20) directly from graph instead of `wc -l | sort` file-size heuristic — already `/mb graph` produces `god-nodes.md`, read that.
4. Add graceful degradation: if `graph.json` is missing or stale, fall back to current grep/find flow + mention in output header "graph: not-used (missing/stale)".
5. Add "Generated: YYYY-MM-DD HH:MM" to template headers via `$(date -u +%FT%TZ)` in the Write payload (no longer hand-typed).

**Testing (TDD):**
- **Unit (shell):** `tests/agents/test_mapper_graph_present.sh` — fixture `codebase/graph.json` with 3 god-nodes, mapper run on focus=concerns → `CONCERNS.md` names them correctly.
- **Unit (shell):** `tests/agents/test_mapper_graph_missing.sh` — no graph.json → mapper falls back to grep + output contains `graph: not-used`.
- **Unit (shell):** `tests/agents/test_mapper_graph_stale.sh` — graph.json mtime 7 days old → same as missing.

**DoD (SMART):**
- [ ] `agents/mb-codebase-mapper.md` has explicit "Use graph.json if present" step before grep
- [ ] Fallback path documented; no hard error on missing graph
- [ ] 3 test files pass
- [ ] Dogfooding: run `/mb map concerns` on this repo post-patch — output references god-nodes from `.memory-bank/codebase/god-nodes.md` by name (≥ 3 matches)
- [ ] Complete within ≤3h (scope-controlled refactor)

**Code rules:** KISS (2 code paths: graph vs grep, clean switch; no polymorphism needed), YAGNI (don't build a graph query DSL — read JSON lines and filter)

---

<!-- mb-stage:5 -->
### Stage 5: mb-doctor — RESEARCH↔experiments drift + index.json auto-regen + git safety

**Why now:** doctor is already the most mature agent; these are surgical additions, not redesign. Ship after Stage 1-3 so that test-runner + rules-enforcer can be referenced from doctor checks if needed.

**What to do:**
1. Add **Step 2.8: `research.md` ↔ `experiments/` cross-check** — for every `H-NNN` with status `✅ Confirmed`/`❌ Refuted`, require matching `experiments/EXP-NNN.md`. Report as INCONSISTENCY if missing.
2. Add **Step 4.5: regenerate `index.json`** — if any of the changed files is under `notes/` or `lessons.md` or `plans/` was touched, run `python3 ~/.claude/skills/memory-bank/scripts/mb-index-json.py .memory-bank` and report `index_regenerated=true|false` in summary.
3. Add **Step 3.5 (git safety):** before applying ANY Edit fix, emit `## Pre-fix git state` in the report showing `git rev-parse HEAD` + `git status --short`. Recommend (not force) `git stash` if the working tree is dirty. If env `MB_DOCTOR_REQUIRE_CLEAN_TREE=1`, refuse to auto-fix when dirty.
4. Update "WARNING vs auto-fix" boundary: add explicit criteria — auto-fix allowed when (a) source-of-truth chain resolves the conflict deterministically AND (b) the fix is representable as `mb-plan-sync.sh`/`mb-plan-done.sh`/`mb-index-json.py` OR a single-line Edit. Otherwise → WARNING.

**Testing (TDD):**
- **Unit (shell):** `tests/agents/test_doctor_research_drift.sh` — fixture `research.md` with H-001 Confirmed but no `experiments/EXP-001.md` → INCONSISTENCY row.
- **Unit (shell):** `tests/agents/test_doctor_index_regen.sh` — fixture where doctor touches a `notes/*.md` → `index.json` regenerated (compare timestamps pre/post).
- **Unit (shell):** `tests/agents/test_doctor_git_safety.sh` — dirty tree + `MB_DOCTOR_REQUIRE_CLEAN_TREE=1` → refuses auto-fix, emits actionable message.

**DoD (SMART):**
- [ ] All 3 test files pass
- [ ] `agents/mb-doctor.md` sections Step 2.8, 3.5, 4.5 present and numbered cleanly
- [ ] Doctor report sample in `agents/mb-doctor.md` shows the new rows
- [ ] Run `/mb doctor` on this repo — report contains `index_regenerated=true|false` line, with 0 false positives for RESEARCH/experiments
- [ ] Complete within ≤3h

**Code rules:** SRP (each added Step maps to one check, zero overlap with existing ones), Fail-Fast (git safety refuses when risky, doesn't hope)

---

<!-- mb-stage:6 -->
### Stage 6: mb-manager — explicit `action: done` + dedupe tail + conflict resolution

**Why now:** deferred to after gates (verifier/rules/tests) are solid so that `action: done` can delegate to them cleanly rather than bundling inline.

**What to do:**
1. Add `### action: done` section to `agents/mb-manager.md` explicitly documenting the actualize+note+session-lock flow (was "combined flow" — now first-class).
2. Document **actualize conflict resolution:** when `status.md` metrics disagree with `mb-metrics.sh --run` output, trust the script; when `checklist.md` disagrees with a closed plan in `plans/done/`, trust checklist (plans are historic after done).
3. Remove remaining minor duplication in templates section (currently 2 `lessons.md` templates shown under different wrappers).
4. Reorder sections so **Rules** appears BEFORE **Actions** (rules are read-once, actions are read-on-dispatch).
5. Update `commands/done.md` → replace "combined flow of action: actualize + action: note" wording with `action: done`.

**Testing (TDD):**
- **Contract (shell):** `tests/agents/test_manager_action_done.sh` — grep the prompt: `action: done` section exists, references `.session-lock`, calls `mb-note.sh` + `mb-index-json.py`.
- **Regression:** `tests/agents/test_manager_existing_actions.sh` — context/search/note/actualize/tasks sections all still present and parse.

**DoD (SMART):**
- [ ] `action: done` section exists with 6-step flow
- [ ] Conflict-resolution subsection lists 3+ concrete conflict rules
- [ ] `commands/done.md` updated (grep for "action: done" ≥ 1)
- [ ] 2 test files pass
- [ ] Complete within ≤2h

**Code rules:** DRY (extract common "touch session-lock" logic to `action: done`), KISS

---

<!-- mb-stage:7 -->
### Stage 7 (OPTIONAL, behind MB_ENABLE_RECOVERER=1): mb-session-recoverer

**Ship only if:** after Stages 1-6, telemetry or manual observation shows `/catchup` is genuinely insufficient for MBs > 100 notes. Otherwise defer to v3.2.

**What to do:**
1. Create `agents/mb-session-recoverer.md` — reads `status.md` + `roadmap.md` + top-20 most-recently-modified notes + last 3 `progress.md` sections, emits compressed context (≤40 lines).
2. Feature-flag: `commands/catchup.md` invokes recoverer only if `MB_ENABLE_RECOVERER=1`; else keeps current trivial dispatch.
3. Measure: add a 1-line telemetry print (`recoverer_used=true N=<notes>`) to `.memory-bank/.telemetry.log`.

**Testing:** `tests/agents/test_recoverer_selection.sh` — 150-note fixture, recoverer output ≤40 lines, references the 5 "most-relevant" notes (judged by mtime + tag overlap with active plan).

**DoD (SMART):**
- [ ] Agent file + frontmatter
- [ ] Feature flag wired in `commands/catchup.md`
- [ ] Test passes
- [ ] Note in `lessons.md` explaining decision (shipped / deferred) + reasoning
- [ ] Complete within ≤4h

**Code rules:** YAGNI (feature-flagged — justify shipping with real data, not hypothesis)

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Test-runner flaky on diverse stacks (pytest / go test / jest / cargo) | H | Ship python + go first (Stage 3a); JS/Rust as Stage 3b. Don't block on universal support. |
| Rules-enforcer false positives on false SRP triggers (generated files) | M | Support `rules-ignore` globs in `.memory-bank/RULES.md` frontmatter; document it in Stage 2 DoD |
| `plan-verifier` baseline-ref lookup fails on shallow clones | M | Fallback to `HEAD~10` with explicit warning in report; document in Stage 1 |
| mb-codebase-mapper `graph.json` staleness check arbitrary (24h) | L | Make threshold configurable via env `MB_GRAPH_STALE_HOURS`, default 24 |
| Doctor auto-fix makes wrong call during git-dirty state | M | Stage 5 Step 3.5 + `MB_DOCTOR_REQUIRE_CLEAN_TREE` env + default to report-only if uncertain |
| Subagent prompt bloat (JSON schemas in every prompt) | L | Use references/subagent-io-schemas.md with links; don't inline full JSON schema in every agent prompt |
| Breaking `/review` or `/test` for existing users | M | Keep legacy inline flow behind env `MB_LEGACY_COMMANDS=1` for 1 minor release; remove in next major |
| Scope creep — adding Stage 7 prematurely | M | Stage 7 gated on observed pain; default decision is "defer" |

## Gate (plan success criterion)

All of:
1. Stages 1-6 all DoD items ✅ (Stage 7 outcome = either ✅ or explicit "deferred with reasoning")
2. `bash tests/agents/run_all.sh` exits 0 on CI matrix (python + go fixtures at minimum)
3. `/mb verify` on this plan — PASS verdict + test section populated (runs `mb-test-runner` — self-hosting check)
4. `/review` on the final diff via `mb-rules-enforcer` — 0 CRITICAL; all WARNINGs acknowledged in `lessons.md`
5. `SKILL.md` Agents table lists all 6 shipped agents (4 existing + 2 new) with correct invocation hints
6. CHANGELOG v3.2.0 entry written, bullets map 1:1 to stages 1-6 outcomes
7. Dogfooding: running this repo's `/mb start` + `/mb map` produces sharper docs (≥10% more file paths in CONVENTIONS.md vs pre-Stage-4 baseline — measured via `grep -c '\`' codebase/CONVENTIONS.md`)
