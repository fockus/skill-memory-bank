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

## Compatibility Notes

- `AGENTS.md` is shared across Pi, OpenCode, Codex, and other agents; project `AGENTS.md` can override global defaults.
- Claude Code reads only `CLAUDE.md` when it exists (it skips `AGENTS.md` by default); other agents (Codex, Pi, OpenCode, Cursor) read `AGENTS.md`. Keep shared project rules in both via the managed blocks; project-specific detail lives in `RULES.md`.
- Global skill installation does not imply project Memory Bank activation; only an existing/resolved bank does.

<!-- mb-agreements:start -->
## Active Agreements
- AGR-072: Эффект экономии замеряется на боевых задачах, не на синтетическом бенчмарке (решение владельца 2026-10-07)
- AGR-073: Независимые задачи (нет общих файлов и зависимостей по порядку) выполняются параллельно по сабагентам, у каждого общего файла один владелец…
- AGR-074: Пайплайны /mb work имеют три независимые оси: уровень сложности (simple — только исполнитель с самопроверкой; medium…
- AGR-075: Частота верификатора настраивается в pipeline.yaml и флагом /mb work --verify: stage | plan | run | off; по умолчанию на medium…
- AGR-076: Настройки качества проекта задаются в одном месте — профиле правил проекта (/mb rules, /mb profile): порог coverage, TDD вкл/выкл, Testing…
- AGR-077: Принципы SOLID, DRY, KISS и YAGNI по умолчанию включены, но пользователь или проект может выключить любой из них (уточняет AGR-064: эти…
- AGR-078: Планы не дробятся без причины: этап — это граница зависимости, слоя/владельца, рискованная контрольная точка или параллелизуемый кусок с…
- AGR-079: Правило «200k токенов на Sprint» удаляется из правил планирования как устаревшее: размер Sprint определяется архитектурными границами и…
- AGR-082: ADaPT-lite внедряется сейчас как первый срез spec svp-adapt-escalation: план крупный, исполнитель берёт пункт целиком…
- AGR-083: Проектный блок Key rules в CLAUDE.md/AGENTS.md содержит только отличия проекта от пользовательских правил (включено, выключено, свои…
- AGR-084: Релиз 5.4.0 пока не делаем: сначала тестируем сами, важные пользователи забирают обновления из main…
- AGR-085: Всё, что пишется в репозиторий, — на английском: комментарии в коде, сообщения коммитов, заголовки и описания PR; ответы пользователю…
- AGR-086: pi-native-integration продолжается из Claude Code: исполнители — сабагенты mb-* на Claude, Codex остаётся внешним ревьюером…
- AGR-088: Pi-native: Tintin — бэкенд по умолчанию, Nico — по явному выбору; для Nico ставится публичный потолок прав…
- AGR-089: pi-native-integration: без внешнего ревью Codex и без судьи — этапы делает сабагент-исполнитель, в конце только верификатор…
- AGR-090: Memory Bank subagents must be usable from ordinary Pi through its native extension, without requiring a separate mb-pi invocation…
- AGR-091: For the ordinary-Pi MB bootstrap repair, the owner explicitly authorizes this sole Pi parent to implement inline without /mb work because…
- AGR-092: For the Pi-scoped commit and push to main, the owner authorizes MB_FLOW_CLOSURE=off for that commit process only because the installed hook…
- … 65 more → /mb agree list

История, superseded и правила ведения → .memory-bank/agreements.md (`/mb agree`)
<!-- mb-agreements:end -->
