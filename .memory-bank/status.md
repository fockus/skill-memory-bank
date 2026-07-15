
# claude-skill-memory-bank: Статус проекта

## ✅ 2026-07-15 — `openspec-adapter` спека реализована (T1–T6), один пункт отложен

One-way import-адаптер `OpenSpec change → наш spec-триплет` (AGR-016) — **T1–T6 done**. T1–T3 core (парсинг+конвертация+запись, `a2e9252`/`66cd650`, judge GO_WITH_BACKLOG I-120) закрыт ранее; в этой сессии добрали **T4 CLI-диспетчер** (`scripts/mb-openspec.sh` import/list/status/sync, `4bebbbc`), **T5 re-import** (anchor_map + merge_task_state + RENAMED re-anchor + orphan→backlog, `0f39618`), **T6 --normalize** (опц. LLM slot-layer + source-hash кэш, fail-open, `226e65f`). Пайплайн этой сессии — **укороченный, по явному запросу пользователя, не сохранён в pipeline.yaml**: Sonnet implement → Opus independent verify, без review/judge; все три задачи прошли независимую верификацию Opus. 45+15+52 pytest/bats green по задачам.

**Единственный отложенный пункт:** T4 DoD-строка «завести `/mb openspec` в `commands/mb.md`» — файл под активным adapter-parity FREEZE (`COORDINATION.md`), не трогаем. Диспетчер `mb-openspec.sh` работает автономно; роутер-строка встанет сразу после снятия заморозки. Спека фактически завершена (T1–T6) за вычетом этой одной строки.

## ✅ 2026-07-15 — donor-программа специфицирована (Track 2)

Donor-план (`memory-bank-donor-evolution-plan.md`, 4246 строк) превращён в валидную umbrella-спеку **`specs/mb-donor-evolution/`**: requirements.md (108 REQ, EARS, 52 GWT-сценария), design.md (471 строка: инварианты, контракты §7, capability matrix, ADR), tasks.md (**132 исполняемых mb-task блока**), source-plan.md (read-only источник). `mb-spec-validate.sh --require-scenarios` — **0 нарушений**; traceability: 334/337 покрыто (3 сироты — старая parallel-team-execution).

Discovery — гриллинг-интервью (= discuss-фаза, AGR-005): решения в `context/mb-donor-evolution.md` и AGR-001…005. Ключевое: нумерация +1 минор (Baseline→**v5.4.0**, …, Plan IR→5.7.0; 6.x без сдвига); roadmap — две дорожки, donor побеждает при пересечении; `parallel-pipeline` → **superseded**; ICE: v6.5/v6.6 (GSD/OpenSpec engines) → **icebox**. ICE-таблица и порядок — `roadmap.md` § Track 2. Первый релиз — wrapper `plans/2026-07-15_feature_mb-donor-evolution-v5-4-baseline.md` (queued, tasks 1–6). Попутно `/mb discuss` усилен grilling-правилами 6–8 (one-question-per-turn, relentless-until-shared-understanding, final confirmation gate).

## ✅ 2026-07-13 — main stabilized + **5.3.0 released** (issue #2 closed)

**`main` was red for over a week and a broken wheel was on PyPI.** Both are fixed.

**The redness was five layers**, three of them from a single commit (`49f9ad5`) that shipped twice-broken code:
1. `scripts/_lib.sh` — unterminated heredoc quote (`<<'PY`). Sourced by *every* `mb-*.sh` → the whole toolchain was dead.
2. `hooks/mb-session-turn.sh` — **raw merge-conflict markers committed**. Unparseable; every deploy re-installed the broken copy.
3. shellcheck ×3 · 4. ruff ×2 (masked — shellcheck failed first) · 5. `install.sh` re-install backed up its *own* `CLAUDE.md`, so the install manifest was never idempotent.

**Two judgement calls worth keeping:**
- The hook conflict: **both sides carried needed logic.** Taking either alone would have silently reverted the I-082 security control `sc_strip_private` (`<private>` spans reaching disk). Merged both.
- The "6 known-baseline-red bats" were **not a bug** — an ambient `MB_AUTO_CAPTURE` env leak. Green in clean CI all along, and wrongly written off. 5 suites are now hermetic.

**Release 5.3.0** — issue #2 (`5.2.0` wheel shipped without `templates/` → `/mb init` exit 3 for every pipx user) was unfixable without a release: the packaging fix was **not an ancestor of tag `v5.2.0`**, and PyPI forbids re-upload. Verified end-to-end on the **published** wheel: `mb-init-bank.sh` exit 3 → **0**, bank scaffolds. Homebrew formula bumped with the sdist digest re-derived locally and cross-checked against the PyPI API.

Cross-session coordination also shipped (`references/coordination.md` had been untracked while `CLAUDE.md`/`rules/` already referenced it).

---

## ⏸ PAUSE 2026-07-06 — long-running-sessions autopilot (Opus plans → Sonnet impl / Codex review / Opus judge)

**Активный мастер-план:** `plans/2026-07-05_SEQUENCE_long-running-sessions.md` — 6 фаз для автономных длинных сессий (goal-driven ralph-loop + параллельные сессии по плану). Роли зафиксированы: **планы пишет Opus напрямую; реализация через `/mb work` — implement=Sonnet, review=Codex GPT-5.5, judge=Opus**; любой сабагент-исполнитель работает на Sonnet.

| Phase | Спека | Статус |
|---|---|---|
| **1 — reviewer-2.0** | `specs/reviewer-2.0` | ✅ **DONE** — 6 задач, коммиты `45737fb 9d0a2e1 113b9b5 7e3604a 1ac1c49 7fb3db4`. Codex поймал 3 реальных дефекта (path-traversal, symlink-эксфильтрация, count-lie bypass strict-mode) |
| **2 — work-loop-v2** | `specs/work-loop-v2` | ✅ **DONE** — 5 задач: trend (`ea3a3ab`), contract (`a39d4a2`), pivot (`930c0ec`), on_max_cycles migration (`b419eee`), docs (`86240f7`) |
| **3 — drive-loop** | `specs/drive-loop` | 🔄 **IN PROGRESS.** Task 1 ✅ DONE (`1bf101b`) — `mb-drive.sh next` stateless decision fn; Codex BLOCKER (type-coercion `{"ok":"true"}`→`stop_success`, нарушал REQ-DR-014) + 5 major исправлены fail-closed, judge GO_WITH_BACKLOG. **Осталось: Task 2** (`/mb drive` команда + AGENTS.md loop-contract, developer), **Task 3** (trend/pivot + route-reeval wiring — тот seam, что T1 оставил: stall/last_pivot из mb-flow fence), **Task 4** (stop-telemetry + Stop-hook resume-gate + parallel keying, devops), **Task 5** (docs, analyst) |
| 4 — parallel | `parallel-pipeline` / `parallel-team-execution` | ⬜ на `mb-fanout.sh` |
| 5 — cost-multi-model + df-P3 | — | ⬜ dynamic-flow Phase 3 Tasks 13-14 |
| 6 — docs | — | ⬜ финал: «как всем этим пользоваться» |

**▶ ТОЧКА ВОЗОБНОВЛЕНИЯ:** drive-loop **Task 2**. Директива пользователя — «Полный автопилот до конца» (фазы 2-6 подряд, отчёт в конце), сейчас на паузе по запросу.

**Backlog, накопленный за автопилот:** I-095 (DRY-fold), I-096 (inert cache path), I-097 (pipeline review_examples wiring), I-098 (split mb-review.sh 501ln), I-099 (cache-key reconcile), I-100 (composable `--review` empty loop), I-101 (traceability `.bats` suffix), **I-102 (mb-drive.sh 455>400 → Task-1b split)**.

**⚠️ Параллельная незакоммиченная работа (НЕ трогать при коммитах):** install-parity правки в `adapters/*`, `install.sh`, `packaging/`, `README.md`, `docs/cross-agent-setup.md`, `tests/bats/test_{codex,cursor,graph,cline,opencode}_adapter.bats`, `tests/e2e/*`, `scripts/mb-reviewer-resolve.sh` + `test_reviewer_resolve.bats`, `.memory-bank/{checklist,roadmap,pipeline.yaml,traceability}.md`, `specs/{reviewer-2.0,work-loop-v2}/design.md`. Коммиты всегда scoped через явный `git add <paths>`, никогда `-A`.

**Phase 0 doc-drift residual (no-code):** status/roadmap/checklist местами говорят «dynamic-flow Phase 2 paused», хотя на диске она done — чистка не сделана.

---

## Current phase

**Phase 6 — Harness + adaptive orchestration.** Phase 5 (`tier1-graph-memory` 17/17 → **v5.1.0**) закрыт. Roadmap переприоритизирован по **ICE** (см. `roadmap.md § ICE-prioritised roadmap`). `goal-driven-autopilot` **снят** — заменён на `specs/dynamic-flow/` (8 мёртвых планов → `plans/superseded/`). Последовательность (dependency-resolved): **cursor-finish → handoff-v2 → dynamic-flow Phase 1 → reviewer-2.0 → work-loop-v2 → cost-multi-model**; docs-лейн `skill-improvements-anthropic-audit` параллельно. XL-хвост (`parallel-pipeline` / `parallel-team-execution`) — после арх-решения host-native vs orchestrator-owned.

**⚠️ Versioning change (2026-06-10):** v5.0.0 cut **early** — не после W12. Причина: 4.0.0 получил git-тег, но публикация в PyPI провалилась (`__version__` drift, исправлено runtime-чтением VERSION), а с тех пор накопился крупный пласт (GraphRAG-lite intelligence layer, session-memory, rules-economy, composable `/mb work` pipeline с review-off-by-default = BREAKING). Это первый PyPI-релиз с 3.1.2. Harness-работа становится пост-5.1.0 (5.x/6.0). Актуальная последовательность → `roadmap.md § ICE-prioritised roadmap`.

**Predecessor phases ✅:** sdd-unification (3 sprints), global-storage core + agent-support, rule-profiles-and-stack-presets, GraphRAG-lite code intelligence.

## ⏭ Следующий шаг

**🔄 codex/GPT-5.5 remediation — 2026-06-23.** v5.1.0 **отгружен** (PyPI + GitHub Release), `main` CI **зелёный** (post-release red закрыт: `3c16381` + `e04c4e7`). 9-агентное codex-ревью (6 аспектов + 3 транспорта) → backlog **I-082..I-086** + 5 fix-планов + sequence-документ. **Порядок исполнения — `plans/2026-06-23_SEQUENCE_codex-remediation.md` (= `roadmap.md § Current focus 2026-06-23`):**
- **Wave 1 (→5.1.1, urgent):** I-082 security-hardening (code-exec в отгруженном коде) → I-083 verification-gates (fail-closed) → I-085 logic+portability (empty-`--range`→весь план BLOCKER).
- **Wave 2 (→5.2.0):** I-086 config-validation+docs → I-084 dispatcher-wiring+transports (pi/opencode/codex executable end-to-end).

Каждый план — governed `/mb work` (`codex-governed`: implement → verify → dual review → **judge=mb-judge** → fix-cycle → done), TDD-first, bash 3.2+5.x, Python 3.11. Hard deps: I-082→I-085 (общий `_lib.sh::mb_canonical_under`), I-086→I-084 (validator + единый pipeline-resolution path). **Следующий шаг: запустить Wave 1 / I-082** по явному go.

**✅ spec `tier1-graph-memory` (17/17 tasks) COMPLETE — 2026-06-14.** Delivered end-to-end through the governed `/mb work` machine: implement (Opus subagents) → verify → DUAL parallel review (Codex gpt-5.5 + main-agent) → judge (GO / GO_WITH_BACKLOG / NO_GO) → fix loop ≤2 then `judge_decides`. All 17 tasks committed on `main` (c015831, 491b717, 21ba225, ca6a358, 74f14a1, 3434cb3, a0d6711, e1bbff1, 5a041d2, 8c8d900, b365e59, 73a095e, 7ba7174, 4bca7f6, 1e94d6d, 0ac97f2, 8ff17bb). Three release-gated backlog items closed: I-069 (07221e9), I-066+I-067 (306835a). Version bumped 5.0.1 → 5.1.0.

**Next — explicit user "go" required for: PyPI publish + git tag of 5.1.0.** Release is PREP-only (committed VERSION + CHANGELOG); publish/tag are NOT done. Remaining open backlog from the sprint stays out of the gate: I-064/I-065 (LOW/MED docstrings) + I-068 (pre-existing flaky `session-end-judge.bats`).

**Roadmap hygiene done — 2026-06-14.** Закрыты готовые планы (subagent-strengthening, codegraph-analytics), 8× goal-driven + opencode-first → `plans/superseded/`, roadmap/status переписаны под ICE.

**✅ Wave 1 [cursor-extension] DONE (f86247c) + ✅ Wave 2 [handoff-v2] DONE (2026-06-15).** handoff-v2 — 5/5 tasks через governed dual-review (Codex gpt-5.5 + lead) + judge, fix-cycle на каждую задачу: handoff-капсула, PreCompact/SessionStart хуки, обязательные `/mb done` gates, append-only sha256-цепочка `progress.md`, docs. **Закрыто после ВТОРОГО независимого прохода ревью (I-076):** lead-only re-verification после fix-cycle 1 была преждевременной — 3 доп. независимых раунда Codex поймали реальные дефекты (process-tree kill без `setsid`, budget-арифметика `$'1\nabc'`/`08`-octal/overflow → нарушения never-block; falsy-tail `or []` молча отключал verify; тавтологический deep-kill тест). Все critical/major закрыты, budget-валидация исчерпывающа по всему домену. Final pytest **1461** / full bats **871**, shellcheck+ruff clean, оба code-фикса RED→GREEN. Judge: **GO**. **Следующий код-wave: reviewer-2.0** (голова harness-цепочки).

**✅ Wave 3 [dynamic-flow Phase 1] DONE (2026-06-16, ICE 378).** Все 7 задач (T2–T7) отгружены через governed dual-review (Codex gpt-5.5 + lead) + judge, fix-cycle на каждую: goal primitive, `mb-flow-sync` fence writer, thin check runners, **THE firewall** `mb-flow-verify.sh` (`a191aa3`, 7 независимых раундов), closure wiring CC Stop-hook + git-hooks fallback (`947a506`, 4 раунда, agent-identity детерминирован на всех точках входа), AGENTS.md firewall-contract (`9ee43e9`). Детерминированный «нельзя соврать про done»: завершение гейтится exit-кодом firewall, не самооценкой (REQ-DF-060). Binding principle: финальный GO только после свежего независимого ревью исправленного кода. Все DoD T2–T7 ✅ в `specs/dynamic-flow/tasks.md`. Phase 2-3 (mini-router + templates + adapters) deferred. См. I-077.

После инфраструктурного unlock: стартовать **W4 code — reviewer-2.0** (`specs/reviewer-2.0`, ICE 224 — голова harness-цепочки) и **W docs — [skill-improvements-anthropic-audit](plans/2026-05-23_feature_skill-improvements-anthropic-audit.md)**. Закрытие каждого wave: `/mb verify` → `/mb done` → plan moves to `plans/done/`.

## Open backlog

- I-062 (MED) — ужесточить EARS-валидатор и spec-checking (per-pattern regex, atomicity, REQ-ID uniqueness, ранний REQ→task lint, traceability drift). Замечено на реальном `/mb discuss` во внешнем проекте. См. `notes/2026-05-29_ears-validator-hardening.md`.
- I-023 (MED) — `grep → find` cleanup в `start.md` / `mb-doctor` (low risk, дешёвый когда дойдут руки)
- I-034 (MED) — plugin-namespaced skill detection в reviewer-resolve
- I-061 (HIGH) — Cursor compatibility remediation: stages 1–6 implemented; bats 38/38 green on cursor suites; pytest pending local env. See `reports/2026-05-24_cursor-compatibility-audit.md`, spec `cursor-extension`.
- I-045 (HIGH) — Pi compatibility remediation: fix docs, sequential fallback in S5 spec, GraphRAG extension decision. See `reports/2026-05-24_pi-compatibility-audit.md`
- I-046 (MED) — `test_pi_adapter.bats` expansion: prompt install, skill content, hook body, MB_PATH propagation tests
- I-047 (MED) — Pi `agents/*.md` global install path (currently only Claude gets agents globally)
- I-048 (HIGH) — OpenCode global skill alias in `install.sh`
- I-049 (HIGH) — Commands frontmatter OpenCode compatibility (`agent`/`subtask` fields)
- I-050 (MED) — OpenCode plugin hooks parity (map bash hooks to TS plugin)
- I-053 (MED) — Cross-agent research note Pi native hooks disclaimer
- I-054 (HIGH) — `scripts/mb-dispatch.sh`: host-agnostic dispatch abstraction. Blocks W1–W12 on OpenCode. See `reports/2026-05-24_plans-specs-opencode-gap-analysis.md` §5.1.
- I-055 (HIGH) — `references/opencode-hooks-mapping.md` + plugin guards (`onBeforeToolExecute`, `experimental.session.compacting`, `onReady`). Blocks W3 handoff-v2 on OpenCode.
- I-056 (HIGH) — OpenCode plugin-first architecture: replace `adapters/opencode/dispatch.sh` bash loop with JS plugin. Blocks W12 parallel-pipeline on OpenCode.
- I-057 (MED) — Model resolver OpenCode probe: `mb-pipeline-model-resolve.sh` should check `.opencode/skills/` and `~/.config/opencode/skills/`. Blocks W4.
- I-058 (MED) — Provider-neutral model aliases: per-host resolution instead of hardcoded Anthropic IDs. Blocks W4 on OpenCode (Kimi defaults).
- I-059 (MED) — OpenCode test fixtures: `test_opencode_*.bats` for dispatch/guards/hooks per wave.
- I-060 (LOW) — Commands `*.md` OpenCode frontmatter for all 24+ command files.

Все HIGH-приоритетные items на момент v4.0.0 ship + audit-remediation: I-045 (Pi), I-048/I-049 (OpenCode inline fixes), I-054/I-055/I-056 (OpenCode structural gaps).

## Ключевые метрики

- VERSION: **5.3.1** (OpenSpec import adapter `/mb openspec` + running-list-of-agreements `/mb agree` + SessionStart update-notify. Prior 5.3.0 = `templates/` packaging fix for issue #2; 5.2.0 = context-window statusline; 5.1.0 = tier1-graph-memory layer)
- Shell-скрипты в `scripts/`: **42**, Python-скрипты в `scripts/`: **9**, Hooks: **10**
- Агенты: **17 dispatchable** (3 utility: manager/doctor/codebase-mapper + 3 verifiers: plan-verifier/rules-enforcer/test-runner + 10 role-agents для `/mb work`: developer/architect/backend/frontend/ios/android/devops/qa/analyst/reviewer + 1 research: `mb-research`) + **partials** (`mb-engineering-core`, `mb-tooling-core` — prepended, never dispatched). `install.sh` `AGENT_COUNT` glob = **21**.
- Commands: **24** top-level (`/mb` hub + 23 dispatchers; `/mb research` added 2026-06-09).
- Tests: **pytest 1190 passed / 0 failed · bats 779 ok / 0 failures** (2026-06-10, after `composable-work-pipeline` + v5.0.0 docs; +29 vs the 1161 post-`mb-research-tooling-core` baseline). shellcheck/ruff clean; `python -m build` → `memory_bank_skill-5.0.0` sdist+wheel (`.memory-bank/` excluded). GitHub `test.yml` last green `26528106396` (pre-5.0.0); re-run on push.
- Public website: **https://fockus.github.io/skill-memory-bank/**
- Текущий remote: `origin=https://github.com/fockus/skill-memory-bank.git`

## Active plans

<!-- mb-active-plans -->
- [2026-05-24] `in_progress` [2026-05-24_fix_cursor-compatibility-remediation.md](plans/2026-05-24_fix_cursor-compatibility-remediation.md) — fix — Cursor hook parity + adapter bundle paths (spec: cursor-extension)
- [2026-05-24] `queued` [2026-05-24_feature_opencode-first-adaptation.md](plans/2026-05-24_feature_opencode-first-adaptation.md) — feature — Plan: feature — OpenCode-first adaptation (native plugin, dispatch abstraction, hook parity; cross-cutting infrastructure for W1–W12)
- [2026-05-24] `queued` [2026-05-24_fix_pi-compatibility-remediation.md](plans/2026-05-24_fix_pi-compatibility-remediation.md) — fix — Plan: fix — Pi extension (subagents + hooks + commands + model providers)
- [2026-05-23] `queued` [2026-05-23_feature_cost-multi-model.md](plans/2026-05-23_feature_cost-multi-model.md) — feature — Plan: feature — Cost (multi-model role assignment, S4 of harness-upgrade)
- [2026-05-23] `queued` [2026-05-23_feature_goal-driven-autopilot-sprint-1-prompt-overlay.md](plans/2026-05-23_feature_goal-driven-autopilot-sprint-1-prompt-overlay.md) — feature — Plan: feature — goal-driven-autopilot — Sprint 1: Prompt overlay + addons
- [2026-05-23] `queued` [2026-05-23_feature_goal-driven-autopilot-sprint-2-mb-debugger.md](plans/2026-05-23_feature_goal-driven-autopilot-sprint-2-mb-debugger.md) — feature — Plan: feature — goal-driven-autopilot — Sprint 2: mb-debugger + `/mb debug`
- [2026-05-23] `queued` [2026-05-23_feature_goal-driven-autopilot-sprint-3-worktree.md](plans/2026-05-23_feature_goal-driven-autopilot-sprint-3-worktree.md) — feature — Plan: feature — goal-driven-autopilot — Sprint 3: Worktree isolation
- [2026-05-23] `queued` [2026-05-23_feature_goal-driven-autopilot-sprint-4-atomic-commit.md](plans/2026-05-23_feature_goal-driven-autopilot-sprint-4-atomic-commit.md) — feature — Plan: feature — goal-driven-autopilot — Sprint 4: Atomic commit per stage
- [2026-05-23] `queued` [2026-05-23_feature_goal-driven-autopilot-sprint-5-parallel-waves.md](plans/2026-05-23_feature_goal-driven-autopilot-sprint-5-parallel-waves.md) — feature — Plan: feature — goal-driven-autopilot — Sprint 5: Parallel waves (DAG)
- [2026-05-23] `queued` [2026-05-23_feature_goal-driven-autopilot-sprint-6-goal-layer.md](plans/2026-05-23_feature_goal-driven-autopilot-sprint-6-goal-layer.md) — feature — Plan: feature — goal-driven-autopilot — Sprint 6: Goal layer + `/goal`
- [2026-05-23] `queued` [2026-05-23_feature_goal-driven-autopilot-sprint-7-autopilot.md](plans/2026-05-23_feature_goal-driven-autopilot-sprint-7-autopilot.md) — feature — Plan: feature — goal-driven-autopilot — Sprint 7: Autopilot loop
- [2026-05-23] `queued` [2026-05-23_feature_reviewer-v2.md](plans/2026-05-23_feature_reviewer-v2.md) — feature — Plan: feature — Reviewer 2.0 (S1 of harness-upgrade)
- [2026-05-23] `queued` [2026-05-23_feature_skill-improvements-anthropic-audit.md](plans/2026-05-23_feature_skill-improvements-anthropic-audit.md) — feature — Plan: feature — skill-improvements-anthropic-audit
- [2026-05-23] `queued` [2026-05-23_feature_work-loop-v2.md](plans/2026-05-23_feature_work-loop-v2.md) — feature — Plan: feature — Work loop 2.0 (S2 of harness-upgrade)
- [2026-05-24] `queued` [2026-05-24_feature_parallel-pipeline.md](plans/2026-05-24_feature_parallel-pipeline.md) — feature — Plan: feature — Parallel pipeline (S5 of harness-upgrade)
- [2026-05-23] `paused` [2026-05-23_feature_goal-driven-autopilot-phase.md](plans/2026-05-23_feature_goal-driven-autopilot-phase.md) — feature — Plan: feature — goal-driven-autopilot (Phase roadmap)
<!-- /mb-active-plans -->

## Recently done

<!-- mb-recent-done -->
- 2026-06-15 — [specs/handoff-v2/](specs/handoff-v2/) — feature — Handoff 2.0 (5/5): handoff capsule + PreCompact/SessionStart hooks + mandatory `/mb done` gates + append-only sha256 progress chain + docs; governed dual-review (Codex + lead) + judge, fix-cycle per task
- 2026-06-14 — [specs/tier1-graph-memory/](specs/tier1-graph-memory/) — feature — Tier-1 graph + session memory (17/17): RRF/import-aware/PageRank graph, progressive-disclosure recall, `/mb recap`+`/mb conflicts`+`/mb consolidate`, `--sessions` graph layer, wiki staleness+decisions; + 5.1.0 release prep
- 2026-06-10 — [specs/composable-work-pipeline/](specs/composable-work-pipeline/) — feature — composable `/mb work` pipeline (review off by default) + v5.0.0 release prep
- 2026-06-09 — [plans/done/2026-06-09_feature_mb-research-tooling-core.md](plans/done/2026-06-09_feature_mb-research-tooling-core.md) — feature — mb-research-tooling-core
- 2026-06-07 — [plans/done/2026-06-07_refactor_rules-context-economy.md](plans/done/2026-06-07_refactor_rules-context-economy.md) — refactor — rules-context-economy
- 2026-05-27 — [plans/done/2026-05-24_fix_ci-baseline-wave-0.md](plans/done/2026-05-24_fix_ci-baseline-wave-0.md) — fix — CI baseline (Wave 0 before Wave 1; latest green `26528106396`)
- 2026-05-24 — [plans/done/2026-05-21_feature_rule-profiles-and-stack-presets.md](plans/done/2026-05-21_feature_rule-profiles-and-stack-presets.md) — feature — rule-profiles-and-stack-presets
- 2026-05-24 — [plans/done/2026-05-21_feature_global-storage-agent-support.md](plans/done/2026-05-21_feature_global-storage-agent-support.md) — feature — global-storage-agent-support
- 2026-05-24 — [plans/done/2026-05-21_feature_global-storage.md](plans/done/2026-05-21_feature_global-storage.md) — feature — global-storage-core
- 2026-05-23 — [plans/done/2026-05-21_refactor_sdd-traceability-docs.md](plans/done/2026-05-21_refactor_sdd-traceability-docs.md) — refactor — sdd-traceability-docs
- 2026-05-23 — [plans/done/2026-05-21_refactor_sdd-work-engine.md](plans/done/2026-05-21_refactor_sdd-work-engine.md) — refactor — sdd-work-engine
- 2026-05-23 — [plans/done/2026-05-21_refactor_sdd-task-model.md](plans/done/2026-05-21_refactor_sdd-task-model.md) — refactor — sdd-task-model
- 2026-05-21 — [plans/done/2026-05-21_architecture_graph-rag-lite-code-context.md](plans/done/2026-05-21_architecture_graph-rag-lite-code-context.md) — architecture — graph-rag-lite-code-context
<!-- /mb-recent-done -->

---

## Архив — Released gates (passed ✅)

| Release | Date | Highlights |
|---------|------|------------|
| **v4.0.0** | 2026-04-25 | Skill v2 refactor: pipeline.yaml + `/mb work` + 10 role-agents + review-loop + 5 hooks + checklist hard-cap. Tests 335 → 596+ → 638. |
| **v3.1.2** | 2026-04-21 | Review-hardening + installer-boundaries + core-files-v3-1 + agents-quality. PyPI/Homebrew sync. |
| **v3.1.0/1** | 2026-04-21 | `/mb compact`, `/mb tags`, `/mb import`, GitHub Pages landing |
| **v3.0.0** | 2026-04-20 | 7 cross-agent adapters (Cursor/Windsurf/Cline/Kilo/OpenCode/Pi/Codex), pipx/PyPI distribution, Homebrew tap |
| **v2.1.0** | 2026 | Auto-capture, drift checkers без AI, `<private>` PII redaction, compaction decay |
| **v2.0.0** | 2026 | Language-agnostic stack detection, CI integration, TDD-based workflow |

Полные details — `plans/done/`, `progress.md` (per-day), `lessons.md` (recurring patterns).

## Архив — Решённые вопросы (исторически)

- ✅ Pi Code остаётся adapter'ом Stage 8; Codex добавлен как 7-й adapter (ADR-010)
- ✅ Distribution strategy: pipx/PyPI primary, Homebrew secondary, Anthropic plugin tertiary
- ✅ Benchmarks (LongMemEval) перенесены в backlog
- ✅ Merge `v2.2.0` absorbed в `3.0.0-rc1` (formal cut пропущен)
- ✅ Старый repo `claude-skill-memory-bank` оставлен как archive remote; canonical = `skill-memory-bank`

## Backlog (next iteration ideas)

- Benchmarks (LongMemEval + custom scenarios)
- sqlite-vec semantic search
- i18n error-сообщений
- Native memory bridge (программная синхронизация с Claude Code auto memory)
- Viewer dashboard (если adoption потребует)
