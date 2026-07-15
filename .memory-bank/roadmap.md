
# Roadmap

<!-- mb-roadmap-auto -->
## Now (in progress)

- [2026-05-24_fix_cursor-compatibility-remediation](plans/2026-05-24_fix_cursor-compatibility-remediation.md) — Cursor Compatibility Remediation
- [2026-06-23_fix_config-validation-docs](plans/2026-06-23_fix_config-validation-docs.md) — Config Validation & Doc Consistency

## Next (strict order — depends)

- [reviewer-v2](plans/2026-05-23_feature_reviewer-v2.md) — feature — Reviewer 2.0 (S1 of harness-upgrade)
- [work-loop-v2](plans/2026-05-23_feature_work-loop-v2.md) — feature — Work loop 2.0 (S2 of harness-upgrade)
- [cost-multi-model](plans/2026-05-23_feature_cost-multi-model.md) — feature — Cost (multi-model role assignment, S4 of harness-upgrade)
- [handoff-v2](plans/2026-05-23_feature_handoff-v2.md) — feature — Handoff 2.0 (S3 of harness-upgrade)
- [skill-improvements-anthropic-audit](plans/2026-05-23_feature_skill-improvements-anthropic-audit.md) — feature — skill-improvements-anthropic-audit
- [2026-05-24_fix_pi-compatibility-remediation](plans/2026-05-24_fix_pi-compatibility-remediation.md) — Pi Compatibility Remediation
- [2026-06-23_feature_dispatcher-wiring-transports](plans/2026-06-23_feature_dispatcher-wiring-transports.md) — Capability Dispatcher Wiring + Transports
- [2026-07-04_fix_install-and-cross-agent-parity](plans/2026-07-04_fix_install-and-cross-agent-parity.md) — Install reliability + cross-agent parity
- [2026-07-04_fix_session-capture-and-mb-hygiene](plans/2026-07-04_fix_session-capture-and-mb-hygiene.md) — Session-capture correctness + Memory-Bank drift hygiene
- [mb-donor-evolution-v5-4-baseline](plans/2026-07-15_feature_mb-donor-evolution-v5-4-baseline.md) — mb-donor-evolution — v5.4.0 Trustworthy Baseline

## Parallel-safe (can run now)

- [2026-07-04_feature_code-graph-activation](plans/2026-07-04_feature_code-graph-activation.md) — Code-Graph Activation (Path A — all four steps)

## Paused / Archived

_None._

## Linked Specs (active)

- specs/cost-multi-model/design.md
- specs/handoff-v2/design.md
- specs/reviewer-2.0/design.md
- specs/work-loop-v2/design.md
- specs/parallel-pipeline/design.md
- specs/cursor-extension
- specs/pi-extension
- specs/dynamic-flow
- reviewer-2.0
- work-loop-v2
- drive-loop
- cost-multi-model
- parallel-pipeline
- parallel-team-execution
- dynamic-flow
- specs/mb-donor-evolution
<!-- /mb-roadmap-auto -->

_Last updated: auto-synced by mb-roadmap-sync.sh_

## ✅ Priority insert (2026-07-15, AGR-006): `update-notify` — ЗАВЕРШЁН

План [2026-07-13_feature_update-notify](plans/done/2026-07-13_feature_update-notify.md) закрыт 2026-07-15. Stage 1 (flavor+Homebrew) `fef41f8` · Stage 2 (mb-version-check.sh) `0d9a57a` · Stage 3 (SessionStart notice) `2a55f87` · Stage 4 (opt-in auto-update) `1607842` · Stage 5 (docs) `4369e9e` · закрытие `1be8c78`. Блокер donor v5.4.0 снят.

## 🔥 Priority insert (2026-07-15, AGR-007): `sdd-openspec-parity` — high priority

Контекст: [context/sdd-openspec-parity.md](context/sdd-openspec-parity.md) (13 решений D-01…D-11.1). Нативная OpenSpec-parity для SDD-движка (`/mb discuss → /mb sdd → /mb work`), **независимая от donor-программы** (AGR-007): AGR-004 / v6.6.0 (OpenSpec **runtime**) остаётся в айсбоксе — здесь только native authoring/validation. Поглощает backlog **I-062**.

**Приоритет: HIGH** — выше donor-релизов после v5.4.0; может идти параллельно с `update-notify` (не пересекается по файлам). Обоснование: это движок, которым donor-программа САМА авторит и валидирует специи — усилив его качество рано, мы поднимаем планку всех последующих спек. **Phase 1** (дешёвые изолированные победы: wording-lint, обязательные сценарии для новых спек, RFC 2119, `## Why`, inputs-registry, archive-gate, secret-scan) ships first и опережает donor v5.5.0+. **Phase 2** (living specs + ADDED/MODIFIED/REMOVED deltas) — отдельный `/mb discuss` перед стартом (D-10), forward-compatible с REQ-OSA-010.

Не пересекается с donor-файлами — трогает нативный SDD-тулинг (`mb-spec-validate.sh`, `mb-sdd.sh`, `mb-ears-validate.sh`, `mb-traceability-gen.sh`, templates). Дальше: `/mb sdd sdd-openspec-parity` → план → governed `/mb work`.

## Track 2 — Donor Evolution Program (2026-07-15, `specs/mb-donor-evolution`)

Источник: `specs/mb-donor-evolution/source-plan.md` (donor-driven план GSD/OpenSpec/Archon/Superpowers/CCPM/Ruflo). Решения discovery-интервью: `context/mb-donor-evolution.md`. Roadmap ведётся **двумя параллельными дорожками**: legacy-очередь ниже живёт своей жизнью; при пересечении с donor-релизом **побеждает donor** — legacy-план замораживается на старте соответствующего релиза, живые требования переносятся в release-slice через SDD delta-review. `parallel-pipeline` → **superseded** немедленно (source-plan §2.1).

Нумерация сдвинута +1 минор внутри 5.x (v5.3.0 уже выпущена 2026-07-13): доковский Этап 0 → v5.4.0 и далее; серия 6.x без сдвига. REQ-ID и mb-task 1–132 не перенумеровываются.

### ICE-приоритизация релизов программы

ICE = Impact × Confidence × Ease (1–10). Порядок = ICE с поправкой на граф зависимостей (source-plan §9.3: 5.4→5.5→5.6→5.7→6.0→6.1; 5.5→6.2; 6.1+6.2→6.3→6.4; 6.3+6.4→6.5→6.6). Нумерация 6.x-хвоста сдвинута +1 под QA-релиз (AGR-009, 2026-07-15): QA→6.2.0, Portable Skills→6.3.0, Delta Specs→6.4.0, Adaptive Ops→6.5.0, icebox GSD/OpenSpec→6.6.0/6.7.0.

| Релиз | Название | P | I | C | E | ICE | Вердикт |
|---|---|---|---|---|---|---:|---|
| v5.4.0 | Trustworthy Baseline | P0 | 8 | 9 | 9 | **648** | Now — wrapper `2026-07-15_feature_mb-donor-evolution-v5-4-baseline` |
| v5.5.0 | Spec Control Plane | P0 | 8 | 8 | 6 | **384** | Next |
| v6.1.0 | Evidence, UAT & Gap Closure | P1 | 9 | 7 | 5 | **315** | Next (после 6.0 — жёсткая зависимость) |
| v5.6.0 | Long-Session Kernel & Event Journal **+ drive-loop** | P0 | 10 | 7 | 4 | **280** | Next — поглощает остаток `specs/drive-loop` (AGR-010): drive-loop дожимается ВНУТРИ слайса, не замораживается |
| v6.2.0 | **Quality Track — QA & Evidence Graph** (`specs/quality-track`, 29 REQ) | P1 | 9 | 7 | 4 | **252** | Next (сразу после 6.1.0 — строится поверх его evidence-ядра EV-01…05, не дублируя его; AGR-008). Высокий impact, высокая сложность — потому середина очереди, а не старт |
| v5.7.0 | Plan IR & Typed Workflow Planner | P0 | 8 | 7 | 4 | **224** | Next |
| v6.0.0 | Isolated Mixed-Node Execution | P1 | 8 | 6 | 3 | **144** | Next (разблокирует 6.1) |
| v6.3.0 | Portable Skills & Provider Platform | P1 | 6 | 6 | 4 | **144** | Next (зависит только от 5.5; можно параллельно 5.6–6.2) |
| v6.5.0 | Adaptive Operations & Observability | P3 | 5 | 5 | 4 | **100** | Later (после 6.4 — зависимость) |
| v6.4.0 | Delta Specs, Projection & Executor Adapters | P2 | 5 | 5 | 3 | **75** | Later |
| v6.6.0 | Optional GSD Execution Engine | P2 | 3 | 4 | 2 | **24** | **Icebox** — пересмотреть после метрик 6.1 и реального спроса на внешний executor |
| v6.7.0 | Optional OpenSpec Authoring Engine | P2 | 3 | 4 | 2 | **24** | **Icebox** — пересмотреть вместе с 6.6 (зависит от него) |

**Итоговый порядок исполнения** (зависимости доминируют над сырым ICE):
`5.4.0 → 5.5.0 → 5.6.0 (+drive-loop) → 5.7.0 → 6.0.0 → 6.1.0 → 6.2.0 (QA) → 6.3.0 (∥ возможно раньше, после 5.5) → 6.4.0 → 6.5.0 → [icebox: 6.6.0, 6.7.0]`.

ICE-примечания: 6.1 имеет третий score программы, но заперт за 6.0 — это главный аргумент не откладывать 6.0. **Quality Track (6.2.0): сырой ICE 252 поставил бы его пятым, но жёсткая зависимость от evidence-ядра 6.1.0 (манифест §7.5, freshness, коллекторы EV-01…05) фиксирует его сразу за 6.1 — раньше физически нельзя без двойной постройки evidence-слоя (D-01/D-02 в `context/quality-track.md`); позже — нельзя оправдать, его ICE выше всего хвоста.** 6.3 — единственный кандидат на параллельный лейн (зависит только от 5.5). Icebox честный: оба optional-движка — самые дорогие (E=2) и наименее подтверждённые потребностью (I=3) части программы; их REQ/задачи (mb-task 102–132) остаются в umbrella-спеке и активируются JIT-слайсами при разморозке.

**Пересечения с legacy-дорожкой** (правило «donor побеждает», замораживать на старте релиза):
- `drive-loop` + `SEQUENCE_long-running-sessions` ↔ **5.6.0** — исключение из заморозки (AGR-010): оставшиеся фазы drive-loop входят в слайс v5.6.0 и ДОДЕЛЫВАЮТСЯ в нём (много вложенной работы, фича важная);
- `work-loop-v2` ↔ 5.6.0/5.7.0 (execution state machine `/mb work`);
- `reviewer-2.0` ↔ 6.1.0 (evidence/review);
- `quality-track` ↔ 6.2.0 — это и ЕСТЬ релиз 6.2.0 (AGR-008), спека уже написана (29 REQ), задачи авторятся JIT при старте слайса;
- `cost-multi-model` ↔ 6.3.0 (provider capabilities/routing);
- `parallel-team-execution` ↔ 6.0.0 (уже де-факто перекрыт mixed-node execution).

## 📋 Единый реестр незакрытого (2026-07-15) — каждый открытый план/спека привязан к очереди

Инвариант: ничто незаконченное не живёт вне этого роудмепа. Если появляется новый план/спека — сюда добавляется строка с местом в очереди.

| Работа | Артефакт | Где в очереди |
|---|---|---|
| sdd-openspec-parity Phase 1 | `specs/sdd-openspec-parity` (24 REQ, T1–T8) | 🔥 HIGH — сейчас, ∥ donor v5.4.0 (AGR-007) |
| agreements (`/mb agree`) | `specs/agreements` | 🔄 в работе параллельной сессией (AGR-запись уже живая) |
| donor v5.4.0 Trustworthy Baseline | план `2026-07-15_feature_mb-donor-evolution-v5-4-baseline` | Now — голова donor-поезда |
| donor v5.5.0…v6.5.0 | umbrella `specs/mb-donor-evolution` | ICE-таблица выше, JIT-слайсы |
| quality-track | `specs/quality-track` (29 REQ) | = donor v6.2.0 (AGR-008/009) |
| drive-loop остаток | `specs/drive-loop` + `SEQUENCE_long-running-sessions` | внутри donor v5.6.0 (AGR-010) |
| sdd-openspec-parity Phase 2 (living specs + deltas) | Task 9 DEFERRED в `specs/sdd-openspec-parity` | после Phase 1, свой `/mb discuss`; forward-compat с v6.7.0 |
| reviewer-2.0 → work-loop-v2 → cost-multi-model | specs + планы 2026-05-23 | legacy Next-цепочка; замораживаются на старте 6.1.0 / 5.6-5.7 / 6.3.0 соответственно (donor побеждает) |
| dynamic-flow Phase 2–3 | `specs/dynamic-flow` | legacy tail; пересечение с 5.6/5.7 оценить на старте v5.6.0 |
| install-and-cross-agent-parity | план 2026-07-04 (queued) | legacy Next; независим от donor — можно ∥ лейном |
| session-capture-and-mb-hygiene | план 2026-07-04 | legacy Next |
| codex-remediation Wave 2: config-validation-docs (I-086) + dispatcher-wiring (I-084) | планы 2026-06-23 | Now/Next в авто-блоке; Wave 1 (I-082/083/085) ✅ DONE `49f9ad5` |
| cursor/pi-compatibility-remediation | планы 2026-05-24 | Now (cursor) / Next (pi); pi-extension ждёт внешнего Pi API |
| code-graph-activation | план 2026-07-04 | Parallel-safe — любой свободный слот |
| skill-improvements-anthropic-audit | план 2026-05-23 | docs-лейн, ∥ любому code-wave |
| parallel-team-execution | `specs/parallel-team-execution` | заморожен на старте v6.0.0 (перекрыт mixed-node) |
| mb-research-tooling-core | `specs/mb-research-tooling-core` (design-only) | shipped в Phase 5 (см. Roadmap high-level); триплет не достраиваем — YAGNI |
| I-109 остаток: агент mb-debugger | backlog | мелкий ∥ слот (час работы), вне релизного поезда |
| Deferred: I-001 benchmarks · I-002 sqlite-vec · I-003 native-memory-bridge · I-005 graph-viz | backlog | заморожены осознанно; пересматривать при user-сигнале |

## Current focus (2026-06-23 — codex/GPT-5.5 remediation)

**v5.1.0 SHIPPED** (PyPI + GitHub Release) and `main` CI is GREEN (post-release red fixed: `3c16381` bats portability + shellcheck 0.9.0, `e04c4e7` pytest CI-portability). A 9-agent codex/GPT-5.5 read-only review (6 aspects + 3 transports → `reports/2026-06-23_codex-gpt5.5-skill-review.md`) produced backlog **I-082..I-086** and 5 fix-plans. **Sequence source of truth: `plans/2026-06-23_SEQUENCE_codex-remediation.md`.**

**Ordered execution (dependency-resolved):**

| Wave | # | Plan | Backlog | Release |
|------|---|------|---------|---------|
| 1 (urgent patch) | 1 | [security-hardening](plans/2026-06-23_fix_security-hardening.md) | I-082 | 5.1.1 |
| 1 | 2 | [verification-gates](plans/2026-06-23_fix_verification-gates.md) | I-083 | 5.1.1 |
| 1 | 3 | [logic-correctness-portability](plans/2026-06-23_fix_logic-correctness-portability.md) | I-085 | 5.1.1 |
| 2 (minor feature) | 4 | [config-validation-docs](plans/2026-06-23_fix_config-validation-docs.md) | I-086 | 5.2.0 |
| 2 | 5 | [dispatcher-wiring-transports](plans/2026-06-23_feature_dispatcher-wiring-transports.md) | I-084 | 5.2.0 |

**Why this order:** security/correctness before features (I-082 code-exec is in shipped 5.1.0); fix verification gates (I-083) so `/mb done`/`/mb work` are trustworthy before landing the rest; fix the empty-`--range`→whole-plan BLOCKER (I-085) early since we execute these plans *with* `/mb work --range`. Hard deps: I-082 → I-085 (shared `_lib.sh::mb_canonical_under` + `mb-work-resolve.sh`); I-086 → I-084 (validator + single pipeline-resolution path the dispatcher relies on). Each plan runs governed (`codex-governed`: implement → verify → dual review → **judge=mb-judge** → fix-cycle → done), TDD-first, tested under bash 3.2 + 5.x and Python 3.11.

## Current focus (2026-06-14, v5.1.0 shipped)

`tier1-graph-memory` (17/17) отгружен → **v5.1.0** (PyPI publish + git tag pending explicit go). `goal-driven-autopilot` **снят с roadmap** — заменён на `specs/dynamic-flow/` (мёртвые планы в `plans/superseded/`). Ниже — переприоритизированный по ICE план оставшейся специфицированной работы. Источник истины по последовательности — этот раздел; авто-блок выше отражает лишь «что активно по фронтматтеру планов».

## ICE-prioritised roadmap (remaining specced work)

ICE = Impact × Confidence × Ease (каждый 1–10). Последовательность = ICE, поправленный на граф зависимостей.

| Работа | Spec / Plan | I | C | E | ICE | Size | Blockers |
|--------|-------------|---|---|---|-----|------|----------|
| handoff-v2 | specs/handoff-v2 | 8 | 9 | 6 | **432** | M | — (parallel-safe) |
| dynamic-flow Phase 1 | specs/dynamic-flow | 9 | 7 | 6 | **378** | M | — |
| cursor-extension finish | specs/cursor-extension | 4 | 9 | 9 | **324** | S | — (~7/9 done) |
| work-loop-v2 | specs/work-loop-v2 | 7 | 7 | 6 | **294** | M | ← reviewer-2.0 |
| reviewer-2.0 | specs/reviewer-2.0 | 8 | 7 | 4 | **224** | L | — (head of chain) |
| cost-multi-model | specs/cost-multi-model | 6 | 6 | 6 | **216** | M | ← reviewer+loop, I-057/058 |
| skill-improvements-audit | plans/…anthropic-audit | 6 | 6 | 6 | **216** | M | parallel-safe (docs) |
| dynamic-flow Phase 2–3 | specs/dynamic-flow | 7 | 6 | 4 | **168** | L | ← Phase 1 |
| pi-extension | specs/pi-extension | 5 | 5 | 4 | **100** | L | external Pi API |
| parallel-pipeline | specs/parallel-pipeline | 6 | 4 | 2 | **48** | XL | ⚠️ arch decision |
| parallel-team-execution | specs/parallel-team-execution | 7 | 3 | 2 | **42** | XL | ← dynamic-flow + parallel-pipeline |

**Strict execution sequence (dependency-resolved):**

| Wave | Item | Why here |
|------|------|----------|
| 0 | Hygiene (roadmap honesty) | ✅ DONE 2026-06-14 — закрыты готовые планы, 8× goal-driven + opencode-first → `plans/superseded/` |
| 1 | cursor-extension finish (S) | ✅ DONE 2026-06-15 (f86247c) — Stages 4-5 + spec hygiene |
| 2 | handoff-v2 (M) | ✅ DONE 2026-06-15 — 5/5 tasks, governed dual-review + judge, fix-cycle per task |
| 3 | dynamic-flow Phase 1 (M) | ✅ DONE 2026-06-16 (a191aa3·947a506·9ee43e9) — 7 tasks, governed dual-review + judge, фирвол «нельзя соврать про done» (I-077) |
| 4 | reviewer-2.0 (L) | ◀ NEXT — голова harness-цепочки |
| 5 | work-loop-v2 (M) | нужен сигнал `progress_trend` из reviewer-2.0 |
| 6 | cost-multi-model (M) | нужен reviewer+loop; сначала закрыть I-057/I-058 |
| ∥ | skill-improvements-anthropic-audit (M) | docs-лейн, идёт параллельно любому code-wave |
| tail | dynamic-flow Phase 2–3 → pi-extension → (XL) parallel-* | после арх-решения ниже |

**✅ Architecture decision resolved (2026-07-15, Track 2).** `parallel-pipeline` помечен **superseded**: donor-программа (`specs/mb-donor-evolution`, релизы 5.6.0–6.0.0) расширяет `/mb work` версионированным execution engine вместо отдельного `/mb run`; worktree-изоляция реализуется в v6.0.0 Isolated Mixed-Node Execution. `parallel-team-execution` замораживается при старте 6.0.0 (правило «donor побеждает»).

**Cross-wave invariants:**
- Каждый landing: pytest GREEN, bats GREEN, rules-check 0 violations, traceability обновлён, plan → `plans/done/`.
- Default behaviour byte-identical после каждой landing — всё новое opt-in (flags/env vars).
- Frontmatter `status: in_progress` только на ОДНОМ плане в моменте (исключение: docs-лейн skill-improvements может идти параллельно code-лейну).

## Recently completed

- **✅ `handoff-v2` — Handoff 2.0 (5/5 tasks)** [2026-06-15]
   - Governed pipeline per task (implement Opus → verify → DUAL review Codex gpt-5.5 + lead → judge NO_GO → fix-cycle 1 → GO): handoff capsule (`mb-handoff.sh`/`handoff_capsule.py`, skeleton-reserved ≤1500-byte truncation, owner-token lock), PreCompact `mb-pre-compact.sh` (never blocks compaction, process-tree kill), SessionStart fresh-capsule prepend (max-date), mandatory `/mb done` gates (`mb-done-gates.sh`, required-list + fail-closed force + CR/LF reason guard + `--diff-files` TDD-delta), append-only sha256 chain (`mb-progress-chain.sh`/`progress_chain.py`, canonical form, unique-run anchor, malformed-index→CRITICAL), docs (`docs/handoff-2.0.md` + CHANGELOG). Full pytest 1448 / full bats 861, shellcheck+ruff clean. Backlog: I-072/I-073/I-074. Commits e70dffb (Task 1) + this push (Tasks 2-5).

- **✅ `tier1-graph-memory` — code-graph + session-memory tier (17/17)** [2026-06-14 → v5.1.0]
   - 17 задач через governed `/mb work` (implement Opus → verify → dual-review Codex gpt-5.5 + main-agent → judge → fix-loop ≤2): RRF auto-backend, import-aware Python call-resolution (CACHE_VERSION=2), PageRank god-nodes, progressive-disclosure `/mb recall`, community-summary retrieval, per-community wiki + `semantic` edges (confidence bands), `--sessions` graph layer, `/mb consolidate`/`/mb recap`/`/mb conflicts`, `[SUPERSEDED]` drift checker, v2 session-summary state machine.
   - Backlog closed: I-066/I-067 (bind-fallback, 306835a), I-069 (heading SM, 07221e9). VERSION 5.0.1 → 5.1.0; full suite 1423 passed / 7 skipped. PyPI publish + git tag — pending explicit go.

- **✅ Phase `global-storage` (core + agent-support) + Sprint `rule-profiles-and-stack-presets`** [2026-05-24, plans archived]
   - `global-storage-core`: resolver contract tests + 6 `_lib.sh` helpers + `mb-init-bank.sh` global flags + `/mb init` UX + rules-only mode docs. Verified: 735 pytest + 119 focused bats.
   - `global-storage-agent-support`: resolver-aware hooks (3 hooks + git-hooks-fallback honour `MB_PATH`) + adapter matrix (opencode JS plugin, cursor/codex/pi/windsurf/cline/kilo) + Codex global AGENTS embed (TDD/SOLID/Clean Architecture/DRY/KISS/YAGNI/`[MEMORY BANK: ABSENT]`) + storage-modes docs + E2E suite (4 bats cases).
   - `rule-profiles-and-stack-presets`: profile schema + 22 built-in presets (roles/stacks/architecture/delivery) + `memory_bank_skill/rules_profile.py` + `scripts/mb-profile.sh` CLI + `mb-rules-check.sh` profile integration (strictness-aware exit, rule_id/profile_source fields, stack-aware checks) + `/mb profile` command + `docs/rule-profiles.md`. Verified: 798 pytest + full bats + ruff clean.
   - Plans: [done/global-storage](plans/done/2026-05-21_feature_global-storage.md), [done/global-storage-agent-support](plans/done/2026-05-21_feature_global-storage-agent-support.md), [done/rule-profiles-and-stack-presets](plans/done/2026-05-21_feature_rule-profiles-and-stack-presets.md).

- **✅ Phase `sdd-unification` — Spec-Driven Development end-to-end** [2026-05-23]
   - Three sprints landed: `sdd-task-model` (shared parser + new tasks.md format + spec-validate), `sdd-work-engine` (`/mb work` executes spec tasks; plan-as-wrapper via linked_spec frontmatter; additive JSON fields), `sdd-traceability-docs` (Spec Task column in matrix + migration script + unified SDD docs).
   - Phase E2E gate PASS: `mb-sdd → mb-spec-validate → mb-work-plan → mb-traceability-gen → mb-spec-tasks-migrate`.
   - Plans: [done/sdd-task-model](plans/done/2026-05-21_refactor_sdd-task-model.md), [done/sdd-work-engine](plans/done/2026-05-21_refactor_sdd-work-engine.md), [done/sdd-traceability-docs](plans/done/2026-05-21_refactor_sdd-traceability-docs.md).

- **✅ GraphRAG-lite code context — portable code intelligence layer** [2026-05-21]
   - Portable CLI source of truth: `scripts/mb-graph-query.py` (`neighbors`, `impact`, `tests`, `explain`, `summary`) and `scripts/mb-code-context.py` evidence packs.
   - SRP remediation split core/render/helper modules while preserving entrypoints: `mb_graph_query_core.py`, `mb_graph_query_render.py`, `mb_code_context_core.py`, `mb_rules_check_lib.sh`, `adapters/pi_graph_rag_extension.ts`.
   - Cross-agent guidance shipped for Pi native project extension wrappers plus OpenCode/Codex/generic AGENTS.md CLI fallback.
   - Verification: `/mb verify` PASS; rules-check 0 violations; focused pytest 40 passed; bats 17+9 ok; full `mb-test-run` 708 passed; ruff/scoped shellcheck clean.
   - Plan: [plans/done/2026-05-21_architecture_graph-rag-lite-code-context.md](plans/done/2026-05-21_architecture_graph-rag-lite-code-context.md).

- **✅ I-004 — `mb-auto-commit.sh` opt-in auto-commit for /mb done** [2026-04-25]
   - `scripts/mb-auto-commit.sh` — bash dispatcher. Triggers only when `MB_AUTO_COMMIT=1` env or `--force` flag.
   - 4 safety gates (each emits warning, exits 0 — non-fatal): bank clean → no-op; dirty source outside bank → skip (won't sweep code); rebase/merge/cherry-pick in progress → skip; detached HEAD → skip.
   - Subject: `chore(mb): <last ### heading from progress.md>` (truncated to 60 chars). Fallback: `chore(mb): session-end <YYYY-MM-DD>`. Co-Authored-By trailer for Claude. Never pushes.
   - Wired into `commands/done.md` step 7 (between `index.json` regen and final report).
   - 13 new tests: 10 `test_mb_auto_commit.py` (all gates + subject derivation + force-flag + help) + 3 `test_i004_registration.py` (script presence, done.md reference, backlog flip). pytest 615 → 628 (+13).
   - Backlog `I-004` flipped HIGH-NEW → HIGH-DONE with outcome line. Plan: [plans/done/2026-04-25_feature_i004-auto-commit.md](plans/done/2026-04-25_feature_i004-auto-commit.md).

- **✅ Phase 4 Sprint 3 — installer auto-register + superpowers reviewer detection + v4.0.0 release** [2026-04-25]
   - `scripts/mb-reviewer-resolve.sh` — bash dispatcher reading `pipeline.yaml:roles.reviewer.agent` (default `mb-reviewer`); honours `override_if_skill_present` when the named skill directory exists in `MB_SKILLS_ROOT` (default `~/.claude/skills`); routes `/mb work` review step to `superpowers:requesting-code-review` automatically when present.
   - `settings/hooks.json` extended with 5 v2 entries (PreToolUse `Write|Edit` × 2 + PreToolUse `Task` × 2 + PostToolUse `Write` × 1), all marked `# [memory-bank-skill]` so `merge-hooks.py` strips/re-appends them idempotently.
   - `install.sh` step 6.5 — informational probe for `~/.claude/skills/superpowers/`; status line tells user which reviewer route is active.
   - `commands/work.md` step 3c rewritten to call resolver instead of hard-coding agent name.
   - **VERSION 3.1.2 → 4.0.0**; CHANGELOG `[Unreleased]` cut to `[4.0.0] — 2026-04-25` summarising Phase 3+4+I-033.
   - 19 new tests (7 hooks-registration + 5 reviewer-resolve + 7 release-prep). pytest 596 → 615.
   - Plan: [plans/done/2026-04-25_feature_phase4-sprint3-installer-and-release.md](plans/done/2026-04-25_feature_phase4-sprint3-installer-and-release.md)

- **✅ I-033 — `mb-checklist-prune.sh` + checklist hard-cap enforcement** [2026-04-25]
   - `scripts/mb-checklist-prune.sh` — bash dispatcher + python parser. Collapses fully-✅+plans/done sections to one-liners. Pre-write `.checklist.md.bak.<unix-ts>` backup. Hard-cap warn (>120 lines). Idempotent.
   - Wire-ins: `commands/done.md` step 4, `scripts/mb-plan-done.sh` chain, `scripts/mb-compact.sh --apply`. Best-effort (non-fatal on failure).
   - `tests/pytest/test_mb_checklist_prune.py` (11 cases) + `tests/pytest/test_checklist_cap.py` (CI cap-test enforcing ≤120 lines on repo's own `.memory-bank/checklist.md`).
   - Dogfood: repo checklist re-pruned 39 → 36 lines. pytest 584 → 596 passed (+12). shellcheck `-x` clean.
   - Plan: [plans/done/2026-04-25_refactor_checklist-prune-i033.md](plans/done/2026-04-25_refactor_checklist-prune-i033.md). Closes lessons.md "rotating artifact without enforcement" antipattern (now SHIPPED).

- **✅ Phase 4 Sprint 2 — `--slim`/`--full` end-to-end + sprint_context_guard** [2026-04-25]
   - `scripts/mb-context-slim.py` — prompt trimmer (active stage block + DoD bullets + covers_requirements list + optional `git diff --staged`); falls back к full prompt when stage marker не найден
   - `hooks/mb-context-slim-pre-agent.sh` upgraded to Sprint 2 behavior — при `MB_WORK_MODE=slim` parses prompt for `Plan:`/`Stage:` markers, runs trimmer, emits JSON `hookSpecificOutput.additionalContext` с slim version. Falls open на любой failure.
   - `scripts/mb-session-spend.sh` — companion CLI для session token-spend tracker (init/add/status/check/clear); chars→tokens via /4 estimate; thresholds из `pipeline.yaml:sprint_context_guard`
   - `hooks/mb-sprint-context-guard.sh` — 5-й hook (PreToolUse Task); accumulates prompt+description chars per dispatch, warns at soft threshold, exit 2 (block) на hard threshold
   - `references/hooks.md` обновлён: context-slim section reflects Sprint 2 behavior, добавлен 5-й hook section, combined settings.json snippet включает оба `Task`-matcher hook'а
   - `commands/work.md` — `--slim`/`--full` flag clarification (exports `MB_WORK_MODE` для loop subshell)
   - 32 new tests (9 context-slim + 5 hook-context-slim-upgrade + 7 session-spend + 5 sprint-context-guard + 6 registration). pytest 552 → 584 passed.
   - Plan: [plans/done/2026-04-25_feature_phase4-sprint2-slim-and-context-guard.md](plans/done/2026-04-25_feature_phase4-sprint2-slim-and-context-guard.md)

- **✅ Phase 4 Sprint 1 — 4 critical hooks** [2026-04-25]
   - `hooks/mb-protected-paths-guard.sh` — PreToolUse Write/Edit; blocks writes to `protected_paths` globs unless `MB_ALLOW_PROTECTED=1` (delegates к `mb-work-protected-check.sh`)
   - `hooks/mb-plan-sync-post-write.sh` — PostToolUse Write; chains `mb-plan-sync.sh → mb-roadmap-sync.sh → mb-traceability-gen.sh` для `.md` files под `plans/` или `specs/`. Best-effort.
   - `hooks/mb-ears-pre-write.sh` — PreToolUse Write для `specs/*/requirements.md` или `context/*.md`; runs `mb-ears-validate.sh -` against content; exit 2 на failure.
   - `hooks/mb-context-slim-pre-agent.sh` — PreToolUse Task; advisory note when `MB_WORK_MODE=slim` (Sprint 2 wires actual prompt rewrite).
   - `references/hooks.md` — full installation guide (per-hook section + combined `~/.claude/settings.json` snippet + operational notes).
   - 35 new tests (6 protected-paths + 5 plan-sync + 6 ears-pre-write + 4 context-slim + 14 registration). pytest 517 → 552 passed.
   - Plan: [plans/done/2026-04-25_feature_phase4-sprint1-critical-hooks.md](plans/done/2026-04-25_feature_phase4-sprint1-critical-hooks.md)

- **✅ Phase 3 Sprint 3 — review-loop ядро** [2026-04-25]
   - `scripts/mb-work-review-parse.sh` — strict JSON validator + cross-checks (CHANGES_REQUESTED ⇒ non-empty issues) + `--lenient` Markdown fallback
   - `scripts/mb-work-severity-gate.sh` — applies pipeline.yaml severity_gate to counts (PASS/FAIL exit codes), supports `--counts <json>` / `--counts-stdin` / `--gate <json>` override
   - `scripts/mb-work-budget.sh` — token budget tracker (init / add / status / check / clear), state в `<bank>/.work-budget.json`, exit codes 0/1/2 для ok/warn/stop
   - `scripts/mb-work-protected-check.sh` — matches changed files against `protected_paths` globs с `**` support
   - `agents/mb-reviewer.md` — production-grade review prompt (per-category walk + severity decision tree + strict JSON schema + fix-cycle behavior + hard guardrails)
   - `commands/work.md` — full review-loop wired: implement → protected-check → review (Task) → parse → severity-gate → fix-cycle → verify (plan-verifier) → stage-done; hard stops table для `--auto`
   - 43 new tests (11 review-parse + 9 severity-gate + 8 budget + 6 protected-check + 9 registration). pytest 474 → 517 passed.
   - Plan: [plans/done/2026-04-25_feature_phase3-sprint3-review-loop.md](plans/done/2026-04-25_feature_phase3-sprint3-review-loop.md)

- **✅ Phase 3 Sprint 2 — `/mb work` execution engine + 9 role-agents** [2026-04-25]
   - `scripts/mb-work-resolve.sh` — 5-form target resolver (existing path / substring / topic / freeform / empty active plan)
   - `scripts/mb-work-range.sh` — range parser (N / A-B / A-) с auto-detect уровня (plan→stages / phase→sprints)
   - `scripts/mb-work-plan.sh` — JSON Lines per-stage emitter с role auto-detection (ios/android/frontend/backend/devops/qa/architect/analyst → developer fallback) + `--dry-run` summary header
   - 9 implementer agents (mb-developer / mb-backend / mb-frontend / mb-ios / mb-android / mb-architect / mb-devops / mb-qa / mb-analyst) + 1 reviewer scaffold (mb-reviewer)
   - `commands/work.md` + router в `commands/mb.md`
   - 76 new tests (9 resolver + 9 range + 10 plan-emitter + 40 agents-registration + 8 work-registration). pytest 398 → 474 passed.
   - Plan: [plans/done/2026-04-25_feature_phase3-sprint2-work-engine.md](plans/done/2026-04-25_feature_phase3-sprint2-work-engine.md)

- **✅ Phase 3 Sprint 1 — `/mb config` + `pipeline.yaml`** [2026-04-25]
   - `references/pipeline.default.yaml` — full spec §9 schema (version, roles 11шт, stage_pipeline implement/review/verify, budget, protected_paths 6 паттернов, sprint_context_guard 150k/190k, review_rubric 5 секций, sdd 5 ключей)
   - `scripts/mb-pipeline-validate.sh` — структурный schema-валидатор (yaml-aware, 14 категорий проверок)
   - `scripts/mb-pipeline.sh` — dispatcher init/show/validate/path с idempotency guard и `--force`
   - `commands/config.md` + router в `commands/mb.md`
   - 63 new tests (33 default-shape + 14 validator + 11 dispatcher + 5 registration). pytest 335 → 398 passed.
   - Plan: [plans/done/2026-04-25_feature_phase3-sprint1-config-pipeline.md](plans/done/2026-04-25_feature_phase3-sprint1-config-pipeline.md)

- **✅ Phase 2 Sprint 2 — `/mb sdd` + SDD-lite в `/mb plan`** [2026-04-25]
   - `scripts/mb-sdd.sh` — Kiro-style spec triple `specs/<topic>/{requirements,design,tasks}.md`
   - EARS section copied verbatim из `context/<topic>.md` если существует
   - Idempotency guard + `--force` для overwrite
   - `scripts/mb-plan.sh` `--context <path>` + `--sdd` flags + auto-detect + `## Linked context` секция
   - 18 new tests (7 sdd + 6 plan-sdd-lite + 5 registration). pytest 317 → 335 passed.
   - Plan: [plans/done/2026-04-25_feature_phase2-sprint2-sdd-and-plan-lite.md](plans/done/2026-04-25_feature_phase2-sprint2-sdd-and-plan-lite.md)

- **✅ Phase 2 Sprint 1 — `/mb discuss` + EARS validator + `context/<topic>.md`** [2026-04-25]
   - `commands/discuss.md` — 5-phase interview (Purpose/EARS/NFR/Constraints/Edge)
   - `scripts/mb-ears-validate.sh` — 5 EARS pattern regex validator
   - `scripts/mb-req-next-id.sh` — monotonic REQ-NNN cross-spec generator
   - `context/<topic>.md` template в `references/templates.md`
   - 24 new tests (13 EARS + 6 req-id + 5 registration). pytest 293 → 317 passed.
   - Plan: [plans/done/2026-04-25_feature_phase2-sprint1-discuss-ears.md](plans/done/2026-04-25_feature_phase2-sprint1-discuss-ears.md)

- **✅ Sprint 3 — I-028 fix (multi-active correctness)** [2026-04-25]
   - Маркеры `<!-- mb-plan:<basename> -->` эмитятся sync-скриптом
   - Remove-logic в done-скрипте — plan-scoped по маркеру с backward-compat fallback
   - 4 collision-теста (pytest) + bats fixture v2-rename catch-up (4 файла)
   - pytest 289 → 293 passed; bats 479 → 515 passed
   - Plan: [plans/done/2026-04-25_refactor_sprint3-multi-active-fix.md](plans/done/2026-04-25_refactor_sprint3-multi-active-fix.md)

## Linked Specs (manual notes)

- `specs/mb-skill-v2/` — skill v2 design doc (Phase 1 completed; Phase 2 Sprint 1 done)

## Open high/medium backlog (см. backlog.md)

- I-028 ✅ resolved в Sprint 3 (multi-active marker-based ownership, 2026-04-25)
- I-026 ✅ resolved в Sprint 2 (Phase/Sprint/Task parser)
- I-023 (MED) — grep→find в start.md/mb-doctor

## Roadmap high-level

- **Phase 1 — Foundation** ✅ COMPLETE (rename + autosync + traceability-gen infrastructure)
- **Phase 2 — Discussion & SDD artifacts** ✅ COMPLETE (discuss+EARS+context, /mb sdd, SDD-lite)
- **Phase 3 — Work engine** ✅ COMPLETE (pipeline.yaml + /mb config, /mb work + 9 role-agents, review-loop + severity gates)
- **Phase 4 — Hardening** ✅ COMPLETE (plan-verifier + 4 critical hooks, --auto/--range/--budget + sprint_context_guard, installer + superpowers overrides)
- **Phase 4.x — Storage + rules + SDD unification** ✅ COMPLETE (global-storage + rule-profiles + sdd-unification + GraphRAG-lite)
- **Phase 5 — Code-graph + session memory** ✅ COMPLETE (`tier1-graph-memory` 17/17 → v5.1.0; codegraph-analytics; mb-research-tooling-core)
- **Phase 6 — Harness + adaptive orchestration** 🔄 ACTIVE → see `## ICE-prioritised roadmap` выше. `goal-driven-autopilot` снят (→ `dynamic-flow`). Sequence: cursor-finish → handoff-v2 → dynamic-flow → reviewer/work-loop/cost chain.

## See also
- traceability.md — REQ coverage matrix (пока "No specs yet", Phase 2 заполнит)
- backlog.md — future ideas & ADR
- checklist.md — current in-flight tasks
- notes/2026-04-22_20-30_sprint3-vs-phase2-priority.md — обоснование порядка Sprint 3 → Phase 2

---

### Legacy content (preserved from the previous plan-file format — review and integrate above)

# claude-skill-memory-bank — План

## Текущий фокус

**v3.0.0 stable + public website live.** Core release уже shipped, а 2026-04-21 для репозитория поднят GitHub Pages лендинг `https://fockus.github.io/skill-memory-bank/`. P0 hardening из full-repo review закрыт: 3 High finding'а покрыты тестами, `mb-compact.sh` снова отвечает только за decay, structural migration возвращён в `mb-migrate-structure.sh`, а installer/adapter surface сокращён перед `v3.1.0`.

После обратной связи внешнего ревью составлен план на 9 stages через 3 минорных релиза (уточнён 2026-04-20):

- **v2.1 (stages 1-4):** Auto-capture, drift checkers без AI, PII markers, compaction decay
- **v2.2 (stages 5-7):** JSONL import, tree-sitter code graph, tags normalization
- **v3.0 (stages 8-9):** Cross-agent (Cursor/Windsurf/Cline/Kilo/OpenCode/Pi Code/Codex) + repo migration + pipx/PyPI distribution + Homebrew tap
- **v3.1+ backlog:** benchmarks (LongMemEval), sqlite-vec, native memory bridge

Фактический статус по аудиту 2026-04-20:

- ✅ Stages 1-8 закрыты в `checklist.md`
- 🔄 Stage 8.5 закрыт частично (migration сделана в коде/remote, release continuity ещё не доведена)
- 🔄 Stage 9 закрыт частично (package/docs/workflows готовы, release verification и smoke зелёные, не закрыты final release chores)
- ⬜ Gate v3.0 не выполнен: verification и smoke зелёные, но не завершены final release actions

Полный план: `plans/2026-04-20_refactor_skill-v2.1.md`.

## Active plans

<!-- mb-active-plans -->
- [2026-05-24] [plans/2026-05-24_fix_cursor-compatibility-remediation.md](plans/2026-05-24_fix_cursor-compatibility-remediation.md) — fix — Cursor Compatibility Remediation (in progress)
- [2026-05-23] [plans/2026-05-23_feature_handoff-v2.md](plans/2026-05-23_feature_handoff-v2.md) — feature — Handoff 2.0
- [2026-05-23] [plans/2026-05-23_feature_reviewer-v2.md](plans/2026-05-23_feature_reviewer-v2.md) — feature — Reviewer 2.0
- [2026-05-23] [plans/2026-05-23_feature_work-loop-v2.md](plans/2026-05-23_feature_work-loop-v2.md) — feature — Work loop 2.0
- [2026-05-23] [plans/2026-05-23_feature_cost-multi-model.md](plans/2026-05-23_feature_cost-multi-model.md) — feature — Cost (multi-model role assignment)
- [2026-05-23] [plans/2026-05-23_feature_skill-improvements-anthropic-audit.md](plans/2026-05-23_feature_skill-improvements-anthropic-audit.md) — feature — skill-improvements-anthropic-audit (docs, parallel-safe)
- [2026-05-24] [plans/2026-05-24_feature_parallel-pipeline.md](plans/2026-05-24_feature_parallel-pipeline.md) — feature — Parallel pipeline (⚠️ arch decision vs dynamic-flow)
- [2026-05-24] [plans/2026-05-24_fix_pi-compatibility-remediation.md](plans/2026-05-24_fix_pi-compatibility-remediation.md) — fix — Pi Compatibility Remediation
<!-- /mb-active-plans -->

## Ближайшие шаги

1. v3.1.2 shipped — no active plans. Next work: v3.2.0 (agents-quality tag, CHANGELOG [3.2.0] already staged), or Stage 8.5 repo-migration cleanup.
2. Optional: Stage 7 `mb-session-recoverer` when user signal arrives.

## Уточнено 2026-04-20

- **Pi Code** = [pi-coding-agent от badlogic](https://github.com/badlogic/pi-mono) — 6-й adapter в Stage 8; **Codex** добавлен как 7-й adapter (ADR-010)
- **Distribution** — pipx/PyPI primary (наш стек уже 12% Python), Homebrew tap secondary, Anthropic plugin tertiary. npm отменён.
- **Имена**: `memory-bank-skill` на PyPI ✓ свободно, `@fockus/memory-bank` на npm ✓ свободно (reserved на будущее), `fockus/homebrew-tap/memory-bank` создать при release
- **Benchmarks (Stage 10)** отложены в v3.1+ backlog

## Отклонено (после ревью)

- **Hash-based IDs** — решает multi-device конфликты, которых у нас нет (YAGNI)
- **KB compilation (`concepts/`, `connections/`, `qa/`)** — преждевременная иерархия
- **GWT в DoD** — дублирует test requirements в текущем шаблоне плана
- **Schema drift detection** — domain-specific, не fits generic skill
- `**/mb debug`** — дублирует `superpowers:debugging` skill
- **Viewer UI** — chrome over substance
- **REST API / daemon mode** — ломает наше архитектурное преимущество (simplicity, 93% Shell)
- **OpenAI/Cohere embeddings через API** — не деремся, local MiniLM

## Отложено (v3.1+ backlog)

- **sqlite-vec semantic search** — после Gate v3.0, когда keyword+tags+codegraph окажутся insufficient
- **i18n error-сообщений**
- **Native memory bridge** (программная синхронизация с Claude Code auto memory)
- **Viewer dashboard** (если adoption потребует)
