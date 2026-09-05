---
type: fix
topic: mb-work-cost-diet-sprint2
phase: mb-work-cost-diet
sprint: 2
status: planned
depends_on: [2026-09-05_fix_mb-work-cost-diet-sprint1.md]
parallel_safe: false
linked_specs: []
created: 2026-09-05
---
# Plan: fix — mb-work-cost-diet · Sprint 2 «work-loop-diet»

**Baseline commit:** 364164a928a8691d5582c228747c3e528c047726 (переснять при старте спринта)

## Context

**Problem:** один item `/mb work` стоит 2–2.5 часа и 10–12 сабагентов, потому что (1) implementer получает 4 KB промпта и 200+ ходов сам исследует репо (в среднем 243 хода, 87 Bash, 300 KB tool-вывода, пик контекста 260k); (2) тесты гоняются ~35 раз на item (implementer 15.6 + verifier 12.6 + reviewer 6.5), кэш улик `mb-review-cache.sh` используется только для review-payload; (3) нет триажа по размеру — `mb-work-adapt.sh` упомянут в `commands/work.md`, но файла нет, и мелкая правка идёт через ту же 28-шаговую церемонию; (4) внешнее ревью (codex/pi) ждут sleep-циклами по 5–10 мин и сабагентами-«бебиситтерами» (verifier в среднем 6.7 мин в `sleep`). Цифры — [reports/2026-09-05_mb-work-cost-audit.md](../reports/2026-09-05_mb-work-cost-audit.md), baseline — `reports/2026-09-05_cost-baseline.json` (Sprint 1 Stage 1).

**Expected result:** S-задача через `/mb work --fast` закрывается ≤ 2 диспатчами, ≤ 80 tool-вызовов у implementer, ≤ 2 полных прогонов тестов и ≤ 30 мин; governed-item — ≤ 2 полных прогона на цикл; внешнее ревью — синхронный раннер с таймаутом и heartbeat, без polling-циклов в оркестраторе. Всё измеряется `mb-cost-report.py`.

**Related files:**
- `commands/work.md` (§5a–5d), `scripts/mb-work-plan.sh` (JSON Lines), `scripts/mb-workflow.sh`, `scripts/mb-pipeline-validate.sh`, `references/pipeline.default.yaml`
- `scripts/mb-test-run.sh` (`--out json`, `tests_pass`), `scripts/mb-review-cache.sh` (`sha|check|write`, TTL 600 s), `scripts/mb-review.sh` (`## Prior evidence`)
- `agents/plan-verifier.md` Step 3.5, `agents/mb-judge.md` § Inputs, `agents/mb-engineering-core.md` §7
- `scripts/mb-estimate-lib.sh` (`mb_estimate_lib_context/spec`), `hooks/mb-context-slim-pre-agent.sh` + `scripts/mb-context-slim.py` (advisory-прототип `--slim`)
- `scripts/mb-subinvoke-resolve.sh` (шаблоны `codex exec` / `pi -p …`), `scripts/mb-work-codex-preflight.sh`, `scripts/mb-fanout.sh`
- `scripts/mb-graph-query.py` (`neighbors|tests|impact`, fail-open при stale — см. план graph-semantic-adoption)
- Memory-ноты пользователя с гочами pi/codex: `~/.claude/projects/-Users-anton-one-Apps-harness/memory/pi-gpt56-headless-reviews.md`, `…jeeves-go/memory/pi-gpt56sol-hangs.md` (stdin EOF, `run_in_background` kill)

Связь с планом `cost-multi-model` (roadmap Next): триаж даёт `model_hint`, `cost-multi-model` — provider-routing; не дублировать, `model_hint` — единственная точка выбора модели по размеру.

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: `mb-work-evidence.sh` — одна тест-улика на item

**Role:** developer

**What to do:**
- Новый `scripts/mb-work-evidence.sh run|get|clear --run-id <id> [--files <csv>] [--refresh] --mb <bank>`: `run` = sha touched-файлов (`mb-review-cache.sh sha`) → `check` (HIT → печать пути кэша `<bank>/tmp/last-tests.json`, exit 0) → MISS → `mb-test-run.sh --dir . --out json` → `write --sha … --run-id …` → печать пути; `get` только читает (exit 1 = нет улики); `--refresh` = `clear` + `run`. TTL берётся из `pipeline.yaml:test_cache_ttl_sec` как у review.
- `commands/work.md`: §5a — implementer гоняет **фокусные** тесты своих файлов, полную батарею — один раз в конце через `mb-work-evidence.sh run`; §5c — verify начинается с `mb-work-evidence.sh get` и передаёт verifier строку `Evidence: <path> (sha <…>)`; §5d/§5e — тот же путь в review-payload (`--rules-check-json` уже есть; добавить `--evidence <path>` в `mb-review.sh`, который сегодня резолвит кэш сам) и в промпт судьи.
- `agents/plan-verifier.md` Step 3.5: «если передан `Evidence:` с совпадающим sha — использовать, **не** перегонять батарею; перегон только при MISS/расхождении»; `agents/mb-judge.md` § Inputs — то же; `agents/mb-engineering-core.md` §7 — «полная батарея один раз, через `mb-work-evidence.sh run`».

**Testing (TDD):**
- `tests/bats/test_work_evidence.bats` (фейковый `mb-test-run.sh` через `MB_TEST_COMMAND`, считающий вызовы в файл):
  - `first run executes suite once and writes cache`
  - `second run with same files is HIT and does not execute suite`
  - `changed file content → MISS → suite re-executed`
  - `--refresh forces re-run`
  - `get without cache exits 1 with reason`
  - `malformed cache json → MISS (fail-safe), not crash`
  - `ttl expired → MISS`
- pytest-doc: `tests/pytest/test_work_evidence_docs.py` — `plan-verifier.md`, `mb-judge.md`, `mb-engineering-core.md`, `commands/work.md` содержат `mb-work-evidence.sh` и фразу про повторный прогон только при MISS.

**DoD:**
- [ ] 7/7 bats + doc-pytest зелёные; shellcheck чист; строка в `SKILL.md` § Tools.
- [ ] Демонстрационный item (Sprint 2 Gate) по `mb-cost-report.py`: полных прогонов батареи ≤ 2 (implementer финальный + verify при MISS) против baseline ~35.
- [ ] `mb-review.sh --emit-payload … --evidence <path>` печатает `## Prior evidence` из переданного файла (bats-кейс в существующем `test_mb_review_cache.bats` или новом).

**Code rules:** DRY — никакого второго кэша, только композиция `mb-review-cache.sh` + `mb-test-run.sh`; fail-safe = MISS.

---

<!-- mb-stage:2 -->
### Stage 2: Size-triage `mb-work-adapt.sh` + `--fast`

**Role:** developer

**What to do:**
- Новый `scripts/mb-work-adapt.sh --item-json <line> [--body-file <f>] [--mb <bank>] [--json]`: класс размера по детерминированным признакам — `Files:` ≤ 2 и тело ≤ 1 500 симв. и DoD ≤ 4 пунктов → `S`; `Files:` ≤ 6 → `M`; иначе или `**Layer:** contract` / слова `security|migration|auth|payment` в теле / `Files:` отсутствует → `L`. Выход: `{"size":"S|M|L","workflow":"<из size_map>","model_hint":"sonnet|opus","reason":"…"}`. Логика в `scripts/mb-work-adapt-lib.sh` (source-able), CLI тонкий.
- `pipeline.yaml` (schema): `workflow.auto_size: false` (opt-in) и `workflow.size_map: {S: implement-only, M: execution, L: <workflow.default>}`; `mb-pipeline-validate.sh` знает ключи; `references/pipeline.default.yaml` документирует.
- `scripts/mb-work-plan.sh`: в каждую JSON-строку добавляется `size` и `model_hint` (вызов lib; при ошибке — `size:"?"`, никакого падения).
- `scripts/mb-workflow.sh`: флаг `--fast` = пресет `implement-only` + `model_hint sonnet` + `fast:true` в JSON (один диспатч, verify инлайн оркестратором по DoD-чекбоксам, без plan-verifier); `--auto-size` (или `workflow.auto_size: true`) = per-item выбор по `size_map`; явный `--workflow` всегда побеждает.
- `commands/work.md` §1/§3/§5: строка про `size` в `## Execution Plan` (`--dry-run` показывает `S/M/L → workflow`), описание `--fast`.

**Testing (TDD):**
- `tests/bats/test_work_adapt.bats`:
  - `two files short body → S`, `six files → M`, `contract layer → L`, `security keyword → L`, `no Files line → L`
  - `size_map from pipeline.yaml applied; default map when key missing`
  - `explicit --workflow beats --auto-size`
  - `--fast yields implement-only + model_hint sonnet + fast:true`
  - `mb-work-plan.sh emits size for every item; malformed body → size "?"`
  - `mb-pipeline-validate.sh accepts auto_size/size_map and rejects unknown size key`
- существующие `test_mb_workflow*.bats`, `test_mb_work_plan*.bats` зелёные (байт-идентичность JSON без новых ключей не требуется — ключи добавляются всегда; обновить их фикстуры).

**DoD:**
- [ ] `bash scripts/mb-work-plan.sh --target <plan> --dry-run --mb .memory-bank` печатает `size` у каждого item; `--fast` в `mb-workflow.sh --json` даёт `implement-only`.
- [ ] 11 bats зелёные + регрессия workflow/plan-сьютов; shellcheck чист; `SKILL.md` § Tools + `commands/work.md` таблица флагов содержат `--fast`/`--auto-size`.
- [ ] `docs/mb-work.md` «Лестница стоимости» (Sprint 1 Stage 2) дополнена строкой `--fast`.

**Code rules:** детерминизм (никакого LLM в триаже), opt-in по умолчанию (`auto_size: false`), KISS — пороги константами в одном месте.

---

<!-- mb-stage:3 -->
### Stage 3: Context pack для implementer (обещанный `--slim`)

**Role:** developer

**What to do:**
- Новый `scripts/mb-work-context-pack.sh --item-json <line> [--max-bytes 8192] [--mb <bank>]` → markdown: заголовок + тело item + DoD; `Files:` с числом строк каждого; для каждого файла до 5 соседей и тесты из графа (`mb-graph-query.py neighbors|tests`, fail-open: нет/stale графа → строка «graph unavailable, use Grep on listed files»); `## Edge Cases` спеки/плана если есть; пути (не содержимое) `RULES.md`/`.memory-bank/RULES.md`; блок «Budget»: `tool calls ≤ <N>` (default 60, `pipeline.yaml:budget.tool_calls_per_item`), «читай только перечисленные файлы и их тесты, полная батарея — один раз через `mb-work-evidence.sh run`, при нехватке контекста верни NEEDS_CONTEXT с конкретным вопросом». Превышение `--max-bytes` → усечение тела item с маркером, DoD и Budget не усекаются.
- `commands/work.md` §5a: промпт = engineering-core + tooling-core + role + **context pack** (вместо голого тела); для `fast:true` / `size:S` — engineering-core заменяется 12-строчным дайджестом внутри pack (`## Discipline (digest)`), чтобы промпт S-задачи был ≤ 12 KB.
- `hooks/mb-context-slim-pre-agent.sh`: advisory-режим удалить (мёртвый код), заменить на проверку «в промпте Task есть `## Budget`, иначе WARN в stderr» — fail-open.

**Testing (TDD):**
- `tests/bats/test_work_context_pack.bats`:
  - `pack contains heading, body, DoD, Files with line counts`
  - `graph present → neighbors/tests listed; graph absent → fallback line, exit 0`
  - `over --max-bytes → body truncated with marker, DoD and Budget intact`
  - `budget N read from pipeline.yaml, default 60`
  - `spec task (kind=task) and plan stage (kind=stage) both supported`
  - `edge-cases section included when present`
  - `S-size pack ≤ 12288 bytes including discipline digest`
- `tests/pytest/test_hook_context_slim.py` переписать под новый контракт хука (2–3 теста).

**DoD:**
- [ ] На демонстрационном item implementer по `mb-cost-report.py` ≤ 80 tool-вызовов и ≤ 120 ходов (baseline 87/243); промпт S-задачи ≤ 12 KB.
- [ ] 7 bats + pytest хука зелёные; shellcheck; строка в `SKILL.md`; `commands/work.md` §5a обновлён (doc-pytest: содержит `mb-work-context-pack.sh` и `## Budget`).
- [ ] `references/work-reference.md` — раздел «Context pack» (≤ 30 строк), «Phase 4 will add `--slim`» удалено из `commands/work.md`.

**Code rules:** fail-open на граф; SRP — сборка pack отдельно от диспатча; YAGNI — без семантического поиска в pack (только граф).

---

<!-- mb-stage:4 -->
### Stage 4: `mb-review-external.sh` — внешнее ревью без polling

**Role:** developer

**What to do:**
- Новый `scripts/mb-review-external.sh --payload <file> --out <file> [--agent codex|pi] [--model M] [--thinking T] [--timeout 900] [--heartbeat 30] [--mb <bank>]`: шаблон команды из `mb-subinvoke-resolve.sh --agent …` (с подстановкой model/thinking в `$MB_SUBINVOKE_MODEL`/новую `$MB_SUBINVOKE_THINKING`), запуск **синхронно** в собственной process-group, `stdin </dev/null` (гоча pi), вывод в `--out`, heartbeat-строка в stderr каждые N секунд (`[review-external] alive 90s, out 0 B`), по таймауту — kill process-group, exit 124; exit 0 = файл непустой, 1 = транспорт упал/пустой вывод. Использует `mb-work-codex-preflight.sh` перед запуском (exit 3 = недоступен, без запуска).
- `commands/work.md` §5d: внешний reviewer запускается **только** этим раннером: `Bash(run_in_background=true)` → ждать task-notification → `mb-work-review-parse.sh --external <out>`; явный запрет `sleep`-циклов, `nohup … & disown` и сабагентов-«бебиситтеров»; `docs/mb-work.md` — абзац «Внешнее ревью».
- `agents/mb-reviewer.md` (codex-ветка) — ссылка на раннер вместо ручного `codex exec`.

**Testing (TDD):**
- `tests/bats/test_review_external.bats` с фейковыми `codex`/`pi` в `PATH` (`tests/fixtures/bin/`):
  - `success: output file written, exit 0`
  - `empty output → exit 1 with reason`
  - `timeout kills the whole process group (child sleep dies), exit 124`
  - `stdin is /dev/null (fake pi hangs on open stdin → must not hang)`
  - `heartbeat lines appear at configured interval`
  - `preflight unavailable → exit 3, transport not invoked`
  - `model/thinking propagated into the resolved template`
- doc-pytest: `commands/work.md` содержит `mb-review-external.sh` и не содержит `sleep 30` в §5d.

**DoD:**
- [ ] 7/7 bats зелёные на macOS (bash 3.2) и Linux CI; shellcheck чист; `SKILL.md` § Tools.
- [ ] На демонстрационном governed-item по `mb-cost-report.py`: 0 Bash-вызовов оркестратора с `sleep` и 0 сабагентов с ролью babysitter; время ожидания ревью = длительность одного background-вызова.
- [ ] `commands/work.md` §5d, `docs/mb-work.md`, `agents/mb-reviewer.md` обновлены (doc-pytest).

**Code rules:** портируемый таймаут без `timeout`/`gtimeout` (стоковый macOS — прецедент I-138): watchdog-подпроцесс + `kill -- -$PGID`; fail-loud на ошибках транспорта.

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Кэш улик даст ложный зелёный (тесты меняли не touched-файлы) | M | sha считается по `Files:` ∩ изменённым с baseline **плюс** всем изменённым тест-файлам; `--refresh` в verify при любом сомнении; TTL |
| Триаж занизит размер (S для рискованной правки) | M | Ключевые слова риска → L; `auto_size` opt-in; `--dry-run` показывает класс до запуска; судья/verify не отключаются для M/L |
| Context pack без графа деградирует в «читай сам» | H (граф stale в 3/4 банков) | Fail-open с явной строкой; план graph-semantic-adoption (Stage 3 auto-catchup) закрывает свежесть; pack всё равно даёт `Files:` + тесты по имени |
| Раннер убьёт «живой» долгий codex по таймауту | M | Default 900 s (замер: 8–12 мин при xhigh), `--timeout` в `pipeline.yaml:roles.reviewer.timeout_sec`; heartbeat показывает, что процесс жив |
| Правки в `commands/work.md` расходятся с тестами-контрактами доков | M | Каждая стадия несёт doc-pytest; `mb-drift.sh` в DoD |

## Gate (plan success criterion)

Демонстрационный прогон двух реальных backlog-задач через обновлённый движок, измеренный `mb-cost-report.py` и приложенный к `reports/`: (1) S-задача (например I-023 `grep → find` cleanup) через `/mb work --fast` — ≤ 2 диспатча, implementer ≤ 80 tool-вызовов, ≤ 2 полных прогона тестов, ≤ 30 мин, DoD-чекбоксы флипнуты через `mb-work-checkbox.sh`; (2) M-задача через `execution` — ≤ 3 диспатча, ≤ 2 полных прогона на item. Полная батарея зелёная, `/mb verify` PASS.
