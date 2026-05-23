---
type: spec-tasks
topic: goal-driven-autopilot
status: ready
created: 2026-05-23
linked_design: design.md
linked_requirements: requirements.md
---

# Tasks: Goal-driven autopilot

Executable task list for `/mb work`. Each `<!-- mb-task:N -->` block is
an atomic unit. `Covers:` links to REQs in `requirements.md`.

Tasks are grouped by Sprint. Sprint plan files (one per group) live in
`.memory-bank/plans/` and reference these task blocks.

---

## Sprint 1 — Prompt overlay + addons (Component C7)

<!-- mb-task:1 -->
### Task 1: Build `scripts/mb-agent-resolve.sh`

**Covers:** REQ-070, REQ-073

**Actions:**
- New script that takes `<role>` and resolves prompt file in precedence
  order: user-global → project → skill-base.
- Use `mb_resolve_path` helper from `scripts/_lib.sh` for project bank.
- Print the resolved path to stdout; non-zero exit if no match found.
- Honour `MB_AGENT_OVERLAY_ROOT` env override for testing.

**Testing (TDD):**
- bats: precedence order — base → adds project → adds user → user wins.
- bats: missing role returns non-zero, prints to stderr.
- bats: env override redirects user-global root.

**DoD:**
- [ ] Script passes shellcheck.
- [ ] All three precedence cases tested green.
- [ ] Returns byte-identical skill-base path when no overlay exists.

<!-- mb-task:2 -->
### Task 2: Create initial addon set under `agents/addons/`

**Covers:** REQ-071, REQ-072

**Actions:**
- `agents/addons/defensive.md` — isolation reminder.
- `agents/addons/scope-lock.md` — no scope creep, no new deps.
- `agents/addons/fail-loudly.md` — explicit blockers, no fabrication.
- `agents/addons/read-before-write.md` — verify before referencing.
- Each addon ≤ 250 tokens. Headers `# Addon: <name>` for clarity.

**Testing (TDD):**
- pytest: each addon file exists, length under cap, no `TODO`/`TBD`.
- pytest: catalog `agents/addons/index.json` lists every shipped addon.

**DoD:**
- [ ] Four addons present and validated by tests.
- [ ] `agents/addons/index.json` generated and committed.
- [ ] Each addon under 250 tokens.

<!-- mb-task:3 -->
### Task 3: Extend `pipeline.yaml` schema for `agents.preamble_addons`

**Covers:** REQ-002, REQ-003, REQ-071, REQ-072

**Actions:**
- Add `agents.preamble_addons: []` to `references/pipeline.default.yaml`
  with comment example listing the four shipped addons.
- Extend `scripts/mb-pipeline-validate.sh` to accept the new field;
  validates it as `list[str]` of known addon names.
- Unknown addon names → validator emits `[validate] agents.preamble_addons: unknown 'X'`.

**Testing (TDD):**
- bats: valid empty array → exit 0.
- bats: valid array of known addons → exit 0.
- bats: unknown addon name → exit 1 with descriptive message.
- bats: non-array value → exit 1.

**DoD:**
- [ ] Validator accepts known addons, rejects unknown.
- [ ] `pipeline.default.yaml` updated with commented example.
- [ ] All bats tests green.

<!-- mb-task:4 -->
### Task 4: Update `/mb work` dispatch to use resolver + addons

**Covers:** REQ-001, REQ-071, REQ-073

**Actions:**
- In `commands/work.md` dispatch step 3a, replace direct read of
  `agents/<agent>.md` with `mb-agent-resolve.sh` + prepended addons.
- Build prompt: `\n\n`.join(addon contents) + `\n\n---\n\n` +
  resolved agent prompt + stage context.
- Empty `preamble_addons` and no overlay → byte-identical to today.

**Testing (TDD):**
- pytest: golden-snapshot test — empty config + skill-base agent →
  prompt matches recorded pre-spec snapshot byte-for-byte.
- pytest: with `preamble_addons: [defensive]` → prompt starts with
  defensive addon content.
- pytest: with project overlay present → resolver picks overlay.

**DoD:**
- [ ] Golden snapshot test confirms baseline preservation.
- [ ] Addon-prepended dispatch verified by integration test.
- [ ] Overlay precedence verified end-to-end.

<!-- mb-task:5 -->
### Task 5: Documentation — overlay system

**Covers:** REQ-080

**Actions:**
- Write `docs/concepts/overlay-system.md` — explains resolver
  precedence, addon catalogue, examples.
- Link from `docs/README.md` (slot reserved).
- Add example `pipeline.yaml` snippet to existing
  `docs/concepts/overview.md` if natural.

**Testing (doc-quality):**
- pytest: file exists, ≤ 300 lines, no `(coming)`/`TBD`/`TODO` markers.
- pytest: code blocks parse as valid YAML where they look like YAML.
- pytest: cross-link from `docs/README.md` resolves.

**DoD:**
- [ ] `docs/concepts/overlay-system.md` exists, ≤ 300 lines, examples
      copy-pasteable.
- [ ] `docs/README.md` links updated (no broken refs).

---

## Sprint 2 — `mb-debugger` agent + `/mb debug` command (Component C3)

<!-- mb-task:6 -->
### Task 6: Write `agents/mb-debugger.md` prompt

**Covers:** REQ-030, REQ-031, REQ-032, REQ-033

**Actions:**
- Prompt structure: defensive + scope-lock + fail-loudly addons baked
  in (debugger is highest fabrication risk).
- Output schema documented inline with example.
- Verdict rules: fixable/high → auto-apply; medium → context-dependent;
  low / needs-human / abandon → halt.

**Testing (TDD):**
- pytest: prompt file parses YAML frontmatter cleanly.
- pytest: required sections present (Input, Output schema, Verdict
  rules).
- pytest: lint passes (no `TODO`, no placeholder).

**DoD:**
- [ ] `agents/mb-debugger.md` shipped with full schema description.
- [ ] Prompt under 4k tokens.

<!-- mb-task:7 -->
### Task 7: Build `scripts/mb-debugger-parse.sh`

**Covers:** REQ-031, EDGE-005

**Actions:**
- Read mb-debugger stdout, validate JSON against schema (verdict
  enum, fix_plan array shape, confidence enum).
- Exit 0 on valid; exit 1 with reason on invalid; exit 2 on missing
  required keys.
- Unknown verdict → exit 1 with "unknown verdict X" message.

**Testing (TDD):**
- bats: valid fixable/high JSON → exit 0.
- bats: missing `verdict` → exit 2.
- bats: unknown verdict value → exit 1.
- bats: malformed JSON → exit 1.

**DoD:**
- [ ] Parser handles all 4 verdicts and 3 confidence levels.
- [ ] bats coverage of malformed inputs green.

<!-- mb-task:8 -->
### Task 8: Build `commands/debug.md`

**Covers:** REQ-035

**Actions:**
- Implement `/mb debug` flags: `--stage`, `--test`, `--file`, `--apply`,
  `--dry-run`.
- Dry-run mode produces fix-plan only, no Write or re-dispatch.
- Persist fix-plan to `.memory-bank/notes/debug-<ts>-<slug>.md`.

**Testing (TDD):**
- bats: `/mb debug --dry-run` does not modify files.
- bats: `/mb debug --apply` triggers implementer dispatch (mocked).
- pytest: persisted note has valid frontmatter and is indexed.

**DoD:**
- [ ] All flag combinations tested.
- [ ] Persisted notes appear in `mb-index.sh` output.

<!-- mb-task:9 -->
### Task 9: Extend `pipeline.yaml` schema for `agents.debugger.*`

**Covers:** REQ-030, REQ-034

**Actions:**
- Add `agents.debugger.{enabled, auto_on_fail, max_cycles, on_max_cycles, require_confidence}` to default config.
- Extend validator: enum checks for `on_max_cycles` and
  `require_confidence`; integer check for `max_cycles`.

**Testing (TDD):**
- bats: valid config accepted; invalid enums rejected with messages.
- bats: `max_cycles=0` rejected (must be ≥ 1).

**DoD:**
- [ ] All new keys documented in `references/pipeline.default.yaml`.
- [ ] Validator coverage green.

<!-- mb-task:10 -->
### Task 10: Integrate `/mb work` auto-trigger on verify FAIL

**Covers:** REQ-030, REQ-032, REQ-033, REQ-034

**Actions:**
- Extend `/mb work` step 3f: after FAIL verify, if
  `agents.debugger.enabled && auto_on_fail` → dispatch mb-debugger,
  parse, apply verdict gating.
- Cycle counter persisted in session state file.
- `on_max_cycles` enforced as documented.

**Testing (TDD):**
- pytest e2e: mocked verifier FAIL → debugger called → high
  confidence fixable → implementer re-dispatched.
- pytest e2e: low confidence → loop halts, fix-plan surfaced.
- pytest: max_cycles exhausted → halt regardless of verdict.

**DoD:**
- [ ] All three e2e flows green.
- [ ] Session state file documented and gitignored.

<!-- mb-task:11 -->
### Task 11: Documentation — debugging workflow

**Covers:** REQ-080

**Actions:**
- `docs/workflows/debugging.md` and `docs/commands/debug.md`.
- Link from `docs/README.md`.

**Testing (doc-quality):**
- pytest: both files exist, ≤ 300 lines each, no `(coming)`/`TBD` markers.
- pytest: cross-links from `docs/README.md` resolve.

**DoD:**
- [ ] Both docs shipped, ≤ 300 lines each.

---

## Sprint 3 — Worktree isolation (Component C2)

<!-- mb-task:12 -->
### Task 12: Build `scripts/mb-work-worktree.sh`

**Covers:** REQ-020, REQ-021, REQ-022, REQ-023, EDGE-002, EDGE-003

**Actions:**
- Subcommands: `ensure`, `status`, `path`, `remove`, `clean`.
- `ensure` creates branch `mb-work/<slug>` from HEAD and worktree
  under `~/.cache/memory-bank/worktrees/<project-hash>/<plan-slug>/`.
- Safety refusals for detached HEAD, dirty tree, unmerged branch
  without `--reuse` / `--force`.

**Testing (TDD):**
- bats: ensure creates worktree and branch on clean repo.
- bats: ensure refuses with dirty tree, accepts with `--force`.
- bats: ensure reuses existing fully-merged branch.
- bats: ensure refuses unmerged branch without `--reuse`.
- bats: `status` lists current worktrees.
- bats: `clean --all` removes only stale entries.

**DoD:**
- [ ] All bats scenarios green.
- [ ] Script handles Linux + macOS path semantics.

<!-- mb-task:13 -->
### Task 13: Extend `pipeline.yaml` schema for `execution.use_worktree`

**Covers:** REQ-020, REQ-021

**Actions:**
- Add `execution.use_worktree` (enum off/auto/always) and
  `execution.worktree_cleanup` (enum keep/merge/prompt) to defaults.
- Validator enforces enum values.

**Testing (TDD):**
- bats: each enum value accepted; invalid rejected.

**DoD:**
- [ ] Validator coverage green.
- [ ] `pipeline.default.yaml` annotated with comments per value.

<!-- mb-task:14 -->
### Task 14: Wire `/mb work` into worktree mode

**Covers:** REQ-020, REQ-021, REQ-023

**Actions:**
- In `commands/work.md`, before dispatch step 3a, call
  `mb-work-worktree.sh ensure` when applicable; export
  `MB_WORK_CWD=<worktree-path>` for downstream steps.
- All Task dispatches set CWD to `MB_WORK_CWD` when set.
- `/mb done` triggers cleanup per `worktree_cleanup`.

**Testing (TDD):**
- pytest e2e: `use_worktree=always` → all dispatches CWD'd to
  worktree.
- pytest e2e: `use_worktree=auto` + `--autopilot` → worktree created;
  `auto` + non-autopilot → no worktree.

**DoD:**
- [ ] e2e flows green.
- [ ] Cleanup behaviour matches `worktree_cleanup` enum.

<!-- mb-task:15 -->
### Task 15: Documentation — worktree isolation

**Covers:** REQ-080

**Actions:**
- `docs/features/worktree-isolation.md` — usage, cleanup, troubleshoot.

**Testing (doc-quality):**
- pytest: file exists, ≤ 300 lines, no `(coming)`/`TBD` markers.
- pytest: cross-link from `docs/README.md` resolves.

**DoD:**
- [ ] Doc shipped, examples copy-pasteable.

---

## Sprint 4 — Atomic commit per stage (Component C5)

<!-- mb-task:16 -->
### Task 16: Template renderer + stage SHA snapshot

**Covers:** REQ-050

**Actions:**
- New helper `scripts/mb-commit-render.sh` renders mustache-like
  variables (`{{role}}`, `{{plan_slug}}`, `{{heading}}`, etc.) from
  pipeline.yaml templates.
- Capture stage-start SHA in session state at step 3a of `/mb work`.

**Testing (TDD):**
- bats: renderer substitutes known vars, leaves unknown intact.
- bats: SHA captured before any subagent dispatch.

**DoD:**
- [ ] Renderer covered for all standard placeholders.
- [ ] Session state schema documented.

<!-- mb-task:17 -->
### Task 17: Reuse 4 safety gates from `mb-auto-commit.sh`

**Covers:** REQ-051, REQ-052

**Actions:**
- Extract shared gate library `scripts/mb-commit-gates.sh`.
- Gate 1: pre-stage clean state. Gate 2: protected paths (reuses
  `mb-work-protected-check.sh`). Gate 3: private content scan.
  Gate 4: tests pass (implicit, after verify PASS).

**Testing (TDD):**
- bats: gate 1 fails session-disable on dirty start.
- bats: gate 3 refuses commit with `<private>` content in staged
  files.
- pytest: gate library reused by both `mb-auto-commit.sh` and the new
  atomic-commit step.

**DoD:**
- [ ] Both callers use the shared library.
- [ ] No code duplication between the two commit flows.

<!-- mb-task:18 -->
### Task 18: Integrate atomic commit into `/mb work` step 3g

**Covers:** REQ-050, REQ-053

**Actions:**
- After verify PASS, if `execution.auto_commit_code: stage`, compute
  `git diff --name-only $STAGE_START_SHA` and create commit using
  rendered template.
- Empty diff → skip commit, log "no changes committed".
- Re-running same stage idempotent.

**Testing (TDD):**
- pytest e2e: PASS stage produces exactly one commit with expected
  trailers.
- pytest e2e: empty-diff stage skips commit without error.
- pytest e2e: FAIL stage produces no commit.

**DoD:**
- [ ] All three e2e flows green.

<!-- mb-task:19 -->
### Task 19: Extend `pipeline.yaml` schema for atomic commit

**Covers:** REQ-050

**Actions:**
- Add `execution.auto_commit_code` (enum off/stage),
  `execution.commit_message_template` (string), `execution.commit_trailer`
  (string) with sensible defaults.

**Testing (TDD):**
- bats: enum values accepted/rejected; template strings allowed
  multi-line.

**DoD:**
- [ ] Validator and defaults updated.

<!-- mb-task:20 -->
### Task 20: Documentation — atomic commit

**Covers:** REQ-080

**Actions:**
- `docs/features/atomic-commit.md` — template variables, safety gates,
  recovery story.

**Testing (doc-quality):**
- pytest: file exists, ≤ 300 lines, no `(coming)`/`TBD` markers.
- pytest: cross-link from `docs/README.md` resolves.

**DoD:**
- [ ] Doc shipped.

---

## Sprint 5 — Parallel waves (DAG) (Component C4)

<!-- mb-task:21 -->
### Task 21: Extend marker parser with `depends_on`

**Covers:** REQ-040, REQ-041

**Actions:**
- Extend `scripts/mb_work_items.py` to parse
  `<!-- mb-stage:N depends_on:[1,2] -->` and
  `<!-- mb-task:N depends_on:[1] -->` (and existing markers without
  the suffix).
- Validate references on parse (cycle / forward-reference detection).

**Testing (TDD):**
- pytest: legacy markers parse with `depends_on=[]`.
- pytest: new markers parse with correct dep lists.
- pytest: cycle in deps → ParseError with cycle path.
- pytest: forward reference → ParseError.

**DoD:**
- [ ] Parser handles old + new markers.
- [ ] All error paths covered.

<!-- mb-task:22 -->
### Task 22: Build `scripts/mb-work-dag.sh`

**Covers:** REQ-040, REQ-041

**Actions:**
- Wraps Python parser, outputs ASCII visualisation + JSON waves.
- Non-zero exit on cycle / forward reference with descriptive stderr.

**Testing (TDD):**
- bats: valid DAG → exit 0, ASCII + JSON on stdout.
- bats: cycle → exit 1 with cycle description.

**DoD:**
- [ ] Both modes (ASCII + JSON) green.

<!-- mb-task:23 -->
### Task 23: Extend `mb-work-plan.sh` JSON Lines with `wave`

**Covers:** REQ-040

**Actions:**
- Compute wave number per item via topological longest-path.
- Add `wave` field to JSON Lines schema (documented in
  `commands/work.md` already; ensure docs match implementation).

**Testing (TDD):**
- pytest: linear plan → wave numbers monotonically increasing.
- pytest: diamond DAG → middle layer gets wave 1, sink wave 2.

**DoD:**
- [ ] `wave` field present in every emitted item.

<!-- mb-task:24 -->
### Task 24: `/mb work --parallel` dispatch + file-conflict guard

**Covers:** REQ-040, REQ-042, EDGE-006

**Actions:**
- Add `--parallel` / `--no-parallel` flags.
- In parallel mode, group items by wave; dispatch all items in a wave
  as one Task message.
- Pre-wave overlap check (scan DoD/Covers for file mentions) → warn,
  auto-decline in `--auto`.
- Per-item post-snapshot via `git diff --name-only`; surface collisions
  in end-of-wave summary.

**Testing (TDD):**
- pytest e2e: 3-item wave dispatches in one message (mock).
- pytest: overlap warning logged when DoDs mention same file.
- pytest: end-of-wave summary lists collisions when present.

**DoD:**
- [ ] Wave dispatch verified.
- [ ] Conflict guard surfaces correctly without halting wave (warn-only).

<!-- mb-task:25 -->
### Task 25: Budget-aware sequential fallback

**Covers:** REQ-043

**Actions:**
- Before each wave, compute `estimated_wave_cost = sum(15k * (1 + dod_lines/10))`.
- If `mb-work-budget.sh status` shows remaining < estimate → fall
  back to sequential for that wave.
- Log fallback with `[budget-fallback] wave N` line.

**Testing (TDD):**
- pytest: budget below threshold → sequential fallback chosen.
- pytest: budget above threshold → parallel dispatch chosen.

**DoD:**
- [ ] Fallback path verified.

<!-- mb-task:26 -->
### Task 26: `pipeline.yaml` schema for parallel waves

**Covers:** REQ-040, REQ-042

**Actions:**
- Add `execution.parallel_waves` (enum off/explicit/auto) and
  `execution.on_wave_failure` (enum stop_for_human/continue_with_warning).

**Testing (TDD):**
- bats: enum validation.

**DoD:**
- [ ] Validator green.

<!-- mb-task:27 -->
### Task 27: Documentation — parallel waves

**Covers:** REQ-080

**Actions:**
- `docs/features/parallel-waves.md` — `depends_on` syntax, file-conflict
  guard, budget fallback.

**Testing (doc-quality):**
- pytest: file exists, ≤ 300 lines, no `(coming)`/`TBD` markers.
- pytest: cross-link from `docs/README.md` resolves.

**DoD:**
- [ ] Doc shipped.

---

## Sprint 6 — Goal layer + `/goal` (Component C1)

<!-- mb-task:28 -->
### Task 28: Build `scripts/mb-goal.sh`

**Covers:** REQ-011, REQ-012, REQ-013, REQ-014, REQ-015

**Actions:**
- Subcommands: `init`, `set`, `done`, `list`, `status`, `refresh`.
- `init` runs the 5–6 question interactive flow (see Task 30).
- `status` reads `goal.md` only, computes `%` from `progress_source`.
- `done` archives goal to `goals/done/<id>-<slug>.md` and appends to
  `progress.md`.

**Testing (TDD):**
- bats: `set "<desc>"` creates `goal.md` with active status.
- bats: `done` archives correctly and updates progress.md.
- bats: `status` reports correct % from checklist source.
- bats: empty goal.md activates `/goal` with hint, exits 0.

**DoD:**
- [ ] All subcommands tested.
- [ ] Computed progress logic verified against checklist.

<!-- mb-task:29 -->
### Task 29: Build `commands/goal.md`

**Covers:** REQ-010, REQ-012, REQ-013, REQ-015

**Actions:**
- Dispatcher mirroring `/mb` style: routes to `mb-goal.sh` subcommands.
- Help mode with `/goal help`.

**Testing (TDD):**
- bats: each subcommand reachable through `/goal`.
- bats: unknown subcommand prints help.

**DoD:**
- [ ] Help text complete, examples included.

<!-- mb-task:30 -->
### Task 30: `/goal init` interactive question flow

**Covers:** REQ-010, REQ-011, EDGE-001

**Actions:**
- 6 questions: mission, conventions, architecture constraints, stack
  notes, out-of-scope, active goal (last optional if goal.md exists).
- Pre-fill mission from README first paragraph if present.
- Pre-fill Stack from `codebase/STACK.md` if present, manual otherwise.
- Skip → `<TBD — fill manually>` marker, no blocking.

**Testing (TDD):**
- bats: 6 questions in order, skip handled.
- bats: existing goal.md triggers archive prompt before overwrite.
- bats: pre-fill from README works when present.

**DoD:**
- [ ] All 6 questions exercised in tests.
- [ ] Archive prompt verified.

<!-- mb-task:31 -->
### Task 31: `pipeline.yaml` schema for `goals.*`

**Covers:** REQ-013

**Actions:**
- Add `goals.enabled` (bool, default false) and
  `goals.auto_decompose` (bool, default false).
- Validator enforces types.

**Testing (TDD):**
- bats: bool validation.

**DoD:**
- [ ] Validator green.

<!-- mb-task:32 -->
### Task 32: `/mb start` integration — surface active goal

**Covers:** REQ-012

**Actions:**
- When `goals.enabled` and `goal.md` exists, `/mb start` prints one
  line: `Goal: <title> — <progress%>` at top of context summary.
- No-op when disabled.

**Testing (TDD):**
- bats: `/mb start` injects goal line when active.
- bats: `/mb start` unchanged when goals disabled.

**DoD:**
- [ ] One-line summary verified.

<!-- mb-task:33 -->
### Task 33: Documentation — goal-driven workflow

**Covers:** REQ-080

**Actions:**
- `docs/workflows/goal-driven.md`, `docs/commands/goal.md`.

**Testing (doc-quality):**
- pytest: both files exist, ≤ 300 lines each, no `(coming)`/`TBD` markers.
- pytest: cross-links from `docs/README.md` resolve.

**DoD:**
- [ ] Docs shipped.

---

## Sprint 7 — Autopilot (Component C6)

<!-- mb-task:34 -->
### Task 34: Build autopilot driver

**Covers:** REQ-060, REQ-061, REQ-062

**Actions:**
- Either `/mb work --autopilot` flag or separate `commands/autopilot.md`
  — implementer chooses; spec is agnostic.
- Startup checks: `agents.debugger.enabled`, `goal.md` exists and is
  active with `linked_plan`/`linked_spec`.
- Refuse with actionable fix-hint on missing prerequisite.

**Testing (TDD):**
- bats: missing debugger flag → refusal with hint.
- bats: missing goal → refusal with hint.
- pytest e2e: minimal viable autopilot dispatch loop iterates one
  item.

**DoD:**
- [ ] Both refusal paths and happy path tested.

<!-- mb-task:35 -->
### Task 35: Goal-aware loop + iteration counters

**Covers:** REQ-062, REQ-063, REQ-064, REQ-065

**Actions:**
- Loop iterates pending items from linked plan/spec.
- Counter for total iterations and consecutive-no-PASS (stall).
- After each PASS, re-read `goal.md` acceptance; exit if all complete.
- On all-done, call `/goal done` + `/mb done`.

**Testing (TDD):**
- pytest e2e: 3-stage plan runs to completion.
- pytest: `max_iterations=2` halts at limit.
- pytest: `max_stall_iterations=2` halts after 2 cycles without PASS.
- pytest: acceptance fully checked → goal closed automatically.

**DoD:**
- [ ] All four scenarios green.

<!-- mb-task:36 -->
### Task 36: Hard-stop integration

**Covers:** REQ-063, REQ-064, NFR-003

**Actions:**
- Wire existing hard stops: `protected_paths`, `budget`,
  `sprint_context_guard.hard_stop_tokens` apply transparently inside
  autopilot.
- New hard stops: `autopilot.max_iterations`,
  `autopilot.max_stall_iterations`.
- All hard stops surface `[autopilot-halt] reason=<trigger> item=<N>`.

**Testing (TDD):**
- pytest: each hard stop verified independently.
- pytest: surface format consistent.

**DoD:**
- [ ] All 5 hard stops covered.

<!-- mb-task:37 -->
### Task 37: Auto-recovery via mb-debugger inside loop

**Covers:** REQ-030, REQ-032, REQ-033, REQ-034

**Actions:**
- On verify FAIL inside autopilot, dispatch mb-debugger (Sprint 2
  delivered the integration; this task wires the autopilot path).
- Per-stage cycle counter, max_cycles enforced.
- Recovery success → continue loop; halt verdicts → halt loop.

**Testing (TDD):**
- pytest e2e: FAIL → recovered → next stage starts.
- pytest e2e: max_cycles exhausted → halt with reason.

**DoD:**
- [ ] Both e2e flows green.

<!-- mb-task:38 -->
### Task 38: `pipeline.yaml` schema for autopilot

**Covers:** REQ-063, REQ-064

**Actions:**
- Add `execution.autopilot.{max_iterations, max_stall_iterations, cancel_on_goal_change}`.
- Validator enforces integers and bool.

**Testing (TDD):**
- bats: type validation.

**DoD:**
- [ ] Validator green.

<!-- mb-task:39 -->
### Task 39: Documentation — autopilot

**Covers:** REQ-080

**Actions:**
- `docs/workflows/autopilot.md` — prerequisites, hard stops,
  observability, troubleshooting.

**Testing (doc-quality):**
- pytest: file exists, ≤ 300 lines, no `(coming)`/`TBD` markers.
- pytest: cross-link from `docs/README.md` resolves.

**DoD:**
- [ ] Doc shipped.

---

## REQ coverage matrix

Generated by `mb-traceability-gen.sh` (will be regenerated on save).
Every REQ in `requirements.md` must appear in at least one task's
`Covers:`.

| REQ | Tasks |
|-----|-------|
| REQ-001 | implicit; preserved by absence of touch — verified by NFR-002 tests in each sprint |
| REQ-002 | Task 3, Task 4 |
| REQ-003 | (handled by existing `mb-upgrade.sh`; verified by NFR-002) |
| REQ-010 | Task 30 |
| REQ-011 | Task 28, Task 30 |
| REQ-012 | Task 28, Task 29, Task 32 |
| REQ-013 | Task 28, Task 29, Task 31 |
| REQ-014 | Task 28 |
| REQ-015 | Task 28, Task 29 |
| REQ-020 | Task 12, Task 13, Task 14 |
| REQ-021 | Task 12, Task 13, Task 14 |
| REQ-022 | Task 12 |
| REQ-023 | Task 12, Task 14 |
| REQ-030 | Task 6, Task 9, Task 10, Task 37 |
| REQ-031 | Task 6, Task 7 |
| REQ-032 | Task 6, Task 10, Task 37 |
| REQ-033 | Task 6, Task 10, Task 37 |
| REQ-034 | Task 9, Task 10, Task 37 |
| REQ-035 | Task 8 |
| REQ-040 | Task 21, Task 22, Task 23, Task 24, Task 26 |
| REQ-041 | Task 21, Task 22 |
| REQ-042 | Task 24, Task 26 |
| REQ-043 | Task 25 |
| REQ-050 | Task 16, Task 18, Task 19 |
| REQ-051 | Task 17 |
| REQ-052 | Task 17 |
| REQ-053 | Task 18 |
| REQ-060 | Task 34 |
| REQ-061 | Task 34 |
| REQ-062 | Task 34, Task 35 |
| REQ-063 | Task 35, Task 36, Task 38 |
| REQ-064 | Task 35, Task 36, Task 38 |
| REQ-065 | Task 35 |
| REQ-070 | Task 1 |
| REQ-071 | Task 2, Task 3, Task 4 |
| REQ-072 | Task 2, Task 3 |
| REQ-073 | Task 1, Task 4 |
| REQ-080 | Task 5, Task 11, Task 15, Task 20, Task 27, Task 33, Task 39 |
| NFR-001 | covered by golden-snapshot test in Task 4 |
| NFR-002 | covered by golden-snapshot tests across Tasks 4, 10, 14, 18, 24, 32, 35 |
| NFR-003 | Task 36 |
| NFR-004 | covered by `shellcheck` CI step; applies to every new script |
