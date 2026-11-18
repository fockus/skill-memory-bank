<!-- mb-key-rules:start -->
<!-- mb-stamp: 5.3.1-e6fc738f -->
## Key rules — project overrides

Global Key rules apply with these differences:
- Clean Architecture: Infra → App → Domain, never backward; Domain has 0 external deps
- English for everything written to the repo: code comments, commit messages, PR titles and descriptions; replies to the user stay in Russian (your rule)
- Replaces the global line: `architecture`.

Details: `.memory-bank/RULES.md`.
<!-- mb-key-rules:end -->

# Memory Bank Skill

Long-term project memory through `.memory-bank/`, engineering rules, SDD specs, executable `/mb work` tasks, verification, review, and session persistence.

## Hard Rules

1. Resolve the active Memory Bank before project work and say its state in your first reply.
   - Existing bank → `[MEMORY BANK: ACTIVE]`.
   - No bank → `[MEMORY BANK: ABSENT]`; do not initialize unless explicitly requested.
2. Read the project rules and Memory Bank context before implementation:
   - global rules: `rules/RULES.md` from this skill bundle;
   - project overrides: `<repo>/AGENTS.md`, `<repo>/RULES.md` or `<bank>/RULES.md` when present;
   - core context: `<bank>/status.md`, `checklist.md`, `roadmap.md`, `research.md` when present (the resolver also detects legacy-cased layouts).
3. Size the task first (`references/effort-tiers.md`, SKILL.md § Task routing). New logic at standard+ follows TDD — failing test first, then implementation, then verification; a small task gets one test per stated behavior; a trivial edit needs no new test.
4. Do not bypass an existing plan/spec. If work comes from Memory Bank, execute through `/mb work` or the equivalent scripts.
5. If `.memory-bank/COORDINATION.md` exists, parallel sessions share the working tree: read the board with `scripts/mb-coord.sh active` (not the whole file) before stages, commits, and shared-file edits; scoped `git add` only (never `-A`); obey FREEZE entries. Protocol: `references/coordination.md`.

## `/mb work` Gate

The gate applies when the task refers to an existing plan or spec in the bank (the user says implement, fix, continue, resume, next step, go by the plan, execute the spec, or similar about it). Without a plan or spec, route by tier — `references/effort-tiers.md` (SKILL.md § Task routing): trivial and small tasks are done inline. When the gate applies:

1. Resolve workflow from `<bank>/pipeline.yaml` with `scripts/mb-workflow.sh`.
2. Resolve target/range with `scripts/mb-work-resolve.sh` and `scripts/mb-work-plan.sh`.
3. Treat `specs/<topic>/tasks.md` blocks marked `<!-- mb-task:N -->` as executable source of truth.
4. If using a wrapper plan, it must have `linked_spec` or `<!-- mb-stage:N -->` markers. If not, stop and fix the wrapper before coding.
5. Follow resolved steps exactly. For governed workflows this means: `implement → verify → review → judge → fix/backlog → done`.
6. Dispatch the resolved `agent` by name with the exact `model` from `pipeline.yaml`/JSON lines; do not use fuzzy model names. `thinking` maps to the agent's `effort:` frontmatter in Claude Code.
7. Do not claim completion until configured verification/review/judge gates are satisfied, or the user explicitly chooses a simpler workflow.

Inline implementation of planned work is fine when the user explicitly asks to skip `/mb work`; the tier's tests and verification still apply.

## Common Workflows

| Intent | Command |
| --- | --- |
| Load context | `/mb start` or `scripts/mb-context.sh` |
| Formalize a raw request | `/mb brief <topic> [--input <path>]…` — first stage of `brief → discuss → sdd → work` |
| Create requirements/spec | `/mb discuss <topic>` → `/mb sdd <topic>` |
| Execute existing spec/plan | `/mb work <target> [--range N] [--workflow NAME]` |
| Simple execution override | `/mb work <target> --workflow simple` |
| Verify plan/spec alignment | `/mb verify` |
| Save session | `/mb done` |
| Validate pipeline | `/mb config validate` or `scripts/mb-pipeline-validate.sh` |
| Validate spec | `scripts/mb-spec-validate.sh <topic>` |
| Drift check | `scripts/mb-drift.sh <repo>` |

## Session Discipline

- Start: restore context and summarize current focus in 1–3 sentences.
- During work: update checklist/tasks immediately when a task is truly complete.
- Before completion: run the verification commands required by the current task/workflow.
- End: append progress, update status/checklist, and run `/mb done` when appropriate.

## Backlog Invariants

- Backlog state machine: `NEW → NEEDS-INFO ⇄ TRIAGED → READY → IN-PROGRESS → DONE | WONTFIX`, written only through `scripts/mb-backlog-state.sh`. It replaces `NEW/TRIAGED/PLANNED/DONE/DECLINED/DEFERRED`; `PLANNED` is never written (`mb-backlog-migrate.sh` converts old tokens).
- `I-NNN` IDs are allocated globally across the bank by one helper, `mb_next_backlog_id` in `scripts/_lib.sh`, under `.memory-bank/.locks/backlog.lock` — never by scanning one file.

## Compatibility Notes

- `AGENTS.md` is shared across Pi, OpenCode, Codex, and other agents; project `AGENTS.md` can override global defaults.
- Claude Code reads only `CLAUDE.md` when it exists (it skips `AGENTS.md` by default); other agents (Codex, Pi, OpenCode, Cursor) read `AGENTS.md`. Keep shared project rules in both via the managed blocks; project-specific detail lives in `RULES.md`.
- Global skill installation does not imply project Memory Bank activation; only an existing/resolved bank does.

<!-- mb-agreements:start -->
## Active Agreements
- AGR-083: Проектный блок Key rules в CLAUDE.md/AGENTS.md содержит только отличия проекта от пользовательских правил (включено, выключено, свои…
- AGR-084: Релиз 5.4.0 пока не делаем: сначала тестируем сами, важные пользователи забирают обновления из main…
- AGR-085: Всё, что пишется в репозиторий, — на английском: комментарии в коде, сообщения коммитов, заголовки и описания PR; ответы пользователю…
- AGR-086: pi-native-integration продолжается из Claude Code: исполнители — сабагенты mb-* на Claude, Codex остаётся внешним ревьюером…
- AGR-088: Pi-native: Tintin — бэкенд по умолчанию, Nico — по явному выбору; для Nico ставится публичный потолок прав…
- AGR-089: pi-native-integration: без внешнего ревью Codex и без судьи — этапы делает сабагент-исполнитель, в конце только верификатор…
- AGR-090: Memory Bank subagents must be usable from ordinary Pi through its native extension, without requiring a separate mb-pi invocation…
- AGR-091: For the ordinary-Pi MB bootstrap repair, the owner explicitly authorizes this sole Pi parent to implement inline without /mb work because…
- AGR-092: For the Pi-scoped commit and push to main, the owner authorizes MB_FLOW_CLOSURE=off for that commit process only because the installed hook…
- AGR-093: Codex uses globally registered native Memory Bank lifecycle hooks, model-free cross-chat capture, and named agent roles…
- AGR-094: The /mb work command must remain compatible with Claude Code while supporting Codex.…
- AGR-095: For this Codex-scoped commit only, the owner authorizes MB_FLOW_CLOSURE=off because the installed pre-commit gates the unrelated paused SVP…
- AGR-097: Антон решил (10.10, /mb team): трек размера standard по умолчанию — прямой исполнитель с TDD + plan-verifier в конце, без ревью трека…
- AGR-098: План unfinished-work-completion: приняты рекомендованные Q1 (G-001 paused до Stage 13, коммит на волну без обхода), Q2 (ретро-red в git…
- AGR-099: For the commits of branches fix/red-baseline and feat/team-shared-gates only (2026-11-17), the owner authorizes MB_FLOW_CLOSURE=off because…
- AGR-100: For the /mb drive argparse fix commit on main only (2026-11-18), the owner authorizes MB_FLOW_CLOSURE=off because the full pre-commit…
- AGR-101: OpenSpec: Memory Bank works with OpenSpec specs like its own — reads them in place (/mb work over an OpenSpec change), imports them into…
- AGR-102: opus55-prompt-fit is finished only for Opus 5.5 and Fable 5.x: Stage 6 (commands/mb.md split) and the Fable run of Stage 8 stay…
- AGR-103: Unfinished work is completed through one master plan (master-completion) split into parallel tracks with disjoint files…
- AGR-104: pi-dynamic-workflows is not adopted as Pi's flow engine: we borrow its ideas without a dependency (validator-feedback gate retry in…
- AGR-105: OpenSpec round-trip design accepted as recommended (all 11 answers in context/openspec-adapter.md § Round-trip (AGR-101)): per-unit…
- AGR-106: Goal G-001 (sdd-vision-pipeline, paused) is parked: .memory-bank/goal.md moved to .memory-bank/goals/G-001.md, because an existing goal.md…
- … 72 more → /mb agree list

История, superseded и правила ведения → .memory-bank/agreements.md (`/mb agree`)
<!-- mb-agreements:end -->
