# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versioning follows [SemVer](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Phase 4 Sprint 2: `--slim`/`--full` end-to-end + sprint_context_guard.**
  Wires the `/mb work --slim` flag from advisory to functional prompt
  trimming, and ships a fifth hook that watches cumulative session
  token spend. New artifacts:
  - `scripts/mb-context-slim.py` — prompt trimmer. Reads the full agent
    prompt from stdin and emits a slim version containing the active
    stage block (extracted between `<!-- mb-stage:N -->` markers in the
    plan) + the DoD bullet list + the plan's `covers_requirements`
    REQ list + (with `--diff`) the `git diff --staged` output. Falls
    back to echoing the input prompt unchanged when the stage marker
    is not present, so a slim mode never breaks the session.
  - `hooks/mb-context-slim-pre-agent.sh` upgraded from Sprint 1's
    advisory-only form. When `MB_WORK_MODE=slim`, it now parses the
    incoming Task `tool_input.prompt` for `Plan: <path.md>` and
    `Stage: <N>` markers, dispatches the trimmer, and emits a JSON
    document on stdout —
    `{"hookSpecificOutput": {"hookEventName": "PreToolUse",
    "additionalContext": "<slim>"}}` — so Claude Code can append the
    trimmed view as orchestrator context without mutating
    `tool_input`. Fail-open semantics throughout.
  - `scripts/mb-session-spend.sh` — companion CLI mirroring
    `mb-work-budget.sh`. Subcommands: `init [--soft N] [--hard N]`,
    `add <chars>`, `status`, `check`, `clear`. State at
    `<bank>/.session-spend.json`. Chars are converted to tokens via
    the standard `chars / 4` estimate. Thresholds default to
    `pipeline.yaml:sprint_context_guard.{soft_warn_tokens,
    hard_stop_tokens}` (150 000 / 190 000).
  - `hooks/mb-sprint-context-guard.sh` — fifth hook, `PreToolUse`
    matched on `Task`. Accumulates the dispatched prompt + description
    char-count per Task invocation, warns at the soft threshold
    (stderr only, dispatch proceeds), and hard-blocks (exit 2) at the
    hard threshold with a recommendation to run `/mb done` +
    `/compact` + `/mb start`. Bank discovery via `MB_SESSION_BANK`
    env or `${PWD}/.memory-bank`; lazy-inits the spend tracker on
    first use.
  - `references/hooks.md` — context-slim section rewritten to reflect
    Sprint 2 behavior; new fifth-hook section for the
    sprint-context-guard; combined `~/.claude/settings.json` snippet
    now wires two hooks to the `Task` matcher.
  - `commands/work.md` — `--slim` / `--full` flag entry now states
    explicitly that the flag exports `MB_WORK_MODE` for the loop
    subshell so the dispatched Task hooks observe it.
  - 32 new pytest cases (9 `test_mb_context_slim.py` + 5
    `test_hook_context_slim_upgrade.py` + 7 `test_mb_session_spend.py`
    + 5 `test_hook_sprint_context_guard.py` + 6
    `test_phase4_sprint2_registration.py`). Total: 552 → 584 passed.

  Phase 4 Sprint 3 will auto-register all five hooks during
  `install.sh` and add a `superpowers:requesting-code-review` skill
  detector that flips the reviewer override declared in
  `pipeline.yaml:roles.reviewer.override_if_skill_present`.

- **Phase 4 Sprint 1: 4 critical hooks (spec §13).**
  Runtime intercept points wired around Claude Code tool calls and
  subagent dispatches. New artifacts:
  - `hooks/mb-protected-paths-guard.sh` — `PreToolUse` (Write/Edit).
    Reads JSON via `jq`, extracts `tool_input.file_path`, delegates
    to `scripts/mb-work-protected-check.sh` for the actual glob match
    against `pipeline.yaml:protected_paths`. Exit 2 (hard block) on
    match unless `MB_ALLOW_PROTECTED=1` is set in the environment.
    Fails open on missing dependencies.
  - `hooks/mb-plan-sync-post-write.sh` — `PostToolUse` (Write). When
    `tool_input.file_path` matches `*plans/*.md` or `*specs/*.md`,
    triggers the deterministic chain
    `mb-plan-sync.sh → mb-roadmap-sync.sh → mb-traceability-gen.sh`.
    Each step is best-effort: missing scripts skipped, non-zero exits
    logged but never blocking. Always exits 0.
  - `hooks/mb-ears-pre-write.sh` — `PreToolUse` (Write). When the
    target is `specs/*/requirements.md` or `context/*.md`, pipes
    `tool_input.content` through `mb-ears-validate.sh -`. Exit 2 with
    the validator's findings on the user's stderr if any REQ line
    fails the EARS regex. Catches manual edits that bypass `/mb sdd`
    or `/mb plan --sdd`.
  - `hooks/mb-context-slim-pre-agent.sh` — `PreToolUse` (Task). When
    `MB_WORK_MODE=slim` is set, emits an advisory note suggesting the
    orchestrator trim the subagent prompt to the active stage + DoD
    + covered REQs + `git diff --staged`. Sprint 2 will upgrade from
    advisory to actual prompt rewrite via JSON `tool_input` output.
  - `references/hooks.md` — installation guide. Per-hook section with
    purpose, event type, matchers, behavior, and a copy-pasteable
    `~/.claude/settings.json` snippet. Combined-snippet section for
    one-shot setup. Operational notes (`jq` requirement, fail-open
    semantics, missing-validator handling). Phase 4 follow-up
    pointers.
  - 35 new pytest cases (6 `test_hook_protected_paths.py` + 5
    `test_hook_plan_sync_post_write.py` + 6
    `test_hook_ears_pre_write.py` + 4 `test_hook_context_slim.py` +
    14 `test_phase4_sprint1_registration.py`). Total: 517 → 552
    passed.

  Phase 4 Sprint 2 will wire the `/mb work --slim` flag to
  `MB_WORK_MODE=slim`, upgrade `mb-context-slim-pre-agent.sh` to
  actually rewrite the prompt, and ship a fifth hook —
  `sprint_context_guard.sh` — that observes session token spend and
  halts at `hard_stop_tokens`. Sprint 3 will auto-register all hooks
  via `install.sh` and add the
  `superpowers:requesting-code-review` skill detector for the
  `pipeline.yaml:roles.reviewer.override_if_skill_present` swap.

- **Phase 3 Sprint 3: review-loop ядро + autopilot hard stops.**
  Closes Phase 3 — `/mb work` is now a full implement → review → fix
  → verify loop. New artifacts:
  - `scripts/mb-work-review-parse.sh` — strict JSON validator for
    reviewer stdout. Schema: `{verdict ∈ {APPROVED,
    CHANGES_REQUESTED}, counts: {blocker, major, minor},
    issues: [{severity, category, file, line, message, fix?}]}`.
    Cross-check: `CHANGES_REQUESTED` requires non-empty issues.
    `--lenient` Markdown fallback for the "verdict: ..." form.
  - `scripts/mb-work-severity-gate.sh` — reads
    `stage_pipeline[step=review].severity_gate` from the effective
    `pipeline.yaml` (override via `--gate <json>`); compares against
    counts via `--counts <json>` or `--counts-stdin`. Exit 0 = PASS,
    1 = FAIL with per-severity breach lines on stderr.
  - `scripts/mb-work-budget.sh` — token budget tracker with
    `init <total> [--warn-at PCT] [--stop-at PCT]`, `add <delta>`,
    `status`, `check`, `clear`. State at `<bank>/.work-budget.json`.
    `check` exit codes: 0 below warn, 1 at/above warn (default 80%),
    2 at/above stop (default 100%).
  - `scripts/mb-work-protected-check.sh` — matches files against
    `pipeline.yaml:protected_paths` globs (incl. `**` segment-wildcard
    via glob→regex translator). Exit 0 if none match, 1 with
    `[protected] <file> matches <glob>` lines on stderr.
  - `agents/mb-reviewer.md` — production-grade prompt. Per-category
    review walk (logic / code_rules / security / scalability /
    tests), severity decision tree (blocker / major / minor with
    concrete examples), strict JSON output schema, fix-cycle
    behavior on subsequent iterations, hard guardrails.
  - `commands/work.md` — full per-stage workflow wired:
    implement → protected-check → review (Task → mb-reviewer) →
    parse → severity-gate → fix-cycle (cap at `max_cycles`,
    `on_max_cycles ∈ {stop_for_human, continue_with_warning}`) →
    verify (plan-verifier) → stage-done. Hard stops table for
    `--auto`: max_cycles reached, verifier fail, protected-path
    edit without `--allow-protected`, `--budget` exhausted,
    `sprint_context_guard.hard_stop_tokens` reached.
  - 43 new pytest cases (11 `test_mb_work_review_parse.py` + 9
    `test_mb_work_severity_gate.py` + 8 `test_mb_work_budget.py` +
    6 `test_mb_work_protected_check.py` + 9
    `test_phase3_sprint3_registration.py`). Total: 474 → 517 passed.

  Phase 4 will add the `context-slim-pre-agent.sh` /
  `pre-agent-protected-paths.sh` runtime hooks (so the protected-path
  block fires *before* a Write tool call lands), the `--slim` /
  `--full` context strategy wiring, and installer detection of the
  `superpowers:requesting-code-review` skill for the
  `pipeline.yaml:roles.reviewer.override_if_skill_present` swap.

- **Phase 3 Sprint 2: `/mb work` execution engine + 9 role-agents.**
  MVP of the executable runtime over plan files. New artifacts:
  - `scripts/mb-work-resolve.sh` — 5-form target resolver (spec §8.2):
    existing path → substring search in `plans/` (excluding `done/`) →
    topic name (`specs/<topic>/tasks.md`) → freeform (≥3 words, exit 3
    + candidate list for orchestrator-driven match) → empty (active
    plan from `<!-- mb-active-plans -->` block in `roadmap.md`).
    `--mb` flag for explicit bank override; ambiguity exit 2 with
    candidate list.
  - `scripts/mb-work-range.sh` — range parser (`N` / `A-B` / `A-`)
    with auto-detected level (plan target → stages from
    `<!-- mb-stage:N -->` markers; phase target via `--phase` →
    sprints from frontmatter `sprint:` field). Out-of-bounds rejected;
    phase mode without sprint frontmatter rejected.
  - `scripts/mb-work-plan.sh` — JSON Lines emitter, one object per
    stage with `{plan, stage_no, heading, role, agent, status,
    dod_lines}`. Role auto-detection by keyword match against heading
    + body (ios / android / frontend / backend / devops / qa /
    architect / analyst, with developer fallback). Agent resolved via
    `pipeline.yaml:roles` (resolved through `mb-pipeline.sh path`).
    `--dry-run` prepends a `## Execution Plan` summary header.
  - 9 implementer agents under `agents/`: `mb-developer.md` (generic
    fallback), `mb-backend.md`, `mb-frontend.md`, `mb-ios.md`,
    `mb-android.md`, `mb-architect.md`, `mb-devops.md`, `mb-qa.md`,
    `mb-analyst.md`. Each with role-specific discipline + self-review
    checklist tied to the rubric.
  - `agents/mb-reviewer.md` — Sprint 3 review-loop contract scaffold
    (verdict format, severity gate behaviour, output schema).
  - `commands/work.md` — slash-command spec for
    `/mb work [target] [--range A-B] [--dry-run]` documenting target
    resolution, range parsing, dispatch protocol via `Task` tool, and
    Sprint 3 deferred items.
  - `commands/mb.md` — router table row + `### work [target]` detail
    section.
  - 76 new pytest cases (9 `test_mb_work_resolve.py` + 9
    `test_mb_work_range.py` + 10 `test_mb_work_plan.py` + 40
    `test_mb_work_agents.py` + 8 `test_phase3_sprint2_registration.py`).
    Total: 398 → 474 passed.

  Sprint 3 will wire the review-loop, severity gates, fix-cycle on
  `CHANGES_REQUESTED`, `plan-verifier` integration, `--auto` end-to-end
  hard stops, `--budget` token tracking, `--slim`/`--full` context
  strategy (with hooks from Phase 4), and the
  `superpowers:requesting-code-review` skill override.

- **Phase 3 Sprint 1: `/mb config` + `pipeline.yaml` declarative engine config.**
  Lays the foundation for the Phase 3 Sprint 2 `/mb work` execution
  engine. New artifacts:
  - `references/pipeline.default.yaml` — bundled default that ships
    with the skill. Implements the full spec §9 schema: `version`,
    `roles` (11 entries: developer / backend / frontend / ios / android
    / architect / devops / qa / analyst / reviewer / verifier),
    `stage_pipeline` (implement → review → verify steps with
    `severity_gate`, `max_cycles`, `on_max_cycles`, and 7 verifier
    checks), `budget`, `protected_paths` (6 globs incl. `.env*`,
    `ci/**`, `.github/workflows/**`), `sprint_context_guard`
    (150k/190k), `review_rubric` (5 sections × 2-3 items), and `sdd`
    (5 EARS-enforcement keys).
  - `scripts/mb-pipeline-validate.sh` — structural schema validator
    (Bash + python+PyYAML heredoc). Checks required keys, version,
    role declarations, severity_gate ⊆ {blocker, major, minor},
    max_cycles ≥ 1, `on_max_cycles ∈ {stop_for_human,
    continue_with_warning}`, budget bounds [0, 100],
    sprint_context_guard.hard > soft, non-empty rubric lists, sdd
    boolean fields, `covers_requirements_policy ∈ {warn, block, off}`.
  - `scripts/mb-pipeline.sh` — dispatcher with subcommands `init`
    (copies bundled default into `<bank>/pipeline.yaml`, idempotent
    with `--force` override), `show` (prints resolved config), `path`
    (prints absolute path of effective file), `validate` (validates
    resolved config or an explicit file). Resolution chain:
    `<bank>/pipeline.yaml` → `references/pipeline.default.yaml`.
  - `commands/config.md` — slash-command spec for `/mb config
    <subcommand>`.
  - `commands/mb.md` — router table row + `### config <subcommand>`
    detail section.
  - 63 new pytest cases (33 `test_pipeline_default_yaml.py` for
    schema-shape sanity + 14 `test_mb_pipeline_validate.py` for
    validator behaviour + 11 `test_mb_pipeline_cli.py` for dispatcher
    semantics + 5 `test_phase3_sprint1_registration.py`). Total:
    335 → 398 passed.

- **Phase 2 Sprint 2: `/mb sdd` Kiro-style spec triple + SDD-lite in `/mb plan`.**
  Closes the SDD vertical. New artifacts:
  - `commands/sdd.md` — slash-command for `/mb sdd <topic> [--force]`,
    creates `.memory-bank/specs/<topic>/{requirements,design,tasks}.md`.
    If `<mb>/context/<topic>.md` exists, the
    `## Functional Requirements (EARS)` block is copied verbatim into
    `requirements.md` (REQ-IDs preserved). Refuses by default if the
    spec already exists; `--force` overwrites.
  - `commands/mb.md` router row + `### sdd <topic>` detail section.
  - `scripts/mb-sdd.sh` — implementation. Bash + python heredoc for
    EARS extraction (Python `\s` regex, not POSIX `[[:space:]]`).
  - `scripts/mb-plan.sh` extended with `--context <path>` and `--sdd`
    flags. Auto-detects `<mb>/context/<safe_topic>.md` when
    `--context` is absent. `--sdd` is strict: refuses unless an
    EARS-valid context exists. When a context is resolved, the plan
    template gains a `## Linked context` section pointing at the
    file.
  - `references/templates.md` — "Spec Requirements", "Spec Design",
    "Spec Tasks" templates aligned with the `mb-sdd.sh` output.
  - 18 new pytest cases (7 `test_sdd.py` + 6 `test_plan_sdd_lite.py`
    + 5 `test_phase2_sprint2_registration.py`). Total: 317 → 335
    passed.

- **Phase 2 Sprint 1: `/mb discuss` + EARS validator + `context/<topic>.md`.**
  Input-side of the SDD traceability pipeline. New artifacts:
  - `commands/discuss.md` — slash-command for the 5-phase requirements
    interview (Purpose & Users / Functional EARS / Non-Functional /
    Constraints / Edge Cases & Failure Modes). Validates draft REQs in
    Phase 2 against the EARS regex; assigns IDs via
    `mb-req-next-id.sh`; finalizes by running `mb-traceability-gen.sh`.
  - `commands/mb.md` router table row + `### discuss <topic>` detail
    section.
  - `scripts/mb-ears-validate.sh` — validates `- **REQ-NNN** ...`
    bullets against the 5 EARS patterns (Ubiquitous /
    Event-driven / State-driven / Optional / Unwanted). Exit 0 = all
    valid (or no REQs); exit 1 = violations on stderr; exit 2 = usage.
    Reads from a file path or stdin (`-`).
  - `scripts/mb-req-next-id.sh` — emits the next monotonic `REQ-NNN`
    by scanning `specs/*/requirements.md`, `specs/*/design.md` and
    `context/*.md`. No bank or no REQs → `REQ-001`. Gaps in the
    existing sequence are NOT filled.
  - `references/templates.md` — added the `context/<topic>.md`
    template with Purpose & Users / Functional Requirements (EARS) /
    Non-Functional / Constraints / Edge Cases / Out of Scope sections.
  - 24 new pytest cases (13 EARS-validate + 6 req-next-id + 5
    registration). Total: 293 → 317 passed.

### Fixed

- **Sprint 3 (I-028): multi-active plan checklist collision.** Two plans sharing
  a stage heading (e.g. both with `## Task 1: Setup`) no longer collapse onto a
  single checklist section. `mb-plan-sync.sh` now emits a
  `<!-- mb-plan:<basename> -->` marker above each section it appends; idempotency
  is keyed on the (marker, heading) pair. `mb-plan-done.sh` removes ONLY sections
  preceded by the closing plan's marker. Sections without markers (pre-existing
  legacy v3.1 layout) keep heading-only ownership through a conservative fallback
  that activates only when no other plan claims the same heading via a marker.
  pytest: 289 → 293 (4 new `test_plan_multi_active_collision.py` cases). bats:
  479 → 515 passed — Sprint 1 missed a v2 rename in `test_plan_sync.bats`,
  `test_idea_promote.bats`, `test_plan_sync_multi.bats`, `test_plan_done_multi.bats`
  fixtures (`plan.md`/`STATUS.md`/`BACKLOG.md` → `roadmap.md`/`status.md`/`backlog.md`),
  also fixed here. Legacy `test_plan_sync.bats::"existing stage with identical
  title not duplicated"` rewritten to express the v3.2 contract (legacy unmarked
  section preserved + new marker section appended).

## [2.0.0-alpha.1] - 2026-04-22

### Breaking

- **Rename core files to lowercase:**
  - `STATUS.md` → `status.md`
  - `BACKLOG.md` → `backlog.md`
  - `RESEARCH.md` → `research.md`
  - `plan.md` → `roadmap.md` (with new roadmap format)
- Migration via `scripts/mb-migrate-v2.sh` — see `docs/MIGRATION-v1-v2.md`.
- 2-version backward-compat window; `/mb doctor` warns on unmigrated layouts.

### Added

- `scripts/mb-migrate-v2.sh` — idempotent v1 → v2 migrator (rename + content transform + reference fixup + timestamped backup)
- `docs/MIGRATION-v1-v2.md` — user-facing migration guide
- `tests/pytest/test_migrate_v2.py` — migration coverage (8 integration tests)
- `tests/pytest/test_skill_naming_v2.py` — naming-guard test (asserts skill code uses v2 names)
- `tests/pytest/fixtures/mb_v1_layout/` — v1 fixture for migration tests

### Changed

- All `commands/`, `references/`, `agents/`, `scripts/` (except migrators), `adapters/`, `memory_bank_skill/`, `templates/`, `rules/`, IDE-rule mirrors, top-level docs, and existing `tests/pytest/` updated to use v2 names.
- `/mb start`, `/mb context`, `/mb doctor` autodetect v1 layout and prompt migration.
- `/mb plan` output path convention unchanged — plan files still land in `.memory-bank/plans/`, roadmap entry now lives in `roadmap.md` (formerly `plan.md`).

## [3.1.2] — 2026-04-21

**Review findings hardening + installer boundary refactor.** Seven stages
closing three classes of problems surfaced by the full-repo review and
security audit: P0 security risks around path traversal and manifest
poisoning, architectural debt in `install.sh` / adapter layer, and
contract / maintainability drift in CLI, manifests, and shared helpers.
All 3 High findings from `SECURITY_AUDIT_REPORT.md` closed; 601/601 bats
+ 246/246 pytest green.

### Added

- **Safe path helpers in `scripts/_lib.sh`** — canonicalization and subtree
  validation reused by `install.sh` / `uninstall.sh` / adapters. Traversal
  payloads in `.claude-workspace`, uninstall manifest paths, and `adapters/pi.sh`
  `pi_skill_dir` all fail closed.
- **`MB_ALLOW_METRICS_OVERRIDE=1` opt-in gate** for `.memory-bank/metrics.sh`
  execution. Default blocks user-supplied overrides with an actionable hint.
- **`-y` / `--non-interactive` flags** on `uninstall.sh` and the Python
  `memory-bank uninstall` CLI. Both skip the prompt for CI/automation usage.
- **`schema_version` + deterministic file/backup ordering** in the global
  install manifest. Unblocks safe tooling that reasons over manifests.
- **`memory_bank_skill/_io.py`** — shared atomic-write helper; replaces four
  duplicated `_atomic_write()` implementations in Python scripts.
- **`memory_bank_skill/_texttools.py`** — shared `strip_marked_section` /
  `localize_language_rule` / etc.; replaces four near-identical Python
  heredoc blocks in `uninstall.sh` with one shared call path.
- **`adapters/_framework.sh` + `adapters/_contract.sh`** — shared adapter
  entrypoints (install/uninstall), manifest writing, hook JSON merge, and
  contract invariants. Sourced by all 7 adapters.
- **`references/adapter-manifest-schema.md`** — documented manifest schema
  (`schema_version`, `adapter`, `installed_at`, `files`, optional keys).
- **Direct bats coverage** for `mb-note.sh`, `mb-plan.sh`, `_lib_agents_md.sh`
  refcount/atomic-write behavior, 10 MB hook-log rotation boundary, and
  `run_shell()` subprocess failure path — closes review-cited test gaps.
- **`test_texttools.py`** pytest coverage for atomic write rollback,
  marker-strip, and language-rule localization.

### Changed

- **`install.sh` no longer contains client-specific Cursor global helpers** —
  hooks / AGENTS / user-rules logic moved into `adapters/cursor.sh`. The
  universal installer is now orchestration only (argument parsing + shared
  install + adapter invocation). `install.sh: 1` reference vs
  `adapters/cursor.sh: 8` references post-refactor.
- **`uninstall.sh` delegates adapter cleanup** instead of relying solely on
  the global manifest. Adapter artifacts round-trip cleanly; user content
  preserved.
- **`adapters/_lib_agents_md.sh`** writes owner state atomically with an
  explicit `jq` preflight that fails clearly when the binary is missing.
- **All 7 adapters migrated to the shared framework** without changing their
  public CLI. OpenCode/Codex/Pi shared `AGENTS.md` coexistence preserved.
- **`mb-compact.sh` is narrowed back to archival decay.** Structural migration
  of `checklist.md` done-sections and `plan.md` deferred/declined bullets now
  lives in `mb-migrate-structure.sh`, which keeps compaction and migration on
  separate boundaries again.
- **`settings/merge-hooks.py`** now strips only Memory Bank-owned hook items
  within mixed entries, preserving unrelated user commands in the same event.
- **Pi's native `MB_PI_MODE=skill` path** is no longer part of the supported
  default surface. Normal installs stay on `agents-md`; native-skill probing
  requires the explicit `MB_EXPERIMENTAL_PI_SKILL=1` gate.

### Fixed

- Traversal payloads in `.claude-workspace`, uninstall manifest paths, and
  `adapters/pi.sh` `pi_skill_dir` now reject external targets before any
  destructive operation.
- `install.sh::backup_if_exists()` refuses symlink targets that escape
  managed directories; safe regular-file idempotency preserved.
- `memory-bank install` fails early on unknown `--clients` values with a
  clear error before `install.sh` runs.
- `settings/merge-hooks.py` no longer drops mixed user/MB hook entries when
  the first hook item happens to be MB-owned.

### Docs

- `README.md`, `docs/install.md`, `docs/release-process.md`, `SECURITY.md`
  now document `memory-bank uninstall -y`, `MB_ALLOW_METRICS_OVERRIDE=1`
  opt-in, and Pi's experimental native skill gate.

## [3.2.0] — 2026-04-21 (unreleased — staged on main)

**Subagent maturity release.** Six stages of targeted upgrades to the skill's
subagent layer. Two new deterministic helpers (`scripts/mb-rules-check.sh`,
`scripts/mb-test-run.sh`) unblock two new subagents; four existing subagents
get first-class contracts, graph-aware analysis, and explicit conflict
resolution. 102 new bats assertions; 177/177 passing including regression.

### Added

- **`agents/mb-rules-enforcer.md` + `scripts/mb-rules-check.sh`** — deterministic
  SRP (>300 lines), Clean Architecture direction (`domain/` importing
  `infrastructure/`), and TDD-delta (source without matching test) checks
  that emit strict JSON. The wrapping subagent adds LLM-level ISP / DRY
  judgment. Called by `/review`, `/commit`, `/pr`, and plan-verifier Step
  3.6. JSON-first design enables machine composition; CRITICAL/WARNING/INFO
  vocabulary is closed and documented.
- **`agents/mb-test-runner.md` + `scripts/mb-test-run.sh`** — per-stack
  structured test executor (python + go in v1). Returns
  `{stack, tests_pass, tests_total, tests_failed, failures[], coverage,
  duration_ms}`. Never collapses `null` to `false` — absence of a runner
  yields explicit NOT-RUN rather than silent pass. Called by `/test` and
  plan-verifier Step 3.5; replaces direct `mb-metrics.sh --run` to avoid
  double execution.
- **`scripts/mb-drift.sh` check #9 — `check_research_experiments`** — scans
  `RESEARCH.md` for H-NNN rows whose status is ✅ Confirmed or ❌ Refuted and
  verifies the matching `experiments/EXP-NNN.md` exists. Missing file →
  `drift_check_research_experiments=warn` + per-H stderr line. Zero LLM
  tokens for detection.
- **`**Baseline commit:** <hash>` header in every new plan** (`scripts/mb-plan.sh`
  writes `git rev-parse HEAD` at plan creation). `plan-verifier` uses it as
  the diff base via `git diff <baseline>...HEAD`, replacing `HEAD~N` guessing.
  Fallback chain: ctime lookup → `HEAD~10` with WARNING. Outside a git repo →
  `unknown`.
- **`MB_DOCTOR_REQUIRE_CLEAN_TREE` env guard** — when set to `1`, mb-doctor
  refuses to auto-fix on a dirty working tree and surfaces an actionable
  `git stash` hint. Default OFF; intended for CI / shared environments.
- **`MB_GRAPH_STALE_HOURS` env override** — default 24h. Controls how fresh
  `graph.json` must be before `mb-codebase-mapper` consumes it; stale →
  graceful grep fallback.
- **`### action: done` first-class section in `agents/mb-manager.md`** —
  normative 6-step flow (actualize → note → plan closure → session-lock →
  index regen → report) + explicit 5-rule "Actualize conflict resolution"
  subsection. Supersedes the prior "combined flow of actualize + note"
  wording in `commands/done.md`.

### Changed

- **`agents/plan-verifier.md` Step 3.5** now delegates to `mb-test-runner`
  instead of calling `mb-metrics.sh --run` directly. Eliminates double test
  execution in the verify → done flow.
- **`agents/plan-verifier.md` Step 3.6** enforces RULES.md with project-first
  precedence (`.memory-bank/RULES.md` → `~/.claude/RULES.md`).
- **`agents/mb-codebase-mapper.md`** now prefers `graph.json` / `god-nodes.md`
  over ad-hoc grep when deriving CONVENTIONS (naming-pattern counts from
  node names) and CONCERNS (god-nodes cited by name + degree). Dogfood on
  this repo: 92% snake_case (53/57 function names), top-5 god-nodes ready to
  cite. Auto-stamps `Generated: $(date -u +%FT%TZ)` in template headers.
- **`commands/review.md`** and **`commands/test.md`** replace inline principle
  / stack-runner enumerations with single `Agent()` delegation blocks.
- **`scripts/mb-rules-check.sh` `has_matching_test()`** strips a leading
  `mb-` prefix before basename matching AND adds a content-grep fallback —
  tests named after the agent/feature (`test_rules_enforcer_*.bats`) now
  correctly satisfy tdd/delta for their wrapping scripts (`mb-rules-check.sh`).

### Fixed

- `plan-verifier` no longer uses `HEAD~N` as the diff base — guess-driven
  audit scope is replaced with the recorded `**Baseline commit:**` from the
  plan header.
- `mb-doctor` no longer edits files silently under a dirty tree when the
  guard env is set — the previous implicit trust in the working state is
  replaced with an observable decision point.
- `mb-rules-check.sh` `tdd/delta` false positives on scripts whose tests are
  named after the conceptual feature (not the script) are resolved via the
  content-grep fallback pass.

## [3.1.1] — 2026-04-21

**i18n infrastructure release.** Memory Bank now ships locale-aware
`.memory-bank/` template bundles. Existing English users are unaffected —
this is a pure capability addition.

### Added

- **Locale template bundles under `templates/locales/{en,ru,es,zh}/.memory-bank/`.**
  `en` and `ru` ship as full translations; `es` and `zh` ship as scaffolds
  (EN copy + `TODO(i18n-<lang>)` banner) that the community can complete via
  PR — see [`docs/i18n.md`](i18n.md).
- **New `scripts/mb-config.sh`** — 4-tier locale resolver:
  1. `MB_LANG` env var
  2. `$MB_ROOT/.memory-bank/.mb-config` (`lang=XX`)
  3. Heuristic auto-detect from existing bank content (Cyrillic → `ru`) with
     write-back for determinism
  4. Default `en`
- **New `scripts/mb-init-bank.sh`** — deterministic, locale-aware bank
  scaffolder. Respects `--lang=XX`, `MB_LANG`, existing `.mb-config`; never
  overwrites user-authored files.
- **`memory-bank init --lang=XX`** CLI flag and **`/mb init --lang=XX`**
  command form.
- **`install.sh --language {en|ru|es|zh}`** — expanded whitelist (was `en|ru`).
- **`docs/i18n.md`** — contributor guide for adding a new locale.

### Contract

- Canonical English anchors (`<!-- mb-active-plans -->`,
  `<!-- mb-recent-done -->`, `## Ideas`, `## ADR`) remain English in **every**
  locale bundle — every `mb-*` script depends on them.
- `commands/mb.md`, script CLI output, and the main English docs stay English.

### Coverage

- 216 pytest + 14 skipped (pytest suite)
- 14/14 `mb-config` bats
- 9/9 `mb-init-bank` bats
- 28/28 install/uninstall e2e bats

## [3.1.0] — 2026-04-21

**Major refactor of core Memory Bank files** (`STATUS.md`, `plan.md`, `checklist.md`, `BACKLOG.md`) with stricter formats, multi-active plan support, monotonic idea IDs, and a dedicated `mb-compact.sh` extension that prunes stale `checklist.md` / `plan.md` entries.

### Breaking-ish (auto-migrated)

- **`plan.md` / `STATUS.md` now carry multi-active plan blocks.** The singular `<!-- mb-active-plan -->` / `<!-- /mb-active-plan -->` markers are upgraded to plural `<!-- mb-active-plans -->` / `<!-- /mb-active-plans -->` and the heading `## Active plan` → `## Active plans`. `STATUS.md` gains a new `<!-- mb-recent-done -->` / `<!-- /mb-recent-done -->` block (default-trimmed to 10 entries via `MB_RECENT_DONE_LIMIT`).
- **`BACKLOG.md` now has a fixed skeleton — `## Ideas` (with `### I-NNN — title [PRIO, STATUS, DATE]` entries) + `## ADR` (with `### ADR-NNN — title [date]` entries).** IDs are monotonic project-wide.
- **Migration is automatic.** Run `bash scripts/mb-migrate-structure.sh --apply .memory-bank` (or `/mb migrate-structure --apply`). The script creates a timestamped `.pre-migrate/YYYYMMDD_HHMMSS/` backup before touching anything, upgrades marker names, and ensures the skeleton is present. Rerunning is a no-op (idempotent). See `docs/MIGRATION-v3-v3.1.md`.

### Added

- **`scripts/mb-idea.sh`** — capture a new idea in `BACKLOG.md ## Ideas` with an auto-assigned `I-NNN` ID (monotonic, project-wide). Usage: `bash scripts/mb-idea.sh "title" [HIGH|MED|LOW]`. Wired as `/mb idea`.
- **`scripts/mb-idea-promote.sh`** — promote an existing idea (`I-NNN`) to a plan file. Validates idea is in `NEW`/`TRIAGED` state, calls `mb-plan.sh <type>`, flips idea status to `PLANNED`, adds `**Plan:**` cross-link, and runs `mb-plan-sync.sh` to register the new plan in `plan.md` + `STATUS.md`. Wired as `/mb idea-promote`.
- **`scripts/mb-adr.sh`** — capture a new ADR in `BACKLOG.md ## ADR` with an auto-assigned `ADR-NNN` ID and a standard skeleton (Context / Options / Decision / Rationale / Consequences). Wired as `/mb adr`.
- **`scripts/mb-migrate-structure.sh`** — one-shot v3.0 → v3.1 structural migration tool (dry-run by default; `--apply` to execute). Wired as `/mb migrate-structure`.

### Changed

- **`scripts/mb-plan-sync.sh` is now multi-active-plan aware.** Upserts the same plan into `<!-- mb-active-plans -->` blocks in *both* `plan.md` and `STATUS.md` (deduped by basename). Auto-upgrades legacy singular markers on first run. Stage sections are appended to `checklist.md` with exact-heading matching so two active plans never collide on identical stage titles.
- **`scripts/mb-plan-done.sh` is fully redesigned.** Instead of just ticking checkboxes, it now (1) removes the plan's stage sections from `checklist.md` entirely, (2) removes its entry from the active-plans blocks in `plan.md` + `STATUS.md`, (3) prepends the completed plan to `<!-- mb-recent-done -->` in `STATUS.md` (trimmed to `MB_RECENT_DONE_LIMIT`, default 10), (4) flips any linked `BACKLOG.md` idea from `PLANNED` → `DONE` and appends an `**Outcome:**` placeholder, and (5) moves the plan file to `plans/done/`.
- **`scripts/mb-compact.sh` extended** with `checklist.md` + `plan.md` compaction:
  - `CHECKLIST_AGE_DAYS` (default 14) — fully-done checklist sections that link to a `plans/done/` file older than this threshold are removed on `--apply`.
  - Bullets inside legacy localized `plan.md` `Deferred` / `Declined` sections are migrated into `BACKLOG.md` as new ideas with status `DEFERRED` (or `DECLINED`) and removed from `plan.md`. Section headings are preserved empty for future use.
- **`templates/.memory-bank/`** — `STATUS.md`, `plan.md`, `checklist.md`, `BACKLOG.md` redesigned around the new marker blocks and ID schemes. Header comments explain each file's role, size recommendations, and script contracts (deliberately avoid mentioning literal marker names to prevent regex false-positives in format-invariant tests).
- **`references/structure.md`** — rewritten as the v3.1 specification. Defines format invariants, lifecycle (NEW → TRIAGED → PLANNED → DONE / DEFERRED / DECLINED), ID schemes (`I-NNN`, `ADR-NNN`, `H-NNN`, `EXP-NNN`), control env vars (`MB_RECENT_DONE_LIMIT`, `MB_COMPACT_CHECKLIST_DAYS`, `MB_COMPACT_AGE_DAYS`), and per-file / per-directory contracts.
- **`commands/mb.md`** — new subcommands `/mb idea`, `/mb idea-promote`, `/mb adr`, `/mb migrate-structure` documented in the routing table and body sections.

### Fixed

- **Python regex deprecation warnings** — replaced POSIX `[[:space:]]*` with `\s*` in the Python snippets embedded in `scripts/mb-compact.sh` and `scripts/mb-migrate-structure.sh`.
- **BSD/GNU `awk` portability** — `mb-idea.sh` ID generation now uses `grep -Eo | awk -F- | sort -n | tail -1 || true` instead of GNU-only `awk match(..., arr)`. `mb-adr.sh` multiline skeleton is written to a temp file and pulled into `awk` via `getline` to avoid `awk: newline in string` on macOS.
- **`mb-idea-promote.sh` Unicode-aware parsing** — title/status extraction switched from `sed -E` / `tr -d` (which failed on multibyte `—`) to Python `re.match`.

### Tests (TDD RED→GREEN)

- **8 new BATS suites, 1 new pytest suite:**
  - `test_plan_sync_multi.bats` (8 tests) — multi-active plan upsert, idempotency, legacy-marker upgrade.
  - `test_plan_done_multi.bats` (7 tests) — completion flow: recent-done prepend/trim, checklist section removal, BACKLOG status flip.
  - `test_idea.bats` (7 tests) — monotonic `I-NNN` IDs, priority handling, idempotency, invalid-input validation.
  - `test_idea_promote.bats` (6 tests) — plan creation from idea, `NEW → PLANNED` flip, plan cross-link, active-plans registration.
  - `test_adr.bats` (6 tests) — monotonic `ADR-NNN`, skeleton sections, date format.
  - `test_compact_checklist.bats` (6 tests) — fully-done section removal linked to old `plans/done/`, env-var override.
  - `test_compact_plan_md.bats` (7 tests) — localized `Deferred` → `DEFERRED`, localized `Declined` → `DECLINED`, English alias support.
  - `test_migrate_structure.bats` (8 tests) — dry-run / apply modes, backup creation, marker upgrade, skeleton injection, idempotency.
  - `test_templates_format.py` — format invariants for all four core templates.
- **`test_plan_sync.bats` (legacy)** updated to the v3.1 contract (single-plan edge cases + error handling); multi-plan behaviour lives in the new suites.
- **`tests/e2e/test_install_uninstall.bats`** grew one assertion verifying the new v3.1 scripts (`mb-idea.sh`, `mb-idea-promote.sh`, `mb-adr.sh`, `mb-migrate-structure.sh`, `mb-compact.sh`) are installed and executable.

### Migration guide

See `docs/MIGRATION-v3-v3.1.md` for the step-by-step upgrade. TL;DR:

```bash
# 1. Install the new version
pipx upgrade memory-bank-skill       # or brew upgrade memory-bank
# 2. Run the automatic structural migration
bash ~/.claude/skills/memory-bank/scripts/mb-migrate-structure.sh --apply .memory-bank
# 3. Verify backup was created
ls .memory-bank/.pre-migrate/
```

## [3.0.1] — 2026-04-21

Patch release consolidating the command audit, docs-surface refactor,
CI stabilization, and the migration to PyPI Trusted Publishing.

### CI / release pipeline

- **PyPI publishing switched to Trusted Publisher (OIDC).** `publish.yml` no longer uses the long-lived `PYPI_API_TOKEN` secret. The `publish-pypi` job now declares `environment: pypi` + `permissions: id-token: write`, and `pypa/gh-action-pypi-publish` auto-activates OIDC. Matches the PyPI-recommended auth path (`docs.pypi.org/trusted-publishers/`). The `pypi` GitHub environment is managed in repo Settings → Environments; it shows up as a green Deployments card on every successful release.
- **`test.yml` installs `.[codegraph]` extras** so `tree-sitter` language bindings are present in CI. Without them `tests/pytest/test_codegraph_ts.py` silently skipped 14 scenarios, dragging coverage of `scripts/mb-codegraph.py` under the 85% threshold. Now coverage reports 92 %+ consistently.
- **`shellcheck` SC2015 resolved in two scripts.** `scripts/mb-deps-check.sh` helpers (`say` / `say_err`) rewritten from the `A && B || C` pattern to explicit `if [ … ]; then …; fi`. `hooks/mb-compact-reminder.sh` subshell switched from `cmd || true` to `cmd; true` inside `$(…)`. Same behaviour, no more SC2015 warnings on lint CI.

### Badges / docs surface

- **Landing page badges (`site/index.html`) + README badges** aligned. 8 green shields total: tests CI, PyPI version, GitHub release, Python versions, Homebrew tap, monthly downloads, last commit, MIT license. All URLs carry a `v=300` cache-buster so `camo.githubusercontent.com` pulls the current shields.io SVG (without it, GitHub's camo proxy held onto the `v3.0.0rc1` image after the stable release).
- **New `Docs` section on the landing page** with curated links to the install guide, `/mb` command reference, `CHANGELOG`, release process, and v1→v2 migration notes. Listed in the topnav.
- **`CONTRIBUTING.md` + `SECURITY.md`** added to satisfy GitHub Community Standards (green Community tab, Security Policy link on the repo header). `CONTRIBUTING` documents the TDD workflow, dev-dependency setup (`.[codegraph,dev]`), Conventional Commits, and the four local lint/test gates. `SECURITY` documents supported versions (3.0.x active, 2.x critical-only until 2026-10, <2 EOL), the private reporting channel (GitHub Security Advisories), response SLAs, and the coordinated-disclosure policy.

### Commands refactor (audit-driven, 2026-04-21)

- **Canonical command template** — `references/command-template.md` documents the required YAML frontmatter shape (`description`, `allowed-tools`, `argument-hint`), body structure, memory-bank integration snippets, alias pattern, and a pre-commit validation checklist. Linked from `SKILL.md`.
- **Frontmatter fixed in 10 command files** — `adr.md`, `catchup.md`, `changelog.md`, `commit.md`, `contract.md`, `done.md`, `plan.md`, `refactor.md`, `start.md`, `test.md` previously opened with `# ~/.claude/commands/<name>.md` + `---` + `## description:` as a Markdown heading. This killed YAML parsing so host UIs (Claude Code, OpenCode, Cursor) never loaded descriptions or tool whitelists. All 10 now open with a valid `^---$` fence on line 1 and expose exactly 2 fences. `pr.md` had the same comment-before-fence issue — also fixed. `doc.md` frontmatter normalized (plugin-specific `agent:` / `context:` keys preserved inside the fence with an explanatory HTML comment).
- **Alias resolution — `/plan`, `/start`, `/done` are now the primary commands.** The sophisticated logic (mb-plan.sh scaffold + mb-plan-sync.sh, mb-context.sh + codebase-bootstrap suggestion, MB Manager actualize+note + `.session-lock` touch) lives in `commands/plan.md`, `commands/start.md`, `commands/done.md`. `/mb plan|start|done` are explicit aliases that delegate to the primary commands. `commands/mb.md` sections shrink to pointer-paragraphs and keep the router entries working so `/mb plan feature <topic>` still reaches the same scripts.
- **`/adr` writes to `BACKLOG.md`** — previously wrote ADR files to `plans/`, contradicting `RULES.md` + MB Manager which both say ADRs belong in `BACKLOG.md ## Architectural decisions (ADR)`. New flow: find max existing `ADR-NNN`, monotonic +1, append as one-line entry per `references/templates.md`. Optional cross-link note. Empty-args guard.
- **Stack-generic refactor via `mb-metrics.sh`** — `security-review.md`, `db-migration.md`, `observability.md`, `api-contract.md`, `test.md` now all call `mb-metrics.sh` first and have an explicit `stack=unknown` fallback that asks the user instead of assuming.
  - `/security-review` now covers Go / Python / Node / Rust / Java / Kotlin / Ruby / .NET (8 stacks) and recommends `trufflehog` / `gitleaks` over the naive grep for secret scanning.
  - `/db-migration` now detects 8+ tools: golang-migrate, goose, Atlas, Alembic, Prisma, Sequelize, Knex, Diesel, SQLx, Flyway, Liquibase, Entity Framework Core, plain SQL. Non-listed → ask the user.
  - `/observability` now covers Go / Python / Node / Rust / Java / Kotlin / .NET with specific library recommendations per stack.
  - `/api-contract` detects Go (gin/echo/chi/net-http) + Node (Express/Fastify/Nest) + Python (FastAPI/Flask/Django) + Spring + ASP.NET + Rust (Axum/Actix/Rocket) + Rails. Recommends Schemathesis + Pact for contract tests.
  - `/test` now uses `$test_cmd` from metrics instead of hardcoding `go test / pytest / jest`; keeps per-runner `-filter` hints as examples.
- **Safety gates — destructive operations no longer silent:**
  - `/commit` runs `mb-drift.sh` + `git diff --check` pre-flight, scans the staged diff for debug residue / secrets / TODOs, and requires explicit `y/N` confirmation (default = No) before `git commit`.
  - `/pr` refuses to create a PR from `main` / `master`, warns if 0 commits ahead of the integration branch, surfaces CI workflows via `gh workflow list`, and requires `y/N` preview confirmation before `gh pr create`.
  - `/db-migration` destructive SQL ops (`DROP TABLE`, `DROP COLUMN`, `TRUNCATE`, `DELETE FROM` without `WHERE`) now require explicit `y/N` confirmation *before the file is written*, not just before it is applied.
- **Empty-`$ARGUMENTS` guards** — `/refactor`, `/contract`, `/adr`, `/api-contract`, `/db-migration` now all stop and ask the user for the missing topic instead of running with an empty target (Fail-Fast per `RULES.md`).
- **`codebase/` integration in context-reading commands** — `/catchup` now reads the `codebase/*.md` summaries alongside plan / checklist / notes. `/review` reads `codebase/ARCHITECTURE.md` + `codebase/CONCERNS.md` for its architectural analysis section. `/pr` adds a `## Codebase context` section to the PR body when `codebase/` is populated.
- **Verification** — `bash scripts/mb-drift.sh .` → `drift_warnings=0` on all 8 checks (path, staleness, script_coverage, dependency, cross_file, index_sync, command, frontmatter). Frontmatter loop check: 17 / 17 command files (minus `mb.md` which has a custom router structure) start with `^---$` and expose exactly 2 `---` fences.

Plan: `.memory-bank/plans/done/2026-04-21_refactor_commands-audit-fixes.md` (10 stages, all PASS).

### Docs

- **Surface `.memory-bank/codebase/` in all structural / workflow documentation.** The directory (populated by `mb-codebase-mapper` via `/mb map` / `/mb graph`, consumed by `scripts/mb-context.sh`) used to be mentioned only in `SKILL.md`, `commands/mb.md`, and the mapper agent prompt — it was missing from the two files that ship to user globals (`rules/CLAUDE-GLOBAL.md` → `~/.claude/CLAUDE.md` managed block, `rules/RULES.md` → `~/.claude/RULES.md`), the structure/workflow/templates references, and the per-project `CLAUDE.md` template used by `/mb init --full`. As a result, fresh agents did not know the folder existed, what lives in it, or when to regenerate it.
  - `references/structure.md` — new `### codebase/ — Codebase map` subsection with artifact table (6 files), producer (`mb-codebase-mapper` subagent, sonnet), consumer (`mb-context.sh`), and regeneration triggers.
  - `references/workflow.md` — session-start bootstrap rule (suggest `/mb map` when `codebase/` is empty, never auto-invoke) + `codebase/` rows in the "when to update" and "when to create" decision tables.
  - `references/templates.md` — tree comments on the `/mb init` structure so every subdirectory (including `codebase/`) has an inline description of who fills it.
  - `references/claude-md-template.md` — new `codebase/` row in the `.memory-bank/` table so the generated per-project `CLAUDE.md` documents the folder.
  - `rules/CLAUDE-GLOBAL.md` + `rules/RULES.md` — identical new `codebase/` row in the "Detailed records" table (byte-identical wording across both files) + bootstrap sentence / step in the session-start workflow.
  - `commands/mb.md` `### init` — new optional **Step 1.5** in `--full` mode: asks the user whether to seed `codebase/` by running `mb-codebase-mapper` now; default answer is skip. Step 6 Summary now surfaces `/mb map` as a follow-up next step.
- **No behavioural change** — `mb-codebase-mapper` is still never auto-invoked; `/mb init --minimal` is unaffected; all existing commands keep their exact current contracts. Running `bash scripts/mb-drift.sh .` still reports `drift_warnings=0`.

---

## [3.0.0] — 2026-04-20

First stable 3.x release. Combines the work from the `3.0.0-rc1` / `rc2` / `rc3`
candidates: native cross-agent install (Claude Code, Codex, Cursor, OpenCode),
five-artifact global parity for Cursor, byte-level idempotent `install.sh`,
and the `memory-bank install` / `memory-bank uninstall` / `memory-bank doctor`
CLI. Install via `pipx install memory-bank-skill` or `brew install fockus/tap/memory-bank`.

### Fixed (idempotency, promoted from `3.0.0-rc3`)

- **`install.sh` is now byte-level idempotent** — repeat runs on an up-to-date tree create **zero** `.pre-mb-backup.*` files.
  - Root cause: `backup_if_exists()` did an unconditional `mv` on any existing target, and `install_file()` called it without comparing `src` / `dst` content. For localized files (`RULES.md`, Cursor paste-file) a raw `cmp -s src dst` never matched because `dst` had been language-substituted.
  - Observed damage before the fix: 14 historic installs → 1628 accumulated `.pre-mb-backup.*` files; a single "clean" reinstall generated 48 backups, 37 of them byte-identical to the active file.
- **New helpers** in `install.sh`:
  - `install_file()` short-circuits via `cmp -s "$src" "$dst"` when content is already identical.
  - `backup_if_exists()` accepts an optional 2nd arg `expected_content_path` and returns `2` (skip marker) on content match.
  - `install_file_localized()` — composes expected post-install content in a temp file (`cp src` + `localize_path_inplace`), compares to `dst` via `cmp -s`, skips backup+write on match. Used for `RULES.md` in Step 1.
  - `localize_path_inplace()` — substitution helper without the existence shortcut.
  - `install_cursor_user_rules_paste()` rewritten with a compose-to-tmp + `cmp -s` skip instead of unconditional overwrite.
- **Manifest `.backups[]`** is now filtered via `os.path.exists` — stale refs from user-cleaned `.pre-mb-backup.*` files are dropped instead of accumulating across installs.
- **`tests/e2e/test_install_idempotent.bats`** — 5 bats scenarios: zero backups on repeat install, exactly-one backup per real content diff, zero backups after external delete, language-swap backs up only localize-target files, manifest lists only existing backup paths.

**Result**: repeat install on an up-to-date tree → 0 backups. Language swap (`--language en` → `--language ru`) → exactly 2 backups (`RULES.md` + `memory-bank-user-rules.md`) and nothing else.

### Added

- **Cursor global parity — five artifacts under `~/.cursor/` are now installed unconditionally** (without `--clients cursor`):
  - `~/.cursor/skills/memory-bank/` — symlink to the canonical skill bundle (Cursor auto-discovers personal skills).
  - `~/.cursor/hooks.json` + `~/.cursor/hooks/*.sh` — three global hooks (`sessionEnd` / `preCompact` / `beforeShellExecution`); each entry is marked `_mb_owned: true`, while user hooks on the same events are preserved.
  - `~/.cursor/commands/*.md` — user-level slash commands mirroring the skill `commands/` directory.
  - `~/.cursor/AGENTS.md` — managed section with unique `memory-bank-cursor:start/end` markers, preserving user content above and below.
  - `~/.cursor/memory-bank-user-rules.md` — paste-ready bundle for **Settings → Rules → User Rules** (Cursor has no file API for global User Rules; this is a one-time manual step per machine). The post-install hint prints `pbcopy`/`xclip` commands.
- **`install.sh` helpers**: `cursor_agents_section()`, `install_cursor_global_agents()`, `install_cursor_user_rules_paste()`, `install_cursor_global_hooks()` (with jq-based `hooks.json` merge similar to Codex). `ensure_skill_aliases()` now creates the `~/.cursor/skills/memory-bank` alias.
- **`uninstall.sh` Cursor branches**: preserve `~/.cursor/AGENTS.md` and `~/.cursor/hooks.json` from manifest-removal (managed merged files), remove only the memory-bank section and `_mb_owned` entries, delete `memory-bank-user-rules.md` and the `skills/memory-bank` alias, and `rmdir` empty `~/.cursor/{skills,hooks,commands}` directories.
- **`tests/e2e/test_cursor_global.bats`** — 17 bats scenarios: install creates all five artifacts, idempotency, preserve-user-content in `AGENTS.md` + `hooks.json`, clean uninstall.
- **`tests/pytest/test_cli.py::test_cli_install_uninstall_smoke_with_cursor_global`** — pytest smoke: real `install.sh` / `uninstall.sh` run in sandboxed `$HOME` with Cursor steps.
- **Docs**:
  - `SKILL.md` — Cursor promoted to the "native full support" tier, plus a new **Host-specific notes → Cursor** subsection with the five-artifact table and paste flow.
  - `docs/cross-agent-setup.md` — supported clients table, **Cursor (full global parity + project adapter)** section, resource availability matrix with a Cursor column and a "Global rules" row, troubleshooting Q&A for User Rules.
  - `README.md` — global install hint updated (Cursor included in baseline `memory-bank install`), new "Cursor-only quick start" section, adapter table extended with global artifacts.

### Fixed

- **`adapters/cursor.sh` — removed duplicate `# Global Rules` heading** in `.cursor/rules/memory-bank.mdc`. Previously the script wrote its own `# Global Rules` and then concatenated `rules/RULES.md`, which starts with the same heading, so the MDC file ended up with two identical H1s.

### Changed

- `install.sh` / `uninstall.sh` — added constants `CURSOR_DIR`, `CURSOR_SKILL_ALIAS`, `CURSOR_USER_RULES_FILE`, `CURSOR_START_MARKER` / `CURSOR_END_MARKER` (independent from Codex markers — allowing coexistence without conflicts in `~/.codex/AGENTS.md` vs `~/.cursor/AGENTS.md`).

### Added (rolled up from prior Unreleased)

- **Interactive client picker in `install.sh`** — when `--clients` is not set and stdin is a TTY, a multi-select menu is shown for 8 clients (`claude-code`, `cursor`, `windsurf`, `cline`, `kilo`, `opencode`, `pi`, `codex`). Accepts numbers, names, `all`, or empty input (`claude-code`). Suppressed by `--non-interactive` or non-TTY stdin.
- **`install.sh --non-interactive`** — explicit interactive bypass for CI / scripted installs.
- **Env `MB_CLIENTS`** — alternate way to set clients (same semantics as `--clients`), useful in Docker / pipx wrappers.
- **`memory-bank install --non-interactive`** — forwards the flag from the Python CLI.
- **`/mb install` subcommand** (section in `commands/mb.md`) — installs adapters from inside Claude Code / OpenCode / Codex. Uses `AskUserQuestion` for multi-select in CC and inline prompt in other agents. The `/mb` namespace protects against collisions with other skills.
- **Windows compromise — Git Bash / WSL support**:
  - `cli.py` no longer hard-fails on Windows. Added `find_bash()` with priority order: `MB_BASH` env override → `bash.exe` on PATH → `C:\Program Files\Git\bin\bash.exe` → WSL fallback.
  - `system32\bash.exe` (WSL launcher shim) is ignored in favor of Git Bash / explicit WSL.
  - `memory-bank doctor` now prints the resolved bash path on any platform.
  - Missing bash on Windows now yields an actionable install hint (`winget` / WSL).
- **README: full command reference** — two tables (18 top-level slash commands + 20 `/mb` subcommands), replacing the previous partial list of 23 lines.
- **README: 3 ways to install cross-agent adapters** — interactive menu, CLI flags, `/mb install` from inside the agent.

### Changed (rolled up from prior Unreleased)

- `memory-bank install / uninstall / init / doctor` — removed `require_posix()` calls; now work on Windows when bash is available.
- `tests/pytest/test_cli.py` — updated for the new platform model (29 tests, including 9 new `find_bash()` discovery tests + WSL wrapper mode).
- `tests/bats/test_install_interactive.bats` — new file with 13 tests for CLI flags, validation, env overrides.

### Docs (rolled up from prior Unreleased)

- README: Platform matrix expanded (macOS native / Linux native / Windows Git Bash / Windows WSL / Windows without bash — the last one with a hint).
- README: command tables numbered as "18 top-level + 20 `/mb` subcommands".

---

## [3.0.0-rc1] — 2026-04-20

### Repository moved

This skill moved to a new public repository: **[`fockus/skill-memory-bank`](https://github.com/fockus/skill-memory-bank)**. The old name `claude-skill-memory-bank` described only one of the 8 supported clients and had become misleading.

**Migration guide:** [docs/repo-migration.md](docs/repo-migration.md).

Historical releases (`v1.x`, `v2.0.0`, `v2.1.0`, `v2.2.0`) remain available in the old repository. `v3.0.0` and later are published in the new one.

### Added

- **Stage 8 — Cross-agent adapters** (7 clients beyond Claude Code): Cursor (CC-compat hooks), Windsurf (Cascade), Cline (`.clinerules/hooks/`), Kilo (+ git-hooks fallback), OpenCode (TS plugin with `experimental.session.compacting`), Codex (experimental hooks), Pi Code (dual-mode). See `docs/cross-agent-setup.md`.
- **`adapters/_lib_agents_md.sh`** — refcount-based shared `AGENTS.md` ownership via `.mb-agents-owners.json`. Enables safe coexistence of OpenCode / Codex / Pi installs.
- **`adapters/git-hooks-fallback.sh`** — universal `.git/hooks/` installer (post-commit auto-capture, pre-commit `<private>` warnings, chain pattern preserving user hooks).
- **`install.sh --clients <list>`** — non-interactive multi-client install. Valid: `claude-code, cursor, windsurf, cline, kilo, opencode, pi, codex`.
- **`docs/cross-agent-setup.md`** — complete per-client cheatsheet + hook capability matrix + troubleshooting FAQ.
- **`docs/repo-migration.md`** — upgrade instructions for existing users.

### Changed

- Repository name: `claude-skill-memory-bank` → `skill-memory-bank`.
- Install target directory: `~/.claude/skills/skill-memory-bank/` (previously `claude-skill-memory-bank/`).
- `mb-upgrade.sh` now tracks the new origin URL.

### Tests

- **340+/340+ bats + e2e green** (+90 adapter bats, +10 install-clients e2e over v2.2.0).

---

## [2.2.0] — 2026-04-20

Knowledge-reach release: cold-start through JSONL import, code graph for 6 languages, tags normalization through a controlled vocabulary.

### Added

- **`/mb import --project <path> [--since] [--apply]`** (`scripts/mb-import.py`) — bootstrap Memory Bank from Claude Code transcripts (`~/.claude/projects/<slug>/*.jsonl`). Extracts daily-grouped `progress.md` sections and arch-discussion notes (≥3 consecutive assistant messages >1K chars). Dedup via SHA256(timestamp + first 500 chars), resume through `.import-state.json`. PII auto-wrap (email + API-key → `<private>`) integrated with v2.1 Stage 3. `--dry-run` by default.
- **`/mb graph [--apply] [src_root]`** (`scripts/mb-codegraph.py`) — code graph for Python (stdlib `ast`, always-on) + Go / JavaScript / TypeScript / Rust / Java (through tree-sitter, opt-in). Nodes = module/function/class, edges = import/call/inherit. Output: `codebase/graph.json` (JSON Lines, grep/jq friendly) + `codebase/god-nodes.md` (top-20 by degree). SHA256 incremental cache per file. `HAS_TREE_SITTER` flag provides graceful degradation without grammars. Skipped dirs: `.venv`, `node_modules`, `__pycache__`, `.git`, `target`, `dist`, `build`.
- **`/mb tags [--apply] [--auto-merge]`** (`scripts/mb-tags-normalize.sh`) — Levenshtein-based synonym detection + merge through a controlled vocabulary. Distance ≤2 detection, ≤1 for `--auto-merge`. Vocabulary in `.memory-bank/tags-vocabulary.md` (user-editable) → fallback to `references/tags-vocabulary.md` (35 default tags). Exit 2 when unknown tags are found (drift signal).
- **`references/tags-vocabulary.md`** — template with 35 default tags (Core: arch/auth/bug/perf/refactor/test/...; Process: debug/review/post-mortem/adr/spike; Workflow: blocked/todo/wip/imported/discussion).
- **`mb-index-json.py`** — auto-kebab-case for tags: `FooBar → foo-bar`, `AUTH → auth`, `someThing → some-thing`. Dedup while preserving order. Source files remain untouched — only the index changes.

### Changed

- **`mb-codegraph.py`** — the Python-only v1 path was extended with a tree-sitter adapter for 5 new languages. Same node/edge schema. Lazy parser loading per language through `_TS_PARSERS` cache.
- **`commands/mb.md`** — `/mb import`, `/mb graph`, `/mb tags` sections with full examples, dogfood outputs, and limitations.
- **`install.sh`** — now prints a hint for tree-sitter extras.

### Tests

- pytest: **96** (was 44 after v2.1) — +17 `test_import`, +21 `test_codegraph` (Python), +14 `test_codegraph_ts` (tree-sitter).
- bats: **208** (was 194) — +14 `test_tags_normalize`.
- shellcheck: 0 warnings. ruff: all passed.

### Gate v2.2 — passed ✅

1. ✅ `/mb import` on real JSONL (2573 events) — **0.127s** (target ≤30s).
2. ✅ `mb-codegraph.py` on `scripts/` — **0.068s** for 60 nodes + 487 edges (target ≤30s).
3. ✅ Tags normalization: `sqlite_vec → sqlite-vec` auto-merged at distance=1, 2 notes rewritten. Unknown tag → exit 2 drift signal works.
4. ✅ Full regression: 96 pytest + 208 bats + ruff + shellcheck clean.
5. ✅ VERSION 2.2.0, CHANGELOG updated.

### ADR pivots

- **ADR-006 updated (Stage 6.5):** tree-sitter originally started as deferred opt-in. After user feedback ("I often work with Node/Go") it was implemented in v2.2, with graceful degradation when grammars are absent. The Python path remained zero-dependency. See BACKLOG (Stage 6.5 shipped entry).

### Deferred to v3.x backlog

- Haiku-powered compression for `/mb import` summaries (currently deterministic first+last chars).
- Debug-session detection in `/mb import` for `lessons.md`.
- Type inference in `/mb graph` (edges are currently name-based and do not distinguish modules with same-named functions).
- tree-sitter grammars for C/C++/Ruby/PHP/Kotlin/Swift (add on demand via `_TS_LANG_CONFIG`).

## [2.1.0] — 2026-04-20

Hardening release: auto-capture when `/mb done` is forgotten, drift detection without AI, PII protection in notes, status-based decay for old plans and notes.

### Added

- **Auto-capture SessionEnd hook** (`hooks/session-end-autosave.sh`) — if a session closes without `/mb done`, the hook appends a placeholder entry to `progress.md`. Lock file `.memory-bank/.session-lock` is written by `/mb done` → the hook sees a fresh lock (<1h) and skips auto-capture. `MB_AUTO_CAPTURE` env: `auto` (default) / `strict` / `off`. Concurrent-safe through `.auto-lock` (30s TTL). Idempotent per `session_id`.
- **Drift checkers without AI** (`scripts/mb-drift.sh`) — 8 deterministic checkers (path, staleness, script_coverage, dependency, cross_file, index_sync, command, frontmatter). Output: `drift_check_<name>=ok|warn|skip` + `drift_warnings=N`. Exit 0 when 0 warnings, otherwise 1. `agents/mb-doctor.md` Step 0 = `mb-drift.sh` → LLM call only if `drift_warnings > 0`. Saves AI tokens.
- **PII markers `<private>...</private>`** in notes — block contents do not enter `index.json` (summary + tags filtered), and `mb-search` replaces them with `[REDACTED]` (inline) or `[REDACTED match in private block]` (multi-line). Unclosed `<private>` is fail-safe: tail to EOF is treated as private. Entries get `has_private: bool`. `--show-private` requires `MB_SHOW_PRIVATE=1` env (double confirmation). `hooks/file-change-log.sh` warns when a `.md` file with a `<private>` block is Write/Edit-ed.
- **Compaction decay `/mb compact`** (`scripts/mb-compact.sh`) — status-based archival: requires **age > threshold AND done-signal**. Active plans (not done) are **NOT archived** even if >180d — warning only. Done-signal (OR): file physically under `plans/done/`, OR a `✅`/`[x]` marker in `checklist.md`, OR mentioned as "done|closed|shipped" in `progress.md`/`STATUS.md`. Notes — `importance: low` + mtime >90d + no references in core files. `--dry-run` (default) reasons only; `--apply` executes and touches `.last-compact`. Entries under `notes/archive/` get `archived: bool`. `mb-search --include-archived` is opt-in for archive search.

### Changed

- **`agents/mb-doctor.md`** — Step 0 is now `mb-drift.sh`; LLM steps (1-4) run only when `drift_warnings > 0` or `doctor-full`.
- **`scripts/mb-index-json.py`** — parser for `<private>` blocks, `has_private: bool` + `archived: bool` fields in the entry schema.
- **`scripts/mb-search.sh`** — span-aware Python filter for REDACTED replacement. Added `--show-private` + `--include-archived`.
- **`settings/hooks.json`** — SessionEnd event added for auto-capture.
- **`commands/mb.md`** — `/mb done` writes `.session-lock`. Added `/mb compact` section with full status-based logic and examples.
- **`SKILL.md`** — "Private content" and "Auto-capture" sections.
- **`references/metadata.md`** — schema extended with `has_private` + `archived` fields.

### Tests

- bats: **194** (20 `test_compact` + 4 `test_search_archived` + 5 `test_search_private` + 20 `test_drift` + 12 `test_auto_capture` + regressions).
- pytest: **44** (7 PII + 2 archived + regressions).
- e2e: 18 install/uninstall (including SessionEnd hook roundtrip).
- shellcheck: 0 warnings (SC1091 info expected for `source _lib.sh`).
- ruff: all passed.

### Gate v2.1 — passed ✅

1. ✅ Auto-capture end-to-end: simulated SessionEnd → `progress.md` updated without `/mb done`.
2. ✅ `mb-drift.sh` on broken fixture: 7 warnings across 8 categories (≥5 target).
3. ✅ PII security smoke: `TOP-SECRET-LEAK-CHECK-GATE21` inside `<private>` → **0 matches** in `index.json`.
4. ✅ `/mb compact` dogfood: live bank is clean (0 candidates), artificial 150d done-plan → archived, 150d active-plan → not archived (safety works).
5. ✅ CI matrix `[macos, ubuntu]` × (bats + e2e + pytest) green.

### Deferred to backlog

- LLM upgrade for auto-capture (currently append-only; details are reloaded by `/mb start` from JSONL).
- `/mb done` weekly prompt for compaction checks.
- Pre-commit drift hook as a separate file (YAGNI; documented in `references/templates.md`).

## [2.0.0] — 2026-04-19

Large refactor: the skill becomes language-agnostic, tested, CI-covered, and integrated with the Claude Code ecosystem. Three concepts under one roof: **Memory Bank + RULES + dev toolkit**.

### Added

- **Language detection (12 stacks)**: Python, Go, Rust, Node/TypeScript, Java, Kotlin, Swift, C/C++, Ruby, PHP, C#, Elixir. `scripts/mb-metrics.sh` emits key=value metrics for any of them.
- **Override for project metrics**: `.memory-bank/metrics.sh` (priority 1 over auto-detect).
- **`scripts/_lib.sh`** — shared utilities (workspace resolver, slug, collision-safe filename, detect_stack/test/lint/src_glob). 7 functions, 36 bats tests.
- **`scripts/mb-plan-sync.sh`** and **`scripts/mb-plan-done.sh`** — automate plan↔checklist↔plan.md consistency through `<!-- mb-stage:N -->` markers.
- **`scripts/mb-upgrade.sh`** — `/mb upgrade` self-update for the skill from GitHub (git fetch → prompt → ff-only pull + reinstall).
- **`scripts/mb-index-json.py`** — pragmatic index for `notes/` (frontmatter) + `lessons.md` (H3 markers). Atomic write. PyYAML opt-in with fallback.
- **`mb-search --tag <tag>`** — tag filtering via `index.json`.
- **`/mb init [--minimal|--full]`** — unified initialization. `--full` (default) = `.memory-bank/` + `RULES.md` copy + stack auto-detect + `CLAUDE.md` + optional `.planning/` symlink.
- **`/mb map [focus]`** — scan the codebase and generate `.memory-bank/codebase/{STACK,ARCHITECTURE,CONVENTIONS,CONCERNS}.md`.
- **`/mb context --deep`** — full codebase content (default = 1-line summary).
- **Frontend rules (FSD)** and **Mobile (iOS + Android)** in `rules/RULES.md` and `rules/CLAUDE-GLOBAL.md`.
- **`MB_ALLOW_NO_VERIFY=1`** — bypass for `--no-verify` in `block-dangerous.sh`.
- **Log rotation** for `file-change-log.sh`: >10 MB → `.log.1 → .log.2 → .log.3`.
- **GitHub Actions** `.github/workflows/test.yml`: matrix `[ubuntu-latest, macos-latest]` × (bats + e2e + pytest) + lint job (shellcheck + ruff).
- **148 bats tests** (unit + e2e + hooks + search-tag), **35 pytest tests**, **94% total coverage**.

### Changed

- **`codebase-mapper` → `mb-codebase-mapper`** (MB-native): output path `.planning/codebase/` → `.memory-bank/codebase/`; 770 lines → 316 (−59%); 6 templates → 4 (STACK, ARCHITECTURE, CONVENTIONS, CONCERNS), each ≤70 lines.
- **`/mb update` and `mb-doctor`** no longer hardcode `pytest`/`ruff`/`src/taskloom/` — they use `mb-metrics.sh`.
- **`SKILL.md` frontmatter** — invalid `user-invocable: false` replaced by `name: memory-bank` with a three-in-one concept description.
- **`Task(...)` → `Agent(subagent_type=...)`** in all skill files. Grep check: 0 occurrences of `Task(`.
- **`mb-doctor`** fixes desynchronization primarily through `mb-plan-sync.sh`/`mb-plan-done.sh`; Edit is reserved for semantic issues.
- **`install.sh`** — always writes the `[MEMORY-BANK-SKILL]` marker when creating a new `CLAUDE.md` (previously only when merging into an existing one).
- **`mb-manager actualize`** — now calls `mb-index-json.py` instead of manually writing `index.json`.
- **`file-change-log.sh`** — removed `pass\s*$` from the placeholder regex (false positive); placeholder search now ignores Python docstrings.
- **`install.sh` banner**: `19 dev commands` → `18 dev commands` (after init-command consolidation).

### Deprecated

- (none — all deprecations in this release are full removals; see Removed)

### Removed

- **`/mb:setup-project`** — merged into `/mb init --full`. `commands/setup-project.md` removed.
- **Orphan agent `codebase-mapper`** — replaced with `mb-codebase-mapper`.
- **Hardcoded `pytest -q` / `ruff check src/`** in `commands/mb.md` and `agents/mb-doctor.md`.
- **All `Task(...)` invocations** in skill files (0 left).

### Fixed

- **E2E-found bug #1**: `install.sh` did not add the `[MEMORY-BANK-SKILL]` marker when creating a **new** `CLAUDE.md`. Result: `uninstall.sh` could not find the section to clean.
- **E2E-found bug #2**: `uninstall.sh` used the GNU-only `realpath -m` flag. BSD `realpath` on macOS failed. Fix: the manifest already stores absolute paths, so `realpath` is unnecessary.
- **Node `src_glob`**: brace-pattern `*.{ts,tsx,js,jsx}` replaced by space-separated globs for portable grep.
- **`mb-note.sh`**: name collision (two notes in one minute) now yields `_2/_3` suffixes (previously `exit 1`).
- **`file-change-log` false positives**: bare `pass` in Python, TODO inside docstrings.
- **shellcheck SC1003** in the awk hook block — rewritten through `index()` without nested single-quote escapes.

### Security

- **`block-dangerous.sh`** updated with `MB_ALLOW_NO_VERIFY=1` explicit opt-in override — previously `--no-verify` was blocked with no safe escape.
- **Secrets detection** in `file-change-log.sh` continues to work (`password|secret|api_key|token|private_key` in source code).

### Infrastructure

- **Dogfooding**: the skill now uses `.memory-bank/` in its own repository. The v2 refactor plan lives in `.memory-bank/plans/`, and sessions are closed through `/mb done`.
- **VERSION marker**: `2.0.0-dev` → `2.0.0` written by `install.sh` into `~/.claude/skills/memory-bank/VERSION`.
- **CI green** on macOS + Ubuntu, 0 shellcheck warnings, ruff all passed.

---

## [1.0.0] — 2025-10-XX (pre-refactor baseline)

- Initial Memory Bank skill: `.memory-bank/` structure, `/mb` roadmap command, 4 agents, 2 hooks, 19 commands.
- Python-first: hardcoded `pytest`, `ruff`, `src/taskloom/`.
- Orphan artifacts from GSD: `codebase-mapper`, `.planning/`.
- 0 automated tests.

[2.0.0]: https://github.com/fockus/claude-skill-memory-bank/releases/tag/v2.0.0
[1.0.0]: https://github.com/fockus/claude-skill-memory-bank/releases/tag/v1.0.0
