# claude-skill-memory-bank — Lessons & Antipatterns

Накапливаются по ходу рефактора v2.

## Meta / Skill Design

### Single-source rule + propagation gap (2026-04-27 / Stage 7)

`references/templates.md` § *Plan decomposition* объявил каноничную иерархию **Phase → Sprint → Stage** с порогами и правилами. Текст был корректный, но он жил в одном месте — а пользователь видит проект через десятки дверей: SKILL.md, README.md, RULES.md, `commands/plan.md`, `commands/mb.md`, `references/planning-and-verification.md`. На каждой такой двери терминология свободно дрейфовала: чеклист использовал «Этап», бэклог — «Спринт», план — Phase/Sprint/Stage, статус — «фаза». Snowball-эффект: следующий контрибьютор копировал ближайший пример, рассинхронизация росла.

**Lesson:** правило, которое не propagated в каждый surface где пользователь его читает, — **invisible**. SSoT необходим, но недостаточен. Расширение паттерна «declarative intent ≠ contract» (2026-04-25): теперь не только intent должен быть encoded в код, но и сам факт ссылки на правило должен быть encoded в **каждой** входной точке.

**Antidote pattern:**
1. **SSoT** — одна каноничная локация (здесь `references/templates.md`). Не дублировать содержимое.
2. **Cross-link refs** — в каждой surface (rules, commands, references, top-level docs) — одна-две строки «See `<SSoT>` § X». Не больше: дубль фактической логики ⇒ drift.
3. **Drift-чекер** — деривативный тест в `mb-drift.sh` который автоматически ловит появление legacy-терминов outside whitelist. Whitelist: SSoT сам себя цитирует, frozen archives (`plans/done/`), historical logs (`progress.md`, `lessons.md`), CHANGELOG. Активный surface — проверяется.
4. **Soft-warn в creator script** — `mb-plan.sh` печатает stderr-warn если topic содержит legacy-термин, но не блокирует. UX-приоритет: не отбирать у пользователя право назвать что угодно. Hard-block тут — over-engineering.
5. **Тестовый контракт** — pytest проверяет что каждый surface действительно ссылается на SSoT (не «должен», а «существует строка с правильным path»). Иначе цикл повторится через 2 спринта.

Сравни с lesson «declarative intent ≠ contract»: оба о том что **слова должны быть подкреплены кодом** (тест, чекер, warn, lifecycle hook). Stage 7 — конкретное приложение этого мета-правила к терминологии.

### "Rotating" артефакт без enforcement = накапливающийся (2026-04-25)

Spec §3 объявил `checklist.md` как **rotating** артефакт ("задача существует только пока stage активен; после `/mb done` → `progress.md`"). Spec §13 запланировал `mb-checklist-auto-update.sh` под `/mb done`. Не построили. В итоге каждый закрытый Sprint оставался в checklist навсегда → 534 строки за 7 сессий, 16 исторических секций, full duplication с `progress.md` + `roadmap.md` + `plans/done/`.

**Lesson:** declarative intent ("ротируется", "lifecycle: пока активен") в spec'е — это **не контракт**. Контракт = код. Если в spec написано "lifecycle X" — значит в plan'е этого фейзы должен быть deliverable: скрипт + hook/команда, который физически enforces lifecycle. Иначе degradation гарантирована.

**Antidote pattern:**
1. Любой "rotating"/"capped"/"ephemeral" артефакт — заводи companion `mb-X-prune.sh` script в той же Sprint.
2. Wire в общий `/mb done` (как PreCompact hook был wired в session-end-autosave).
3. Add hard-cap test (pytest) который fails если файл превысил cap.
4. Не доверяй ручной discipline — тестировщик артефакт-роста =  CI, не человек.

См. I-033 в backlog для конкретной реализации. **Status: SHIPPED 2026-04-25** — `scripts/mb-checklist-prune.sh` + 12 tests + cap-test + wire-ins в `/mb done`, `mb-plan-done.sh`, `mb-compact.sh`. Pattern теперь применим к любому будущему "rotating" артефакту в spec.

### Dogfooding = validation (2026-04-19 / audit)

Skill без собственного `.memory-bank/` в репозитории — явный сигнал нежизнеспособности. Первым делом — init в own repo. Если skill неудобен для самого автора, он неудобен для пользователей.

### Orphan agents leak from templates (2026-04-19 / audit)

При копировании agent'ов из другого плагина (GSD) важно проверить frontmatter (`name:`), output paths и integration points. Orphan `codebase-mapper` с `name: gsd-codebase-mapper` и записью в `.planning/` — классический artifact copy-paste без адаптации.

### Language hardcode in "universal" tools (2026-04-19 / audit)

Инструмент, позиционируемый как language-agnostic, но захардкоженный на `pytest`/`ruff`/`src/taskloom/` — ложное позиционирование. Либо честно ограничиться Python, либо реально детектировать стек (pyproject/go.mod/Cargo.toml/package.json).

### Optional dependency checks must validate the whole feature contract (2026-04-20 / verification)

Для optional integrations недостаточно проверить только top-level модуль (`tree_sitter`). Если feature требует полный набор bindings/parsers, guard должен валидировать именно этот полный набор. Иначе тесты становятся environment-sensitive: один Python environment падает, другой проходит, хотя бизнес-логика не менялась.

### Homebrew 5 smoke надо проверять через tap, а не local formula path (2026-04-20 / release)

Начиная с Homebrew 5 local `brew install --formula ./path/to/formula.rb` больше не даёт репрезентативный user-path smoke для tap-distributed пакета. Для release-проверки нужно тестировать реальный сценарий `brew tap <org>/tap && brew install <org>/tap/<formula>`, а local path использовать только как dev artifact.

### Stage 7 (`mb-session-recoverer`) deferred to v3.3+ (2026-04-21 / agents-quality)

Plan `agents-quality` marked Stage 7 OPTIONAL behind `MB_ENABLE_RECOVERER=1`. Decision: defer until telemetry or direct feedback shows `/catchup` is insufficient for MBs > 100 notes. Current MB (this repo) has ~15 notes — no pain signal to justify adding another subagent prompt + feature flag. Revisit when: (a) `.memory-bank/notes/` exceeds 100 entries AND (b) users report `/catchup` dumping more than they can read in 30s. Until then the 17-line `commands/catchup.md` dispatcher is the right-sized solution.

### Basename-matching heuristic needs content fallback (2026-04-21 / agents-quality verify)

`mb-rules-check.sh` `tdd/delta` check initially matched tests by stem only (`test_<stem>_*.bats`). On this repo, 4 scripts (`mb-drift.sh`, `mb-plan.sh`, `mb-rules-check.sh`, `mb-test-run.sh`) have tests named by the wrapping agent/feature (`test_doctor_*`, `test_plan_verifier_*`, `test_rules_enforcer_*`, `test_test_runner_*`) — all emitted false-positive CRITICALs even though coverage existed. Fix: two-pass matcher — Pass 1 basename variants + mb-prefix strip, Pass 2 grep the test file content for the source basename. Lesson: when tests are allowed to target conceptual features rather than physical scripts, pure basename matching is brittle; a content-grep fallback is cheap (O(diff_files) file reads) and catches the common cross-layer pattern.

### Test isolation — shared filesystem state outside `$HOME` (2026-04-26 / Stage 4)

Audit-time pytest run flaked 626/628 on `test_cli_install_uninstall_smoke_with_cursor_global` + `test_uninstall_non_interactive_flag_works_without_stdin`. Both tests sandbox `$HOME` correctly via `subprocess.run(env={"HOME": str(tmp_path/"home"), ...})`. So why the flake?

Root cause: **the artifact path was bound to the source dir, not `$HOME`.** `install.sh:17` reads `MANIFEST="$SOURCE_SKILL_DIR/.installed-manifest.json"`. Every install-related test in `test_cli.py` overwrites `REPO_ROOT/.installed-manifest.json` — regardless of `$HOME` sandbox. Only one test (`test_install_manifest_has_schema_version_and_stable_file_order`) had a try/finally to back up + restore. Tests running before it in arbitrary order would leak state into the manifest, the protected test would snapshot the leaked state, and a subsequent test reading "stable" manifest contracts would fail.

**Fix:** module-level autouse fixture `_protect_repo_install_manifest` in `test_cli.py` — backs up `REPO_ROOT/.installed-manifest.json` bytes before each test, restores after. After the fix: 3 consecutive full pytest runs → 648/648 × 0 flake.

**Pattern:** when sandboxing for tests, **`$HOME` isolation is necessary but not sufficient.** Audit every artifact path that the system-under-test writes to: hard-coded paths bound to source-dir / repo-root / `/tmp/known-name` are all shared-state hazards even with `$HOME` swapped. Either (a) parameterize the path via env var (`MB_INSTALL_MANIFEST_PATH`-style), (b) wrap all callers in autouse save/restore, or (c) make the path derive from `$HOME` so sandboxing alone protects it. We chose (b) here because (a) requires modifying production code with an env override solely for tests (YAGNI for a single artifact).