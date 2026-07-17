# Design: svp-spec-review-loop

> Architecture, interfaces, and decisions backing requirements.md.
> Слайс S9 — тонкий слой поверх S2-C5 (`sdd.spec_review`, `scripts/mb-sdd-review-result.sh`,
> вердикт-JSONL `<bank>/tmp/spec-review/<topic>.jsonl`). Ничего из S2 не переопределяется:
> S9 добавляет судью, петлю, реестр отклонений, промпт-сборщик и work-гейт.
> `review: waived` (AGR-022) — спека не проходила codex-ревью; первый боевой прогон механизма S9
> по этой спеке гасит ревью-долг (dogfooding).

## Architecture

```
/mb sdd <topic>
  … шаги S2 (генерация → батарея C8) …
  (9a) spec_review  — промпт из C4 (сборщик) → ревьюер-модель → вердикт JSONL (S2-C5, kind=review)
  (9b) spec_judge   — C1 конфиг → судья-модель → решение JSONL (kind=judge)   ← S9
        GO                → принятие
        GO_WITH_BACKLOG   → выжившие findings → backlog I-NNN → принятие
        NO_GO             → (9c) fix-проход по findings → назад в (9a), НОВЫЙ независимый review
  цикл ≤ max_cycles → honest stop: spec=not_accepted reason=review_cycles_exhausted topic=<t>

/mb work <topic>
  preflight: C5 spec-гейт (kind=review/judge из JSONL) → blocked | proceed | override(kind=override)
```

Владелец всех JSONL-записей — расширенный `mb-sdd-review-result.sh` (C2); петлю оркеструет
prompt-слой `commands/sdd.md` (C3); LLM нигде не пишет журнал сам.

## Interfaces

### C1. pipeline-схема `sdd.spec_judge`

Рядом с существующей `sdd.spec_review` (S2-C5), **инлайн-мапой** (обязательно: PyYAML-optional
пути `parse_simple_mapping`+`parse_inline_map`; вложенный блок даёт `None`):

```yaml
sdd:
  spec_review: {enabled: false, agent: mb-reviewer, model: <exact>, thinking: medium}   # S2-C5 (+ опц. ключ rubric: <path> — S9)
  spec_judge:  {enabled: false, agent: mb-judge, model: <exact>, thinking: medium, max_cycles: 2}  # S9
```

- Валидация в `scripts/mb-pipeline-validate.sh` рядом с проверками `sdd.*`: `enabled` булев,
  `max_cycles` целое ≥1, `model` непустой при `enabled: true`; неизвестные ключи мапы → ошибка.
- `spec_judge.enabled: true` при `spec_review.enabled: false` → ошибка валидации
  (судье нечего судить), сигнатура `spec_judge_requires_spec_review`.
- Дефолт выключен: без правок pipeline.yaml поведение байт-в-байт прежнее (D-30: судья-человек).

### C2. Расширение `scripts/mb-sdd-review-result.sh` (владелец журнала)

Существующие подкоманды S2 (`check`, `record` kind=review) не меняются. Добавляется:

- `record --kind judge --decision GO|GO_WITH_BACKLOG|NO_GO [--items I-NNN,…] [--mb PATH] <topic>` —
  строгая валидация, append одной компактной строки `{ts, attempt, kind:"judge", decision, items?}`;
  exit 0 GO / 1 NO_GO|GO_WITH_BACKLOG-без-items-при-выживших / 2 malformed.
- `record --kind override [--mb PATH] <topic>` — строка `{ts, kind:"override"}`; exit 0.
- `check --judge <topic>` — тройная same_model-проверка ДО диспатча: judge-модель ≠ review-модель
  И judge-модель ≠ модель-генератор спеки (из frontmatter `generated_by`, при отсутствии ключа —
  проверка пропускается с предупреждением `generator_model_unknown` на stderr, не ошибкой);
  нарушение → stderr `same_model`, exit 2 (сигнатура и код идентичны S2-C5).
- `status [--mb PATH] <topic>` — печатает ровно одну строку
  `spec_review=<APPROVED|CHANGES_REQUESTED|SKIPPED|none> judge=<GO|GO_WITH_BACKLOG|NO_GO|none> override=<yes|no>`
  по последним валидным строкам каждого kind; журнала нет → все поля `none`/`no`, exit 0.
  Это единственный вход work-гейта C5 — гейт не парсит JSONL сам.

Журнал остаётся append-only: строки никогда не редактируются и не удаляются; «действующее
состояние» = последняя валидная строка каждого kind (правило S2-C5 сохраняется).

### C3. Петля в `commands/sdd.md` (шаг 9 конвейера S2)

Шаг 9 расширяется до 9a/9b/9c (клаузы промпта; порядок канонический, не меняется):

- 9a: собрать промпт ревью ЧЕРЕЗ C4 (не вручную), диспатч ревьюера, `record` вердикта (S2-C5).
- 9b: при `spec_judge.enabled` — `check --judge`, затем диспатч судьи с: последний вердикт,
  spec triple, реестр отклонений (если есть), рубрика; `record --kind judge`.
  Судья, а не ревьюер, решает остановку. GO_WITH_BACKLOG: каждый выживший finding →
  `mb-idea.sh` (I-NNN) до принятия, id передаются в `record --items`.
- 9c: при NO_GO — fix-проход по findings текущего вердикта (исполнитель — оркестратор или
  фиксер-агент), затем возврат в 9a как НОВЫЙ независимый review (следующий `attempt`);
  отклонённые с доказательством находки — в реестр C6 до re-review.
- Счётчик циклов — по числу kind=judge строк текущей сессии sdd; после `max_cycles` NO_GO —
  стоп с наблюдаемой строкой `spec=not_accepted reason=review_cycles_exhausted topic=<t>`
  на stdout; спека остаётся непринятой, решение у пользователя.

### C4. Промпт-сборщик `scripts/mb-sdd-review-prompt.sh`

`mb-sdd-review-prompt.sh [--mb PATH] <topic>` → полный промпт ревью на stdout:

1. рубрика: `sdd.spec_review.rubric` из pipeline (файл обязан существовать, иначе stderr
   `rubric_not_found path=<p>`, exit 2) | дефолт `references/spec-review-rubric.md`;
2. блок «Принятые отклонения» из `specs/<topic>/review-deviations.md` — только если файл
   непуст; с инструкцией «не поднимай заново, если текст спеки согласуется с обоснованием»;
3. список файлов спеки (requirements/design/tasks + `context/<topic>.md` при наличии);
4. схема вердикта (JSON, совместимая с writer'ом S2-C5).

Детерминирован: одинаковые входы → байт-идентичный stdout; exit 0 | 2 usage/rubric_not_found.

### C5. Work-гейт `scripts/mb-work-spec-gate.sh` + врезка `commands/work.md`

`mb-work-spec-gate.sh [--mb PATH] [--skip-spec-gate] <topic>`:

- `sdd.spec_review.enabled` ≠ true ИЛИ `status` дал `spec_review=none` → stdout пусто, exit 0
  (гейт молчит — обратная совместимость, REQ-011).
- Действующее `spec_review=CHANGES_REQUESTED` и `judge` ∉ {GO, GO_WITH_BACKLOG} и
  `--skip-spec-gate` не передан → stdout `work=blocked reason=spec_review_pending topic=<t>`,
  exit 3.
- `--skip-spec-gate` в блокирующем состоянии → `record --kind override` через C2, stdout
  `work=proceed reason=override topic=<t>`, exit 0.
- Иначе → exit 0, stdout пусто.

Врезка в `commands/work.md`: вызов гейта сразу после резолва spec-target'а, ДО первого
диспатча work-item. Plan-target'ы без linked_spec гейт не трогает.

### C6. Реестр отклонений `specs/<topic>/review-deviations.md`

Markdown-таблица, append-only (строки не редактируются; изменение решения = новая строка):

```markdown
# Review deviations: <topic>

| id | source | decision | evidence | date |
|---|---|---|---|---|
| R3-004 | round3/codex | rejected: TTL легален для stale-claims | umbrella REQ-023: «release stale claims by TTL» | 2026-07-17 |
```

Пишет оркестратор (правило «банк пишет только оркестратор»); потребитель — промпт-сборщик C4
(инъекция as-is, машинного парсинга нет — KISS). Файл опционален: нет файла = нет блока.

## Decisions

- **ADR-S9-1. Судья терминирует цикл.** Context: в governed-ревью кода ревьюер без судьи
  бесконечно улучшает. Decision: решение об остановке принимает ТОЛЬКО судья (GO/GO_WITH_BACKLOG/NO_GO);
  ревьюер даёт вердикт, не решение. Consequences: NO_GO всегда ведёт в fix+re-review или honest stop.
- **ADR-S9-2. Независимый re-review после фикса.** Context: урок «lead self-review пропускает
  свои же дыры». Decision: после fix-прохода — полный новый review (новый attempt), не
  инкрементальная проверка фиксов. Consequences: дороже на цикл, честнее по качеству.
- **ADR-S9-3. Промпт собирает скрипт, не LLM.** Context: инъекция реестра «инструкцией» непроверяема.
  Decision: C4 — детерминированный сборщик, тестируемый bats'ом. Consequences: любое изменение
  состава промпта — правка скрипта с тестом.
- **ADR-S9-4. Гейт читает `status`, не JSONL.** Context: два парсера одного журнала разъедутся.
  Decision: единственный читатель/писатель журнала — C2; гейт потребляет его однострочный `status`.
- **ADR-S9-5. Спека без ревью (AGR-022).** Context: явное решение пользователя «не будем проверять».
  Decision: `review: waived` во frontmatter; ревью-долг гасится dogfooding-прогоном S9 по самой себе.
  Consequences: риск дефектов спеки выше обычного — компенсируется тем, что реализация S9 сама
  создаёт инструмент их обнаружения.

## Risks & mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Спека не ревьюилась (AGR-022) — дефекты доедут до реализации | M | M | dogfooding: первый прогон S9 — по этой же спеке; находки → deviations/backlog штатным механизмом |
| Судья-модель недоступна в среде | L | M | паттерн codex-reviewer: health-check + SKIPPED loudly отдельной строкой журнала; решение у человека (D-30 fallback) |
| Рассинхрон с S2-C5 при его правках (S2 сейчас в ремедиации) | M | M | S9 не дублирует C5-текст, только ссылается; выравнивание при umbrella-интеграции после ремедиации (D-08) |
| Петля жжёт токены на слабой спеке | M | L | `max_cycles` (дефолт 2) + honest stop; GO_WITH_BACKLOG как дешёвый выход для minor-хвоста |
| Два писателя журнала (гонка sdd-сессий) | L | M | append-only + правило S2-C5 «последняя валидная строка»; журнал per-topic |
