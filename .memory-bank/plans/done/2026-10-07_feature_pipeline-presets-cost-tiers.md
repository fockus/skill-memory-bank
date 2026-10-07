---
type: feature
topic: pipeline-presets-cost-tiers
status: done
depends_on: ["2026-10-07_fix_proportional-effortsprint2-execution-economy.md"]
parallel_safe: false
linked_specs: []
created: 2026-10-07
---
# Plan: feature — pipeline-presets-cost-tiers · уровни сложности, тиры стоимости, шаблоны для код-агентов, частота верификатора

**Baseline commit:** e351a17b8f114bb985dcc2efbdd5709c731736e6

## Context

**Problem (2026-10-07).**
- Верификатор (`plan-verifier`) запускается на каждый пункт `/mb work`, его частоту нельзя настроить.
- Пресеты workflow (`execution`, `codex-governed`, `governed-execution`, …) не выстроены по сложности.
- Модели задаются только как `roles.<role>.model`. Нет переключателя «дорого / оптимально / дёшево» и нет готовых наборов моделей для разных код-агентов.

Решения владельца:
- AGR-074 — три оси: уровень сложности × тир стоимости × код-агент, с шаблонами для Claude Code, Codex, Pi, OpenCode и Cursor;
- AGR-075 — частота верификатора `stage | plan | run | off`, по умолчанию `plan`;
- AGR-067 — уровни задачи;
- AGR-073 — параллельная работа.

**Expected result.**
1. **Уровни сложности** — workflow в `pipeline.default.yaml`:
   - `simple` = `[implement, done]`: исполнитель сам проверяет себя целевыми тестами и DoD, отдельного верификатора нет;
   - `medium` = `[implement, verify, done]`, verify с частотой `plan`;
   - `complex` = `[implement, verify, review, fix, done]`: один ревьюер, ограниченный fix-цикл;
   - `governed` = текущий `governed-execution`: verify, ансамбль ревью, судья, fix-циклы.

   Старые имена работают как алиасы. Уточнение: `execution` → `medium` меняет частоту verify с «каждый пункт» на «конец плана», это осознанное изменение по AGR-075, его нужно записать в CHANGELOG. Имя `full` уже занято полным циклом с discuss/sdd и сохраняется.
2. **Частота верификатора:** `workflows.<name>.verify.cadence: stage | plan | run | off` и флаг `/mb work --verify=…`. Значения:
   - `stage` — после каждого stage плана или task спеки;
   - `plan` — один раз после последнего пункта плана или спеки;
   - `run` — один раз в конце запуска, даже если он прошёл по нескольким планам;
   - `off` — без верификатора; `/mb verify` вручную остаётся доступен.
3. **Тиры стоимости:** `model_profiles.<host>.<tier>.<role-class>`. Классы ролей:
   - `implementer` — developer, backend, frontend, ios, android, devops, qa, debugger, analyst;
   - `planner` — architect, planner;
   - `researcher`;
   - `verifier`;
   - `reviewer` — reviewer и все `reviewer_*`;
   - `judge`.

   Состав тиров:
   - `premium` — дорогая модель на всех ролях;
   - `optimal` — «дешёвые руки, дорогие глаза»: implementer, verifier и researcher на средней модели, reviewer, judge и planner на дорогой;
   - `economy` — средняя модель на всех ролях, без самых дешёвых.

   По умолчанию `cost: optimal`, флаг `/mb work --cost=premium|optimal|economy`.
4. **Код-агенты:** шаблоны `model_profiles` для `claude-code`, `codex`, `pi`, `opencode`, `cursor`. Хост определяется при запуске, при этом можно задать отдельно для хоста: `hosts.<host>.cost`, `hosts.<host>.preset`, `hosts.<host>.verify`. Порядок разрешения модели для роли:
   1. флаг CLI;
   2. явный `roles.<role>.model` в проектном `pipeline.yaml`;
   3. `model_profiles[host][cost][class]`;
   4. `inherit`.

   Проекты, где модели уже заданы явно, как в этом репозитории, ведут себя так же, как раньше.
5. **Привязка к уровням задачи** (`effort_tiers`):
   - trivial и small — без `/mb work`; если пользователь всё же запустил его, используется `simple`;
   - standard → `medium`;
   - large → `discuss → sdd`, затем `complex`;
   - extra → `governed`.

   Карта лежит в `pipeline.yaml`, и проект может её переопределить.
6. **Шаблоны и UX:**
   - `/mb config init --host <h> --preset <p> --cost <c>` пишет проектный `pipeline.yaml` из шаблонов;
   - `/mb config show` печатает итоговую матрицу «роль → агент → модель → discipline» для текущих хоста, пресета, тира и частоты verify.

**Related files:** `references/pipeline.default.yaml`, `scripts/mb-workflow.sh`, `scripts/mb-work-plan.sh`,
`scripts/mb-agent-caps.sh` (уже маппит модель через `dispatch.model_map` — переиспользовать, не дублировать),
`scripts/mb-pipeline-validate.sh` + `scripts/mb_pipeline_validate_blocks.py`, `commands/work.md`,
`commands/config.md`, `references/work-reference.md`, `docs/mb-work.md`, тесты.

**Parallel execution (AGR-073).** Wave 0 — Stage 0, read-only research; можно запускать сейчас. Wave 1 стартует после Sprint 2 Stage 2+3a: тот агент сейчас владеет `pipeline.default.yaml`, `mb-work-plan.sh` и `commands/work.md`. В Wave 1 идут Stage 1 → Stage 2, последовательно, потому что у них общий `mb-workflow.sh`/`mb-work-plan.sh`. Wave 2 — Stage 3 и Stage 4 параллельно: у Stage 3 resolver моделей, у Stage 4 шаблоны хостов и `config init/show`; владельцы файлов разведены. Wave 3 — Stage 5.

---

## Stages

<!-- mb-stage:0 -->
### Stage 0: Исследование моделей и сабагентов у пяти хостов (read-only)

**What to do:**
- Для Claude Code, Codex, Pi, OpenCode и Cursor выяснить по актуальной документации, со ссылками, и по коду адаптеров:
  - как сабагенту задаётся модель;
  - актуальные идентификаторы моделей для уровней «дорогая» и «средняя»;
  - что значит `inherit`.
- Сверить с `dispatch.model_map`, `mb-agent-caps.sh` и AGR-056 (Pi наследует модель оркестратора).
- Отчёт `reports/2026-10-07_host-model-matrix.md`: таблица «хост × тир × класс роли → model id», пробелы и решения для хостов без выбора модели сабагенту.

**DoD:**
- [x] отчёт со ссылками на источники; для каждого хоста указано, поддерживается ли выбор модели сабагенту

---

<!-- mb-stage:1 -->
### Stage 1: Частота верификатора

**What to do:**
- `pipeline.default.yaml`: `workflows.<name>.verify.cadence`, у `medium` — `plan`, у `complex` и `governed` — `plan`. Если в проекте явно задан `stage`, он сохраняется.
- `mb-workflow.sh` и `mb-work-plan.sh` принимают `--verify=stage|plan|run|off` и отдают в JSON каждого пункта `verify: true|false`, а также `final_verify` у последнего пункта плана или спеки. При `run` verify делается в конце запуска (`mb-work-plan.sh --range` по нескольким планам).
- `commands/work.md` § 5c: verify выполняется только у пунктов с `verify: true`. При `plan` и `run` верификатор получает весь diff плана или запуска и гоняет полный набор тестов (Sprint 2 Stage 2). При `off` — запись «verification skipped (cadence=off)» в progress.

**Testing (TDD):**
- bats: план из 3 пунктов при cadence `stage` → 3 пункта с verify; при `plan` → 1, только последний; при `off` → 0; при `run` с двумя планами → 1, в конце.
- Флаг CLI перебивает `pipeline.yaml`.
- `mb-pipeline-validate.sh` отклоняет неизвестное значение cadence.

**DoD:**
- [x] тесты красные до, зелёные после; validate проходит на default и на этом репо

---

<!-- mb-stage:2 -->
### Stage 2: Пресеты сложности + `effort_tiers`

**What to do:**
- Workflows `simple`, `medium`, `complex`, `governed`.
- Алиасы для обратной совместимости: `execution → medium`, `governed-execution → governed`, `implement-only` — остаётся как есть. `workflow.default: medium`.
- В `simple` у шага implement стоит пометка `self_verify: true`: исполнитель получает в промпт требование самопроверки (целевые тесты + DoD) вместо отдельного верификатора.
- `effort_tiers: {small: simple, standard: medium, large: complex, extra: governed}`. Флаг `mb-workflow.sh --tier <name>`. Для trivial — exit 2 с подсказкой «без /mb work».
- Эта стадия забирает часть Stage 1 Sprint 1 proportional-effort про `effort_tiers` и `--tier`. В Sprint 1 остаются справочник `references/effort-tiers.md` и роутинг в `SKILL.md`, которые ссылаются на эти пресеты.
- `commands/work.md`: таблица пресетов (Cost ladder) переписывается как матрица «пресет × тир». Файл уже на
  пределе 400 строк (`test_s2_file_size_contract`) — детали выносятся в `references/work-reference.md`,
  в `work.md` остаётся короткая таблица; `docs/mb-work.md` § Cost ladder (устаревшие `~28`/`~35`) — тоже.

**Testing (TDD):**
- bats: каждый пресет резолвится в свои шаги; алиасы резолвятся в новые имена; `--tier extra` → steps содержат review и judge; `--tier small` → simple с `self_verify`.
- Проектный `pipeline.yaml` этого репо (`codex-governed`) резолвится как раньше.

**DoD:**
- [x] тесты зелёные; CHANGELOG описывает смену дефолта на `medium` и cadence `plan`

---

<!-- mb-stage:3 -->
### Stage 3: Тиры стоимости и разрешение модели по ролям

**What to do:**
- Схема по отчёту Stage 0 (`reports/2026-10-07_host-model-matrix.md`), проще исходной:
  `cost_tiers: {premium: {<class>: premium…}, optimal: {implementer: mid, verifier: mid, researcher: mid, planner: premium,
  reviewer: premium, judge: premium}, economy: {<class>: mid…}}` — одна таблица на все хосты;
  `model_profiles.<host>: {premium: <id>, mid: <id>}` — две модели на хост. `cost` по умолчанию `optimal`;
  `hosts.<host>.{cost,preset,verify}`. Тир меняет только модель; effort остаётся из frontmatter агента.
- Резолвер в `mb-work-plan.sh` (он уже читает `roles.<role>.model` напрямую), порядок разрешения — п. 4 Expected result.
  В JSON каждого пункта: `model`, `model_source` (cli, role, profile или inherit), `cost`, `discipline`.
- `dispatch.model_map` + `mb-agent-caps.sh` — только перевод модели при запуске шага через другой CLI; caps сейчас
  не вызывается из `/mb work` — подключить через `--model <id>` или зафиксировать, что перевод не нужен (без второй таблицы).
- Ограничения хостов: Pi — алиасы `opus/sonnet` превращаются в модель родителя (AGR-056, `adapters/pi_native_roles.mjs`),
  модели — `provider/id` одного провайдера; OpenCode и Cursor — модель задаётся только статически (агент/frontmatter),
  значит тир применяется при `config init`/рендере агентов, а не на каждый вызов; `config show` это показывает.
- `/mb work --cost=…`, `--host=…` (переопределить автоопределение).

**Testing (TDD):**
- pytest/bats: optimal на claude-code — developer/verifier = sonnet, reviewer/judge/planner = opus; premium — opus на всех ролях; economy — sonnet на всех ролях; явный `roles.developer.model` побеждает профиль; флаг `--cost` побеждает `hosts.<host>.cost`; Pi без заданного mid → `inherit` с предупреждением.
- Модель haiku (через override) → `discipline: strict`.

**DoD:**
- [x] тесты зелёные; на этом репо (явные модели) результат `mb-work-plan.sh` совпадает с прежним, кроме новых полей

---

<!-- mb-stage:4 -->
### Stage 4: Шаблоны для пяти хостов + `config init/show`

**What to do:**
- Шаблоны `model_profiles` для claude-code, codex, pi, opencode и cursor по отчёту Stage 0.
- Для pi и opencode, где провайдер любой: при `config init --host` модели выбираются из текущей конфигурации хоста или задаются флагами `--model-premium`/`--model-mid`. Плейсхолдеры в итоговый файл не попадают.
- `/mb config init --host --preset --cost` и `/mb config show`, описание в `commands/config.md`.
- Документация `docs/mb-work.md` и `references/work-reference.md`: матрица «пресет × тир × хост», не больше одного экрана.

**Testing (TDD):**
- bats: `config init` для каждого из 5 хостов в temp-проекте даёт валидный `pipeline.yaml` (validate проходит); `config show` печатает матрицу ролей; повторный init без `--force` не перезаписывает проектные правки.

**DoD:**
- [x] 5 шаблонов валидны; `config show` на этом репо показывает текущие явные модели

---

<!-- mb-stage:6 -->
### Stage 4b: Модель тира в установленных агентах OpenCode / Cursor / Codex

**Files:** `scripts/mb-agent-render.py`, `adapters/opencode.sh`, `adapters/cursor.sh`, `adapters/codex.sh`, `scripts/mb_config_hosts.py`, тесты

**What to do:**
- Рендерер принимает модель роли: значение `mb_work_models.resolve_model` по проектному `pipeline.yaml`, хосту и тиру. Куда она пишется:
  - OpenCode — `model: provider/id` в `.opencode/agents/*.md`;
  - Cursor — `model: <id>` в `~/.cursor/agents/mb-*.md`;
  - Codex — `model` в `.toml`.
- `config init --host opencode|cursor|codex` перерендеривает установленных агентов. Пока этого нет, init и show печатают примечание «модель наследуется».

**Testing (TDD):**
- bats в temp HOME/проекте: после `config init --host cursor --cost premium` у `mb-developer` стоит `model: claude-opus-5-5`;
- без профиля в агенте нет `model`;
- повторный init даёт байт-в-байт тот же результат.

**DoD:**
- [x] тесты зелёные; тесты адаптеров остальных хостов зелёные

---

<!-- mb-stage:5 -->
### Stage 5: Интеграция и замер

**What to do:**
- `/mb work` на фикстурном плане из 3 пунктов, для каждого пресета при `optimal`: число dispatch'ей, прогонов verify и полных прогонов тестов совпадает с матрицей в `work.md`.
- Добавить в отчёт proportional-effort (Sprint 2 Stage 4) колонки «пресет / тир».

**DoD:**
- [x] сценарии зелёные; полный pytest/bats без новых красных относительно baseline
  — `tests/bats/test_proportional_full_suite_once.bats` «preset-matrix: …» 4/4 (8/8 файл): claude-code, optimal, план из 3 пунктов — simple 3 dispatch / 0 verify / 0 full, medium 4/1/1, complex 7/1/1, governed 25/1/1, совпадает с `work.md` § Cost ladder; модели sonnet (implementer, verifier), opus (reviewer, judge). Колонка «Preset / cost tier» — в `reports/2026-10-07_proportional-effort-baseline.md`. Полный прогон 2026-10-07: pytest 3864 passed, 2 failed (оба до этой работы), bats 3662, 0 not ok.

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Смена дефолта `execution` → `medium` с cadence `plan` пропустит ошибку в середине плана | M | полный прогон тестов и верификатор в конце плана; `--verify=stage` доступен одной опцией; CHANGELOG |
| Идентификаторы моделей хостов устаревают | H | шаблоны — в `pipeline.yaml`, переопределяются; `config show` показывает, что реально будет использовано |
| Хост не умеет выбирать модель сабагенту | M | `inherit` + пометка в `config show`; Stage 0 фиксирует такие хосты |
| Конфликт с Sprint 2 по `pipeline.default.yaml` / `mb-work-plan.sh` / `work.md` | M | Wave 1 стартует только после Sprint 2 Stage 2+3a |

## Gate (plan success criterion)

`/mb work --workflow <simple|medium|complex|governed> --cost <premium|optimal|economy> --verify <stage|plan|run|off>` (пресет также через `--tier`) резолвит шаги и модели по ролям для каждого из 5 хостов; дефолт — medium + optimal + verify в конце плана; явные модели проекта не ломаются; все тесты зелёные.
