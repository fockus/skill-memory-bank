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
- AGR-024: drive-loop: T2 (/mb drive команда + AGENTS.md loop-контракт) и T4 (stop-телеметрия + Stop-hook resume-gate + parallel keying) вытаскиваются вперёд очереди ближайшим исполняемым слотом — исключение из AGR-011 по прецеденту AGR-012; T3 (trend/pivot wiring) и T5 (docs) остаются в donor v5.6.0
- AGR-025: memsearch-плагин выключен глобально (enabledPlugins=false): в MB-проектах дублирует /mb recall (session summaries + agreements/progress/notes), его Stop-хук гонял ONNX bge-m3 индексацию после каждого хода (сотни MB/ход), фактический индекс 24KB = не использовался. Вернуть: одна строка в ~/.claude/settings.json
- AGR-026: Eval-proof (S2 svp-sdd-core, находка [1]): подпись durable eval-пруфа выносится к оркестратору — ключ держит основная сессия, а не сабагент; агент исполняет команду и отдаёт rc+output, оркестратор проверяет, подписывает своим ключом и записывает proof. Публичный литерал MBW_EVAL_PROOF_KEY как 'подпись' упраздняется. Принятая цена: раунд-трип на каждой задаче; там, где отдельного оркестратора нет (headless, /mb drive), гейт честно деградирует до checksum-режима с явной пометкой в состоянии и выводе — по прецеденту AGR-013 (honest degradation), а не делает вид, что защищает
- AGR-027: I-147 (класс пустых утверждений в тестах) чинится отдельным слайсом ВПЕРЁД продолжения кругов ревью по спекам: (1) правило «тест, который никто не видел красным, — не доказательство» — каждое конвертированное утверждение доказывается красным прогоном; (2) общий assert-хелпер из s4_assert.bash + линтер, делающий ловушку ненаписуемой; (3) атрибуция мутаций до утверждения — точечно, только на eval-гейт и запись в backlog.md/roadmap.md; (4) контракт-ферст (S8/AGR-018) не ускоряем. Исполнители S2 и S4 переключены на I-147, S1 остаётся на круге 3
- AGR-028: Судья /mb work переведён с Fable на Opus: mb-judge стоит сразу после codex-ревью (gpt-5.6-sol xhigh) в шагах codex-governed и терминирует цикл вердиктом GO/GO_WITH_BACKLOG/NO_GO; находки кругов S1/S2/S4 держатся на тонких уликах (пустые утверждения тестов, гейт, который держит на одном пути вызова и испаряется на другом), поэтому решающая роль не может быть слабее ревьюера [supersedes AGR-023]
- AGR-029: Исполнение группы sdd-vision-pipeline (goal G-001), пункты AGR-023, не затронутые сменой судьи: /mb work codex-governed; implement = Opus-сабагенты; review = codex gpt-5.6-sol (xhigh); до 3 параллельных треков и не более 4 одновременных сабагентов; оркестратор — основная сессия; порядок T1→S1→S7→S4→S2→S8→S9→S6→S3→S5 внутри DAG umbrella. Перевыпущено потому, что AGR-028 погасил AGR-023 целиком, тогда как менялась только модель судьи
- AGR-030: Лимит 400 строк — ОРИЕНТИР, не гейт (решение пользователя 2026-07-20): механически он не проверяется нигде, единственное упоминание — проза в rules/CLAUDE-GLOBAL.md про планировщик, а единственный реальный чек — SRP на 300 с уровнем WARNING; исполнители не должны перекраивать архитектуру ради числа, S8 разблокирован
- AGR-031: Гейт закрытия тем управляет ТОЛЬКО финальной генерацией spec-триплета, а не каждой записью в context/<topic>.md (решение пользователя 2026-07-20): снимает противоречие REQ-020 (быстро к коду) против REQ-002 (безусловный гейт), черновые записи по REQ-008/REQ-019 гейтом не перехватываются
- AGR-032: Граница зон S9/S2 и любая будущая: файл принадлежит ОДНОМУ исполнителю в моменте; второму задача не блокируется, а ставится в очередь за владельцем, и оркестратор разводит явно — вместо параллельной правки одного файла двумя треками (прецедент 214380b: правки одного трека уехали в коммит другого)
- AGR-033: commands/mb.md снят из списка «не трогать» (решение пользователя 2026-07-20): патч S7 задачи 4 применяется; коммитить файл можно только после сверки, что в нём нет чужой незакоммиченной работы, иначе она уедет под чужим сообщением
- AGR-034: Три эскалации S2 закрываются так (пользователь 2026-07-20 «делай как рекомендуешь»): [7] снапшот-дайджест валидируется ОДИН раз на входной границе первым потребителем с закрытым кодом причины, а не перепроверяется на каждой стадии; [8] вердикт с моделью вне разрешённого ростера pipeline.yaml не записывается вообще — запись о ревью, называющая модель, которая не запускалась, это сфабрикованная провенанс-запись, худший класс из трёх; [13] чинится КОД под документированный контракт (стейджинг всех трёх файлов, затем переименование всех трёх), а не документ под код — наполовину опубликованный триплет оставляет спеку в несогласованном виде
- AGR-035: Зонный контракт 400 строк (tests/pytest/test_s2_file_size_contract.py, 23 файла зоны svp-sdd-core) остаётся в силе без изменения порога (решение пользователя 2026-07-27): S9 обязан уложить scripts/mb-sdd-review-result.sh (сейчас 429, красный с коммита a50e113) в лимит вместе с находками [3] и [4]. Уточняет AGR-030, а не отменяет: 'ориентир' верно для глобального правила, но в этой зоне 400 проверяется механически — моё утверждение 'не проверяется нигде' было выведено из отсутствия глобального правила и оказалось неполным. Разбиение делать по смыслу (единый containment, схема записи, чтение журнала — естественные границы), а не механической резкой под число
- AGR-036: REQ-049/structural_form расширяется (решение пользователя 2026-07-27, эскалация судьи B5): валидатор признаёт структурным Eval тест (pytest/bats), чьи ЦЕЛИ — doc/config файлы, а не любой pytest; признак идёт по цели теста, потому что расширение whitelist'а всегда ослабляет гейт. Чинится инструмент, а не девять спек под инструмент: doc-структурный тест — доминирующая идиома этого кода (test_sdd_command_contract_v2.py), его красный наблюдаем до реализации, что REQ-049 и требует. Альтернатива (переписать Eval в grep) отвергнута как обход whitelist'а — подмена проверки структуры документа поиском подстроки
- AGR-037: Батарея C8 получает фазу (решение пользователя 2026-07-27, находка I-171): --phase generation требует КРАСНЫХ Eval (задача действительно что-то меняет), --phase done требует ЗЕЛЁНЫХ; C7 гейтит status->ready по --phase done. Без фазы гейт ready недостижим для реализованной спеки по построению: батарея исполняет каждую Eval и требует rc!=0, а реализованная спека даёт зелёные — то есть ready был достижим ТОЛЬКО у нереализованной спеки. Вариант 'оставить гейт только структурным' отвергнут: он убирает единственную проверку того, что объявленный красный действительно красный
- AGR-038: graph-semantic-adoption: оформляется тактическим планом (5 стадий), НЕ спекой — nudge v2 (повтор каждые N grep + символ из паттерна), bootstrap codesearch-индекса в /mb graph --apply + backfill 4 банков, фоновый catchup графа на SessionStart, короткий враппер mb-graph.sh, статус графа в диспатче субагентов; замер adoption через неделю после раскатки

История, superseded и правила ведения → .memory-bank/agreements.md (`/mb agree`)
<!-- mb-agreements:end -->
