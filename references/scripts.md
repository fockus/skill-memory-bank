# Scripts reference

Every script under `scripts/`, grouped by area. `SKILL.md` keeps only the entry points agents call
directly; this file is the single full table (the doc-count test checks it against `scripts/`).

## Contents

- [Bank core](#bank-core)
- [Plans and specs](#plans-and-specs)
- [Work loop, review, drive and flow](#work-loop-review-drive-and-flow)
- [Graph and search](#graph-and-search)
- [Session memory](#session-memory)
- [Coordination and agreements](#coordination-and-agreements)
- [Install and maintenance](#install-and-maintenance)
- [Internal libraries](#internal-libraries)

## Tools — shell scripts

All scripts live in `scripts/` next to this `SKILL.md`. In global installs, the bundle is typically available through host aliases:
- Claude Code: `~/.claude/skills/memory-bank/`
- Codex: `~/.codex/skills/memory-bank/`
- Cursor: `~/.cursor/skills/memory-bank/`

Scripts work with `.memory-bank/` in the current directory or through the `mb_path` argument.

### Bank core

| Script | Purpose |
|--------|---------|
| `_lib.sh` | Shared helpers sourced by other scripts |
| `_mb_skill_python.py` | Interpreter bootstrap for Python entry points: re-execs once under `$MB_PYTHON` or the wheel install's `<prefix>/bin/python3` when a bare `python3` cannot import `memory_bank_skill` |
| `_install_options.sh` | Sourced by `install.sh`: install options and file ownership when no previous install manifest exists (`pipx install --force`, a cleaned Homebrew keg) |
| `mb-context.sh [--deep]` | Build context from core files (`STATUS` + `plan` + `checklist` + `RESEARCH` + codebase summary). `--deep` shows full codebase docs, `--full` disables the per-file byte cap (`MB_CONTEXT_MAX_BYTES` / `context_max_bytes`, default 12 KB) |
| `mb-statusline.py [--install]` | Claude Code statusline showing context-window fill `%` (`used/limit`, 1M-aware) + model · branch · project. Reads the status JSON on stdin; `--install` wires it into `~/.claude/settings.json` (backup, no clobber) |
| `mb-search.sh <q> [--tag t]` | Keyword search across the memory bank. `--tag` filters via `index.json` |
| `mb-note.sh <topic>` | Create `notes/YYYY-MM-DD_HH-MM_<topic>.md`. Collision-safe (`_2` / `_3`) |
| `mb-idea.sh <title> [HIGH\|MED\|LOW]` | Capture a new idea in `backlog.md` with monotonic `I-NNN` |
| `mb-idea-promote.sh <I-NNN>` | Promote an idea (I-NNN) into an active plan |
| `mb-adr.sh <title>` | Capture an Architecture Decision Record in `adr.md` (ADR-NNN) |
| `mb-adr-migrate.sh [--dry-run\|--apply] [mb_path]` | Move ADR blocks/lines from `backlog.md` into `adr.md` verbatim, sorted by ID (idempotent, `.bak` backup) |
| `mb-init-bank.sh` | Deterministic, locale-aware `.memory-bank/` scaffolder |
| `mb-config.sh` | Memory Bank config resolver + locale auto-detector |
| `mb-metrics.sh [--run]` | Language-agnostic metrics (12 stacks). `--run` captures `test_status=pass\|fail` |
| `mb-index.sh` | Registry of all entries (core + notes/plans/experiments/reports) |
| `mb-index-json.py` | Build `index.json` (frontmatter notes + lessons headings). Atomic write |
| `mb-drift.sh` | 8 deterministic drift checkers (path, staleness, script coverage, dependency, cross-file, index sync, command, frontmatter) |
| `mb-progress-chain.sh` | `--rebuild-tail` / `--verify` the `progress.md` append-only hash chain (`index.json:progress_chain`); CRITICAL drift on tamper (handoff-v2) |
| `mb-rules-check.sh` | Deterministic rules enforcement (SRP / Clean Architecture / TDD delta) |
| `mb-rules.sh render\|sync\|list\|enable\|disable\|add\|remove\|init` | Managed `## Key rules` block at the top of CLAUDE.md / AGENTS.md (after the language block). `render --target=project\|global` prints it; `sync --scope=project\|user` writes existing project / global host files; the selection subcommands edit the scope's `key_rules` profile field and re-sync (`/mb rules`, install onboarding `init --interactive`) |
| `mb-done-gates.sh` | Mandatory `/mb done` gate set (tests + rules + placeholder scan); `--force --reason` records a NOTE in `progress.md` (handoff-v2) |
| `mb-test-run.sh [--changed-since <ref>] [--files <list>]` | Structured test runner with per-stack output parsing → strict JSON; runs every detected stack (bats + pytest + go); the flags run only tests related to the changed files (full-suite fallback with `reason`) |
| `_test_select.sh` | Helper sourced by `mb-test-run.sh`: test-stack detection and targeted test selection (naming convention + code graph) |
| `mb-find-polluter.sh <path> <test_glob>` | Bisect which test creates an unwanted file/state (runs each test file via `npm test`, stops at the first polluter). Used by `mb-debugger`; adapted from superpowers (MIT) |
| `mb-checklist-prune.sh [--apply]` | Compact `checklist.md` to the v2 format — fold a plan's per-stage blocks into one `## <title> — k/n` block, move closed plans and fully-done `plans/done`-linked sections **verbatim** into `progress.md`. Cap `MB_CHECKLIST_MAX_LINES` → `.mb-config` `checklist_max_lines=` → 100; still over cap → exit 3 with a per-plan diagnostic (live work is never cut). **Rule: `checklist.md` = open TODO only; commit hashes / test counts / closeouts go to `progress.md`.** Composed by `mb-core-cap.sh fix` |
| `mb-checklist-v2.py <cmd>` | Single reader/writer for the `checklist.md` v2 format (`plan` / `apply` / `upsert` / `flip` / `extract`), used by `mb-checklist-prune.sh`, `mb-plan-sync.sh`, `mb-plan-done.sh` and `mb-work-checkbox.sh` |
| `mb-status-rotate.sh [--keep N] [--dry-run|--apply]` | Archive dated `## ` sections of `status.md` past the newest N (default 3) into `progress.md` as `## [status archive] …` blocks, through the locked append-only helper. Undated sections (`## Current phase`, `## Open backlog`) never move. Called by the actualize step (`/mb done`, `/mb update`) before `status.md` is rewritten |
| `mb-core-cap.sh check\|fix [--mb <path>] [--json]` | Hard line caps for the two core registries (AGR-043): `status.md` = current state, `checklist.md` = plans in flight, everything else in `progress.md`. `check` prints `status_lines/status_cap checklist_lines/checklist_cap over=<csv|none>` (exit 1 when over); `fix` composes `mb-status-rotate.sh --apply` + `mb-checklist-prune.sh --apply` and re-checks — exit 1 = still over (dispatch MB Manager `actualize --strict`), exit 3 = live plans do not fit (owner decision, never a trim). Caps `MB_STATUS_MAX_LINES` / `MB_CHECKLIST_MAX_LINES` → `.mb-config` → 60 / 100; `MB_CORE_CAP=off` disables |
| `mb-compact.sh [--apply]` | Status-based compaction decay — archive old done plans + low-importance notes |
| `mb-handoff.sh` | Handoff capsule manager — `--actualize` / `--read` / `--rotate` a ≤1500-byte session capsule under `handoff/` (handoff-v2) |
| `mb-tags-normalize.sh [--apply]` | Levenshtein-based tag synonym detection + merge across `notes/` |
| `mb-roadmap-sync.sh` | Regenerate `roadmap.md` autosync block from `plans/*.md` frontmatter |
| `mb-traceability-gen.sh` | Regenerate `traceability.md` from specs + plans + tests |
| `mb-language.py` | `/mb language`: per-project response / code-comment language as a managed block at the top of the project's `AGENTS.md` and `CLAUDE.md` (`set`, `off`, `show`) |
| `mb-context-slim.py` | Slim a full agent prompt on stdin → terse version on stdout |
| `mb-cost-report.py [--project <dir>] [--since N] [--json]` | `/mb cost` engine: mine Claude Code transcripts (`~/.claude/projects/<slug>/`) into per-session, per-subagent-role and per-work-item (`mb-work-state.sh init` → `mb-work-checkbox.sh flip`) cost. Parsing in `memory_bank_skill/cost_report.py` |
| `mb-effort-report.sh [--json] [--repo <dir>] [--since <ref> [--until <ref>]] <session.jsonl>…` | Per-task effort: tokens (usage deduped per message id, subagent transcripts folded in), wall / active duration, turns, tool calls, dispatches, test / full-suite runs, test cases and docs written; with a git range — tests, docs and code lines added. Read-only, no network |
| `mb-profile.sh` | Rule profile manager: `init`, `show`, `path`, `validate`, `set` — user/project scopes |
| `mb-glossary.sh` | Atomic upsert of a single `<term> — <definition>` line in `<bank>/glossary.md`; term and definition are read from files, so no quoting loss (REQ-017) |
| `mb-secret-scan.sh` | Canonical secret-scan dispatcher (`transcript` and `brief-input` policies); patterns are single-sourced from `mb-import.py`, never a second regex set |
| `mb-backlog-state.sh` | Backlog state machine, hierarchy, and briefs: `transition <I-NNN> <STATE>`, `annotate --brief --parent` |

### Plans and specs

| Script | Purpose |
|--------|---------|
| `mb-plan.sh <type> <topic>` | Create `plans/YYYY-MM-DD_<type>_<topic>.md` with `<!-- mb-stage:N -->` markers |
| `mb-plan-sync.sh <plan>` | Synchronize a plan ↔ checklist + roadmap + status (idempotent) |
| `mb-plan-done.sh <plan>` | Close a plan: `⬜→✅` + move to `plans/done/` |
| `mb-ears-validate.sh <file>` | Validate REQ bullets against the 5 EARS patterns |
| `mb-req-next-id.sh` | Emit the next monotonic `REQ-NNN` identifier |
| `mb-sdd.sh <topic>` | Create a Kiro-style spec triple under `specs/<topic>/` (requirements / design / tasks). Scaffolds an optional `## Scenarios` (GIVEN/WHEN/THEN) section |
| `mb-scenario-extract.py <file>` | Extract `<!-- mb-scenario:N -->` GIVEN/WHEN/THEN blocks → normalized test-plan (JSON Lines: covers + steps + stable `test_id`). `--validate` checks present scenarios are well-formed. Opt-in layer; absent scenarios → empty/no-op |
| `mb-spec-validate.sh <topic\|spec-dir\|spec-file>` | Validate spec triple integrity (EARS, parseable tasks, per-task Covers/DoD/Testing, no REQ orphans). Present GIVEN/WHEN/THEN scenarios are structure-checked; `--require-scenarios` (opt-in) enforces ≥1 scenario per REQ; `--require-tests` (opt-in) enforces ≥1 covering test per REQ (scans `<repo>/tests`, `<mb>/tests`, or `MB_TEST_ROOTS`). `--json` mode for structured output |
| `mb-spec-tasks-migrate.sh <topic\|tasks-file> [--apply\|--dry-run]` | Migrate legacy `## N. ...` tasks to `<!-- mb-task:N -->` format. Dry-run default, --apply writes backup before changes, idempotent |
| `mb-openspec.sh` | Thin dispatcher for the OpenSpec import adapter: `import\|list\|status\|sync` → `mb-openspec.py` |
| `mb-openspec.py` | One-way OpenSpec `changes/<id>/` → MB spec triple `specs/<topic>/` import + drift-aware `list`/`status`/`sync` (opt-in `--normalize` LLM slot layer) |
| `mb-brief.sh` | Deterministic helper behind `/mb brief`: `create` (topic + candidate + `--input` documents), `context`, `accept` — the file effects of the brief stage live in a script, not a prompt |
| `mb-brief-validate.sh` | Structural validator for a brief one-pager — section order, required fields, single-page budget |
| `mb-estimate-check.sh` | Deterministic size-estimate validator: the `/mb discuss` context estimate and the spec-triple / candidate budget gate. No LLM, no PyYAML |
| `mb-interview-artifact-check.sh` | Deterministic structural validator for `/mb discuss` interview artifacts — `plan`, `--require-closed`, `--print-digest`. No LLM |
| `mb-interview-artifact-write.sh` | Deterministic writer for `/mb discuss` file effects: atomic publish, and byte-identity of a rejected target is a script-proven fact rather than a prompt promise |
| `mb-sdd-candidate.sh` | Candidate lifecycle for `/mb sdd` generation: the seam separating a GENERATED `tasks.md` from an ACCEPTED one (`<bank>/tmp/sdd/<topic>/tasks.candidate.md`) |
| `mb-sdd-self-check.sh` | Deterministic executor of the C8 generation self-check battery over a published draft triple, so `commands/sdd.md` decides draft→ready by exit code, not prompt judgement. Pure checker — writes nothing |
| `mb-sdd-review-result.sh` | Executable owner of the spec-review exit codes: validation, the append-only record, and 0/1/2 — `commands/sdd.md` owns only the model dispatch |
| `mb-sdd-layers-render.py` | Deterministic renderer for the test-layer tasks and the `## Quality DoD` block |
| `mb-quality-dod.sh` | Render the one canonical `## Quality DoD` block; the orchestrator runs it ONCE per item and hands the same file to implementer, reviewer, and judge |
| `mb-rules-resolve.sh` | Resolve the rule sources a spec is judged against — `discovery` and `validation` modes behind one JSON contract |
| `mb-contract-gate.sh` | Execute a spec's Contract-checkers registry (the fenced ```json``` block of the `**Layer:** contract` task) |

### Work loop, review, drive and flow

| Script | Purpose |
|--------|---------|
| `mb-pipeline.sh` | Manage the project's `pipeline.yaml` (spec §9) |
| `mb-pipeline-validate.sh` | Structural validation for `pipeline.yaml` (spec §9) |
| `mb-work-resolve.sh` | Resolve `<target>` arg into a plan/spec path (spec §8.2) |
| `mb-work-range.sh` | Emit per-stage indices (plan mode) or per-sprint paths |
| `mb-work-plan.sh` | Emit per-stage execution plan as JSON Lines (spec §8) |
| `mb-work-budget.sh` | Token budget tracker for `/mb work --budget` |
| `mb-work-protected-check.sh` | Match files against `pipeline.yaml:protected_paths` |
| `mb-work-review-parse.sh` | Validate reviewer output for `/mb work` review-loop |
| `mb-work-severity-gate.sh` | Apply `pipeline.yaml:severity_gate` to review counts |
| `mb-work-trend.sh` | Review-cycle trend: weighted score (10×blocker + 3×major + 1×minor) vs the previous cycle → `improving` / `stagnant` / `regressing` / `null` (work-loop-v2 G2) |
| `mb-work-pivot.sh` | Decide `refine` / `pivot_in_role` / `pivot_via_architect` from the trend + cycle count, instead of grinding the same fix (`pivot_after_cycles`, `pivot_escalate_to_architect_on`) |
| `mb-work-contract.sh` | Per-stage "what done means" contract under `<bank>/contracts/<topic>_stage-<N>.md` — `create` / `read` / `validate` / `path`; the reviewer can judge against it |
| `mb-workflow.sh` | Resolve the active workflow + per-step `model`/`thinking` config from `pipeline.yaml` for `/mb work` |
| `mb-drive.sh` | Autonomous goal-driven loop: `next` reads goal-acceptance + the firewall + work-state + budget and emits exactly one action (`implement` / `repair` / `pivot` / `stop_*`). Stateless, fail-closed — `stop_success` requires a green firewall AND 100% acceptance (REQ-DR-014) |
| `mb-drive-preflight.sh` | Initialize missing drive components or resume the same run without resetting cycles, steps, limits, or spend; refuse corrupt state and conflicting resume limits |
| `mb-drive-stop.sh` | Drive-loop stop telemetry + per-run drive state: `arm` marks a drive live (arms the Stop-hook resume-gate), `record --reason\|--action` writes the stop reason once into the `mb-flow` fence, `progress.md`, and the run's state slot (REQ-DR-033/034) |
| `mb-work-state.sh` | Durable `/mb work` loop-state + `max_cycles` enforcement; optional per-run isolation/claim under `MB_WORK_PARALLEL` |
| `mb-work-checkbox.sh` | Deterministic DoD-checkbox flip, gated on the run's work-state phase (single-writer for `checklist.md`) |
| `mb-work-diff.sh` | Baseline-scoped diff for a `/mb work` run — feeds verify/review with the stage's own changes only |
| `mb-work-progress-append.sh` | Locked, atomic, append-only writer for `<bank>/progress.md` (safe under concurrent runs) |
| `mb-work-codex-preflight.sh` | Fail-safe codex CLI availability/auth health-check before a cross-model review wave |
| `mb-agent-caps.sh` | Capability-aware dispatch: resolve CLI transport (pi/opencode/codex/claude-agent) + concrete model per role by probing CLI presence and model availability |
| `mb-reviewer-resolve.sh` | Pick the active reviewer agent name |
| `mb-review.sh` | Review orchestrator entry point: deterministic 5-section payload assembly (diff + calibration examples + test evidence + auto-findings), model-agnostic, `--emit-payload`/`--input` |
| `mb-review-cache.sh` | Touched-file test-evidence cache: `compute_touched_sha` + TTL HIT/MISS resolution under `.memory-bank/tmp/` |
| `mb-review-examples.sh` | Layered calibration-example loader: project-over-skill precedence by `example_id`, fence-aware parser, per-category rotation, path-traversal/symlink-safe; renders the `## Calibration examples` payload section |
| `mb-diff-scope.sh` | L5 diff-scope backstop: compare changed files against an allowed glob scope and report out-of-scope changes (exits 0, JSON report; ADR-4) |
| `mb-fanout.sh` | Stateless fan-out helper: run N branch prompts concurrently via background jobs, capture JSON results, and aggregate into one object — exit-code authority for failed branches (REQ-DF-084) |
| `mb-flow-branch-sink.sh` | Per-branch result sinks with write-once discipline for `<!-- mb-flow -->` fence: each parallel branch writes to its own `.mb-flow/branch-<i>.json` to prevent races (ADR-9) |
| `mb-flow-route.sh` | Deterministic route resolver: apply route-floor rules (REQ-DF-022) to an LLM-proposed or user-supplied route and write the resolved `route:` into the `<!-- mb-flow -->` fence in status.md |
| `mb-flow-sync.sh` | Regenerate the `<!-- mb-flow -->` runtime fence in status.md: emit route, phase, checks, gate, last-verify-sha, stall-count, and stop-reason fields (REQ-DF-030/031/032, REQ-DR-033) |
| `mb-flow-verify.sh` | THE firewall fan-out: run route-relevant check runners, normalize verdicts via `mb-work-severity-gate.sh`, and exit 0/1/2 — the sole exit-code authority of the dynamic-flow firewall (ADR-3) |
| `mb-goal-acceptance.sh` | L5 goal-acceptance aggregator: parse `## Acceptance criteria` checkboxes in goal.md and report whether every criterion is satisfied (exits 0, JSON report; REQ-DF-042) |
| `mb-goal-validate.sh` | Validate a goal.md before a Dynamic Flow run: enforce required sections, acceptance-criteria items, and field completeness — fail-loud exit 1 on malformed goals (REQ-DF-004) |
| `mb-lint-run.sh` | L5 lint runner: auto-detect project stack via `mb-metrics.sh`, map to linter (ruff/shellcheck), run it, and report findings (exits 0, JSON report; ADR-3; unknown stack = SKIP) |
| `mb-no-todo.sh` | L5 residual-placeholder runner: scan target files for TODO/FIXME/HACK markers, reusing `mb_rules_check_lib.sh::scan_placeholders` patterns and exemptions (exits 0, JSON report; REQ-DF-042) |
| `mb-subinvoke-resolve.sh` | Resolve the per-agent shell sub-invoke command template for the active agent (mirrors `mb-reviewer-resolve.sh`); used by `mb-fanout.sh` to bake `--cmd` when the operator does not supply one (REQ-DF-082) |

### Graph and search

| Script | Purpose |
|--------|---------|
| `mb-codegraph.py` | Code graph orchestrator. Extractors in `memory_bank_skill/`: `codegraph_python` (stdlib `ast`), `codegraph_shell` (Bash/Bats via stdlib `re`) — both always on — `codegraph_treesitter` (multi-language, opt-in), `codegraph_analytics` (communities/cohesion/betweenness, optional networkx — `hooks/mb-semantic-bootstrap.sh` installs it with tree-sitter, and the builder re-execs under that venv), `codegraph_cochange` (git co-change edges via opt-in `--cochange`) |
| `mb-graph.sh` | Short front door the hooks print: `who-calls\|impact\|tests <Symbol>`, `status`, `search "<query>"` (one token → BM25, phrase → embeddings); finds the bank from any project subdirectory; exit 4 = no Memory Bank |
| `mb-graph-query.py` | Query `codebase/graph.json`: `neighbors`, `impact`, `tests`, `explain`, `summary` with JSON/markdown output |
| `mb-code-context.py` | GraphRAG-lite evidence pack: optional semantic candidates + graph expansion + text/read fallback |
| `mb-semantic-search.py` | Semantic code search over `graph.json` (+ wiki): `--backend auto` (embeddings when `fastembed` installed, else pure-Python BM25 — the $0 zero-dep base), `--source-only`, disk cache in `.index/codesearch/` warmed by `/mb graph --apply`. Modules in `memory_bank_skill/`: `semantic_search`, `semantic_embeddings`, `codegraph_loader` |
| `mb-wiki.py` | `/mb wiki` engine (deterministic prep): `plan`/`packs`/`write-article`/`merge-edges`/`index`. LLM articles + surprising-connection edges via host subagents. Modules: `wiki_evidence`, `wiki_store` |

### Session memory

| Script | Purpose |
|--------|---------|
| `mb-session-doctor.sh` | Diagnose session-memory subsystem health (unsummarized sessions, missing index/adapters, legacy stubs) |
| `mb-session-spend.sh` | Session token-spend tracker (sprint context guard) |
| `mb-session-recent-rebuild.sh` | Regenerate `session/_recent.md` from `session/*.md` (keeps newest `MB_RECENT_KEEP`; deterministic, idempotent) |
| `mb-recap.sh <sid>` | `/mb recap`: reconstruct a full `progress.md` entry from `session/<sid>*.md` via one Haiku call, replacing that session's auto-capture stub idempotently (`recapped` frontmatter). Missing session → exit non-zero, no writes; real entry already present → refuse |
| `mb-conflicts.sh [--judge] [--threshold N]` | `/mb conflicts`: report memory entries with high lexical overlap **and** opposing/replacement assertions (en+ru markers) as conflict candidates — `$0` pass (token-set Jaccard > `N`, default 0.3) over `notes/` + `lessons.md` + recent `progress.md`, zero LLM calls. `--judge` confirms/rejects each pair via one Sonnet call + prints a suggested `[SUPERSEDED: YYYY-MM-DD -> <ref>]` marker. PRINT-ONLY — never writes to any bank file |
| `mb-consolidate.sh [--apply] [--days N]` | `/mb consolidate`: fold sessions older than `N` days (default 30) that cluster by shared files / lexical overlap into 5–15 line `notes/` candidates, archive those session files VERBATIM → `session/archive/`, and move their contiguous auto-capture progress STUBS VERBATIM → `progress-archive.md`. Zero LLM calls. Dry-run is the DEFAULT (writes nothing — bank byte-identical); `--apply` performs it. Real progress entries are immutable and never move |
| `mb-auto-commit.sh` | Opt-in auto-commit of `.memory-bank/` after `/mb done` (`MB_AUTO_COMMIT=1` or `--force`) — 4 safety gates, MB-only staging, never pushes |
| `mb-freshness.sh [--porcelain\|--stop-nudge\|--banner]` | Deterministic MB-vs-code drift alarm (`behind`/`dirty`); drift-gated Stop nudge + SessionStart banner (`MB_DRIFT_WARN_COMMITS`/`MB_DRIFT_WARN_DIRTY_LINES`, opt-out `MB_FRESHNESS_BANNER=off`). See `docs/concepts/session-memory.md` for the auto-commit recipe |
| `mb-session-prune.sh` | Archive contentless session stubs out of `<bank>/session/` into `session/archive/stubs/`; dry-run is the default, `--apply` performs the move. Also flags/repairs bloated files (`>MB_SESSION_BLOAT_BYTES`) with post-`## Summary` bullets |
| `mb-session-repair.sh [--apply] <file>` | Repair a session file corrupted by the legacy append-after-`## Summary` bug: move turn-bullets back into `## Live log`, reset `summarized=false`, re-cap over-long bullets, keep a `archive/pre-repair/` backup. Dry-run default, idempotent, fail-safe |
| `mb-settings-ensure-timeout.py` | Surgically ensure the SessionEnd `mb-session-end.sh` hook command carries a per-command `timeout` so the Haiku summarizer is not SIGKILLed before writing `## Summary` |

### Coordination and agreements

| Script | Purpose |
|--------|---------|
| `mb-coord.sh active [--tail N]` / `mb-coord.sh append --type <T> --title <t>` | Read/write the cross-session board `COORDINATION.md` without loading it: `active` prints active FREEZEs (tagged, plus `[legacy]` ones declared in a **bolded** body marker), HANDOVERs with no ACK, the last N entries (default 3) and a `board: <entries>, <bytes>` line — a few hundred bytes instead of hundreds of KB. `append` writes `## <TYPE> · YYYY-MM-DD · <title>` through a locked atomic append. No board → `no board`, exit 0 |
| `mb-agree.sh` | Single writer for the running list of agreements (`agreements.md`): `add\|defer\|reject\|question\|resolve\|list\|sync` + managed-block sync |

### Install and maintenance

| Script | Purpose |
|--------|---------|
| `mb-deps-check.sh [--install-hints]` | Preflight dependency checker (python3, jq, git + optional tree-sitter, networkx) |
| `mb-agent-render.py` | Installer helper: builds the installed form of an agent by placing the partials listed in its `compose:` frontmatter above its body (`--host` adapts the frontmatter for OpenCode, pi, or Codex; for Codex it writes a TOML role) |
| `mb-migrate-v2.sh` | One-shot v1 → v2 migrator for `.memory-bank/` |
| `mb-migrate-structure.sh` | One-shot v3.0 → v3.1 structure migrator for `.memory-bank/` |
| `mb-import.py` | Claude Code JSONL → Memory Bank bootstrap importer |
| `mb-upgrade.sh [--check\|--force]` | Self-update the skill from GitHub |
| `mb-version-check.sh [--force]` | Is a newer release out? Compares local `VERSION` against the latest GitHub Release (PyPI JSON as fallback), cached with a TTL. Prints strict JSON (`current`/`latest`/`update_available`/`flavor`/`upgrade_command`/`checked_at`/`source`). Always fail-open — exit 0, silent, never blocks a session. Off: `MB_UPDATE_CHECK=off` |

### Internal libraries

Sourced helpers and Python modules behind the entry points above — not called by agents directly.

| Script | Purpose |
|--------|---------|
| `mb_rules_check_lib.sh` | Shared helper library for `mb-rules-check.sh` |
| `mb_rules_sync_lib.sh` | File writers behind `mb-rules.sh sync` (Key rules, RULES.md settings, AGENTS.md and per-host rule files; keeps adapter ownership of rewritten rule files) |
| `mb_rules_check_profile.sh` | Profile resolution and output emitters for `mb-rules-check.sh` |
| `mb_rules_check_baseline.sh` | Baseline SRP / Clean Architecture / TDD checks for `mb-rules-check.sh` |
| `mb_rules_check_stack.sh` | Stack-aware and FSD checks for `mb-rules-check.sh` |
| `mb_rules_check_arch.sh` | Architecture-preset import checks (preset `check` block: clean, modular-monolith, microservices, ddd, hexagonal, mobile-udf) for `mb-rules-check.sh` |
| `mb_work_models.py` | Per-role model resolver for `mb-work-plan.sh` (cost tiers × host `model_profiles`, AGR-074) and the `cost`/`cost_tiers`/`model_profiles`/`hosts` schema for `mb-pipeline-validate.sh` |
| `mb_config_hosts.py` | Host templates for `mb-pipeline.sh init --host` (`/mb config init`) and the role → model matrix of `mb-pipeline.sh matrix` (`/mb config show`), AGR-074 |
| `mb_work_adapt.py` | ADaPT-lite for `/mb work`: `adapt:` config + schema, `complexity_escalation` parsing (`parse`), sub-items in run state behind `mb-work-state.sh split`/`sub-done`/`adapt-check` and the `done` gate (`references/adapt.md`) |
| `mb_work_waves.py` | Parallel `wave` per item for `mb-work-plan.sh` from `Files:` / spec `Scope:` sets and `Blocked-by` (AGR-073) |
| `mb_work_items.py` | Shared parser for plan stages (`<!-- mb-stage:N -->`) and spec tasks (`<!-- mb-task:N -->`); CLI emits JSON Lines |
| `mb_req_id.py` | Shared REQ-ID grammar (single source of truth) used by traceability / spec-validate / ears-validate. Supports prefixed schemes (`REQ-RS-008`), distinguishes a definition from a mid-line mention, expands `REQ-RS-002/003` slash-shorthand, and maps pytest identifiers (`req_rs_008`) onto canonical ids |
| `mb-work-slots.sh` | Sourced helper: per-run state/budget/drive slot-path resolution + source→run claim index (gated behind `MB_WORK_PARALLEL`) |
| `mb_openspec_model.py` | Dataclasses shared by the OpenSpec adapter's parser/converter |
| `mb_openspec_parse.py` | Read-only OpenSpec change parser (`parse_change`, `compute_source_hash`) |
| `mb_openspec_convert.py` | Deterministic OpenSpec → MB spec-triple converter (anchors, EARS classify, re-import anchor reuse) |
| `mb_openspec_normalize.py` | Opt-in `--normalize` LLM slot layer + source-hash cache for the OpenSpec adapter (fail-open) |
| `mb_graph_query_core.py` | Core graph loading, matching and payload builders for `mb-graph-query.py` |
| `mb_graph_query_render.py` | Markdown summary renderers for graph-query output |
| `mb_code_context_core.py` | Core evidence-pack orchestration for `mb-code-context.py` |
| `mb_brief_candidate.py` | Candidate inspection for `mb-brief.sh` (contract C6 steps 4–5) |
| `mb-estimate-lib.sh` | Sourced parsers for `mb-estimate-check.sh` (context-file and spec/candidate estimates). Not a standalone entry point |
| `mb-sdd-self-check-eval.sh` | Sourced half of the C8a battery: how ONE `**Eval:**` declaration is classified in a given phase (`--phase generation` requires red, `--phase done` requires green) |
| `mb_sdd_judge_journal.py` | Judge / override / status half of the spec-review journal (append-only, symlink-safe) |
| `mb_quality_dod.py` | The `## Quality DoD` renderer core — one renderer, three receivers |
| `mb_rules_resolve.py` | Rule-source resolution core for `mb-rules-resolve.sh` |
| `mb_rubric_quality.py` | Drops the stock review-rubric bullets of a principle / Testing Trophy the project switched off (`mb-profile.sh quality`, AGR-076); imported by `mb_rules_resolve.py`. |
| `mb_contract_gate.py` | Runner for the Contract-checkers registry |
| `mb_contract_registry.py` | The Contract-checkers registry — one reader, one schema, two consumers |
| `mb-work-state-eval.sh` | Sourced eval-first layer for `mb-work-state.sh`: the red→green Eval gate. Not a standalone entry point |
| `mb-work-state-lib.sh` | Sourced helpers for `mb-work-state.sh` that shell out to external tooling (pipeline YAML, uuid). Not a standalone entry point |
| `mb_work_eval_proof.py` | Canonical eval-proof payload for the `mb-work-state` red→green gate |
| `mb_work_source.py` | Shared declaration-source resolution for work-state init and Eval; canonicalizes relative locators before they can change with cwd |
| `mb_work_plan_wrapper.py` | Wrapper-plan resolution for `mb-work-plan.sh` (`linked_spec` / `<!-- mb-stage:N -->`) |
| `mb_backlog_state_engine.py` | Backlog parser + state engine behind the backlog scripts |
| `mb_backlog_validate.py` | Backlog metadata validation: the brief gate (REQ-007) + single-line safety |
| `mb_roadmap_group.py` | Group-section rendering + progress aggregation for `mb-roadmap-sync.sh` |
| `mb_roadmap_order.py` | Pure ICE-component parsing + priority ordering for `mb-roadmap-sync.sh` |
| `mb_roadmap_plans.py` | Plan-frontmatter parsing + collection for `mb-roadmap-sync.sh` |
| `mb_roadmap_render.py` | Fence handling, bootstrap transfer, and atomic publish for `mb-roadmap-sync.sh` |
| `mb_spec_validate_v2.py` | v2 / C8 battery gates for `mb-spec-validate.sh` |
| `mb_spec_validate_tasks.py` | Per-task structural checks 3–6 for `mb-spec-validate.sh` |
| `mb_spec_validate_structural.py` | Scope classification + structural Eval grammar (REQ-049) |
| `mb_spec_validate_scope_eval.py` | I-174 gate: a task's `**Eval:**` must actually run the test files its `**Scope:**` claims |
| `mb_spec_validate_layers.py` | Test-layer gates C3/C4 and the Contract-checkers schema |
| `mb_spec_validate_graph.py` | `blocked_by` dependency-graph gates (REQ-052 / C8.5) |
| `mb_pipeline_validate_core.py` | Pipeline config validation core for `mb-pipeline-validate.sh` |
| `mb_pipeline_validate_blocks.py` | Per-block pipeline validators (budget … named-pipeline metadata) |
| `mb_pipeline_minimal_yaml.py` | PyYAML-optional minimal loader for `pipeline.yaml` — the zero-dep base |
| `mb_fs_atomic.py` | One atomic file-publish primitive, shared by every writer |
