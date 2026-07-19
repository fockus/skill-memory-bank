# Memory Bank Skill

Long-term project memory through `.memory-bank/`, engineering rules, SDD specs, executable `/mb work` tasks, verification, review, and session persistence.

## Hard Rules

1. Resolve the active Memory Bank before project work.
   - Existing bank → print `[MEMORY BANK: ACTIVE]`.
   - No bank → print `[MEMORY BANK: ABSENT]`; do not initialize unless explicitly requested.
2. Read the project rules and Memory Bank context before implementation:
   - global rules: `rules/RULES.md` from this skill bundle;
   - project overrides: `<repo>/AGENTS.md`, `<repo>/RULES.md` or `<bank>/RULES.md` when present;
   - core context: `<bank>/status.md`, `checklist.md`, `roadmap.md`, `research.md` when present (the resolver also detects legacy-cased layouts).
3. New logic requires TDD: failing test first, then implementation, then verification.
4. Do not bypass an existing plan/spec. If work comes from Memory Bank, execute through `/mb work` or the equivalent scripts.
5. If `.memory-bank/COORDINATION.md` exists, parallel sessions share the working tree: read the board before stages, commits, and shared-file edits; scoped `git add` only (never `-A`); obey FREEZE entries. Protocol: `references/coordination.md`.

## Mandatory `/mb work` Gate

When a project has an active Memory Bank and the user says: implement, fix, continue, resume, next step, go by the plan, execute the spec, or similar:

1. Resolve workflow from `<bank>/pipeline.yaml` with `scripts/mb-workflow.sh`.
2. Resolve target/range with `scripts/mb-work-resolve.sh` and `scripts/mb-work-plan.sh`.
3. Treat `specs/<topic>/tasks.md` blocks marked `<!-- mb-task:N -->` as executable source of truth.
4. If using a wrapper plan, it must have `linked_spec` or `<!-- mb-stage:N -->` markers. If not, stop and fix the wrapper before coding.
5. Follow resolved steps exactly. For governed workflows this means: `implement → verify → review → judge → fix/backlog → done`.
6. Pass exact `model` and `thinking` from `pipeline.yaml`/JSON lines to subagents. Do not use fuzzy model names.
7. Do not claim completion until configured verification/review/judge gates are satisfied, or the user explicitly chooses a simpler workflow.

Manual inline implementation is only acceptable for trivial non-plan work or an explicit user request to skip `/mb work`; TDD and verification still apply.

## Common Workflows

| Intent | Command |
| --- | --- |
| Load context | `/mb start` or `scripts/mb-context.sh` |
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
- `CLAUDE.md` may be legacy in some repos. Prefer `AGENTS.md` when both exist unless project instructions say otherwise.
- Global skill installation does not imply project Memory Bank activation; only an existing/resolved bank does.

<!-- mb-agreements:start -->
## Active Agreements
- AGR-001: mb-donor-evolution: umbrella-spec + JIT release slices (no upfront per-release specs, no mega-plan)
- AGR-003: Roadmap runs two parallel tracks (legacy Next queue + donor program); on overlap donor wins: legacy plan freezes at donor release start, live requirements move to the slice; parallel-pipeline superseded immediately
- AGR-004: mb-donor-evolution: ICE may cut releases to icebox, not only reorder — v6.5.0 (GSD) and v6.6.0 (OpenSpec) iceboxed, revisit after 6.1 metrics
- AGR-005: Grilling interview of 2026-07-15 counts as the /mb discuss phase for mb-donor-evolution (no duplicate interview); decisions in context/mb-donor-evolution.md
- AGR-006: update-notify (plan 2026-07-13): HIGH priority — finish before starting donor v5.4.0; remaining: commit Stage 3 after green re-verify, then Stage 4 (opt-in auto-update) + Stage 5 (docs)
- AGR-007: sdd-openspec-parity: full native-only OpenSpec parity in 2 phases (P1 quality layer, P2 living specs+deltas), independent of donor program — AGR-004/v6.6.0 stays iceboxed; 13 decisions in context/sdd-openspec-parity.md
- AGR-008: quality-track (MB Quality Track): donor-программный релиз v6.2.0 сразу после 6.1.0 поверх его evidence-ядра (§7.5, EV-01…05 не дублируются); объём = вижен-Этапы 1–3 (foundation + planning + generation + /mb work --qa); Playwright/healer/OpenSpec-source — следующие JIT-слайсы; решения в context/quality-track.md
- AGR-009: mb-donor-evolution: release numbering — 5.x сдвиг +1 минор (Baseline→5.4.0…Plan IR→5.7.0, v5.3.0 shipped); 6.x после 6.1.0 сдвиг +1 под QA-релиз: QA→6.2.0, Portable Skills→6.3.0, Delta Specs→6.4.0, Adaptive Ops→6.5.0, icebox GSD/OpenSpec→6.6.0/6.7.0; REQ-ID и mb-task не перенумеровываются [supersedes AGR-002]
- AGR-010: Docs site: MkDocs Material, English-only, deployed as /docs/ subpath of the existing GitHub Pages artifact (landing stays at root); existing docs/*.md migrate as-is
- AGR-011: drive-loop: доделать полностью в составе donor v5.6.0 Long-Session Kernel — оставшиеся фазы drive-loop входят в слайс v5.6.0 и дожимаются внутри него (исключение из заморозки AGR-003); quality-track подтверждён по ICE (9×7×4=252) на позиции v6.2.0 сразу после 6.1.0
- AGR-012: adapter-parity: спека встаёт ПЕРВОЙ в очереди роудмепа, впереди donor v5.4.0 — скил должен работать везде до donor-стройки
- AGR-013: adapter-parity: паритет хуков/сабагентов на Pi и OpenCode достигается host-native расширениями, предлагаемыми пользователю opt-in при install и в runtime-nudge (/mb doctor); никогда авто-install; отказ = byte-identical install; Codex = honest degradation (prompt-hook notify + platform_limited)
- AGR-014: adapter-parity discuss-итоги: nudge = /mb doctor + session-start (1 строка, раз за сессию, через AGENTS.md-блок до установки транспорта); Pi-диспатч строим даже headless (медленный лучше отсутствия); honesty-слой (platform_limited + негативные тесты) на все 8 клиентов, фокус расширений pi/opencode/codex + cursor-верификация; исполнение одним слайсом T1–T8; Pi native slash-команды — research в T1 (REQ-022)
- AGR-015: Site/README may document /mb agree (agreements registry) ahead of its release tag — user explicitly requested a public block about the feature; docs/environment-variables-style exclusions no longer apply to it
- AGR-016: openspec-adapter: тонкий one-way import-адаптер OpenSpec change → наш spec-триплет (детерминированное ядро + опц. --normalize LLM-слой), ставится ВПЕРЁД остальных планов для быстрого релиза; отличен от sdd-openspec-parity (native parity) и iceboxed donor v6.7.0 (runtime integration)
- AGR-017: sdd-vision-pipeline: umbrella-спека нового пайплайна (G1–G14 + spec-review + /mb docs, 30 решений в context/sdd-vision-pipeline.md) встаёт главным треком после дожатия openspec-adapter и update-notify; donor-релизы пере-ICE-иваются после её создания
- AGR-018: svp-contract-test-loop (слайс S8 группы sdd-vision-pipeline, ICE 360, blocked by S2): /mb work исполняет спеку контракт-ферст — контрактная задача идёт первой (чекеры критериев готовности → юнит-тесты чекеров на фикстурах обеими половинами → реализация чекеров → зелёные тесты чекеров → обязательный красный прогон против продукта), бизнес-код только после неё по TDD, прогон чекеров против продукта — на стадии verify; интеграционные и e2e тесты — две отдельные задачи в конце спеки (success + основные edge-сценарии); все три слоя отключаются пользователем при создании спеки с записью отказа и причины во frontmatter layers:; Quality DoD = ссылки на правила проекта (AGENTS.md/RULES.md/профиль), иначе на rules/RULES.md банка, доставляются исполнителю, ревьюеру и судье через существующий review_rubric и исполняются существующим mb-rules-check.sh; канонический порядок стадий не меняется
- AGR-019: /mb plan остаётся ручным режимом без Contract/Eval-механики: contract-first/eval усиление (sdd-vision-pipeline) распространяется только на SDD/tasks/work-путь; для plan-only пути пользователь при необходимости добавляет контракты промптом (решение по смысловому аудиту 2026-07-17, INT-PLAN-CONTRACT-EVAL)
- AGR-020: sdd-vision-pipeline/S3: Cursor включается в полный режим intra-session параллели наравне с Claude Code/Pi/OpenCode (у Cursor есть саб-агенты); сужение D-07 до трёх хостов отменено
- AGR-021: ICE-приоритизация группы: считается автоматически, неподтверждённые приоритеты используются с ворнингом + эскалацией пользователю на согласование/правку (ordering не блокируется); после подтверждения ice_confirmed:true
- AGR-022: sdd-vision-pipeline/S9 svp-spec-review-loop: spec-уровневые кубики пайплайна review+judge — автоматический spec_judge (GO/GO_WITH_BACKLOG/NO_GO, судья терминирует цикл), fix-петля с независимым re-review, durable реестр принятых отклонений (не поднимать заново), preflight-гейт /mb work по действующему вердикту; спека создаётся БЕЗ codex-ревью по явному решению пользователя; интеграция в umbrella — после ремедиации круга 3
- AGR-023: Исполнение группы sdd-vision-pipeline (goal G-001): /mb work codex-governed, роли — implement=Opus-сабагенты, review=codex gpt-5.6-sol (xhigh), judge=сабагент на Fable; до 3 параллельных треков, не более 4 одновременных сабагентов; оркестратор — основная сессия; порядок T1→S1→S7→S4→S2→S8→S9→S6→S3→S5 внутри DAG umbrella
- AGR-024: drive-loop: T2 (/mb drive команда + AGENTS.md loop-контракт) и T4 (stop-телеметрия + Stop-hook resume-gate + parallel keying) вытаскиваются вперёд очереди ближайшим исполняемым слотом — исключение из AGR-011 по прецеденту AGR-012; T3 (trend/pivot wiring) и T5 (docs) остаются в donor v5.6.0
- AGR-025: memsearch-плагин выключен глобально (enabledPlugins=false): в MB-проектах дублирует /mb recall (session summaries + agreements/progress/notes), его Stop-хук гонял ONNX bge-m3 индексацию после каждого хода (сотни MB/ход), фактический индекс 24KB = не использовался. Вернуть: одна строка в ~/.claude/settings.json
- AGR-026: Eval-proof (S2 svp-sdd-core, находка [1]): подпись durable eval-пруфа выносится к оркестратору — ключ держит основная сессия, а не сабагент; агент исполняет команду и отдаёт rc+output, оркестратор проверяет, подписывает своим ключом и записывает proof. Публичный литерал MBW_EVAL_PROOF_KEY как 'подпись' упраздняется. Принятая цена: раунд-трип на каждой задаче; там, где отдельного оркестратора нет (headless, /mb drive), гейт честно деградирует до checksum-режима с явной пометкой в состоянии и выводе — по прецеденту AGR-013 (honest degradation), а не делает вид, что защищает

История, superseded и правила ведения → .memory-bank/agreements.md (`/mb agree`)
<!-- mb-agreements:end -->
