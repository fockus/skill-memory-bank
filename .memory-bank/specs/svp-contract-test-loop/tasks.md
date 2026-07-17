# Tasks: svp-contract-test-loop

> Слайс S8 (ICE 360, blocked by svp-sdd-core). Eval первым (red) → реализация (green).
> Роли — bare (парсер сам добавляет префикс `mb-`: `scripts/mb_work_items.py:240`).
> Ревизия 2 (2026-07-17): Eval-строки приведены к грамматике S2-C1 (`red:` + `exit:` + `output~:`),
> DAG и Scope сериализованы по общим файлам, `commands/verify.md` заменён на реальные швы.
> Ревизия 3 (2026-07-18, круг 3): T2 — спека без блока = легаси (`source=legacy`), sibling-скан
> `noncanonical_owner`, anchor → `test_missing_block_is_legacy` (R3-001/R2-004); T3 — легаси-короткое
> замыкание + матрица слоёв (e2e без integration) + JSON-реестр (R3-001/R3-003/R3-002); T4 — два
> фрагмента `{tasks_markdown, quality_dod_markdown}` (R2-010); T5 — JSON/argv реестр, двухфазный
> диспатч A/B + resume, закрытая схема evidence + red-evidence gate (R3-002/R2-001/CPR-A); T6 — рубрика
> в блоке + `mb-rules-check` evidence в Prior evidence (R2-012).
> Порядок по `Blocked-by`: {1, 2} → 3 → 4 → 5 → 6 → 7 (интеграционные) → 8 (e2e).

<!-- mb-task:1 -->
## Task 1: Резолвер правил

**Stage:** 1
**Covers:** REQ-016, REQ-017
**Role:** backend
**Blocked-by:** none
**Scope:** scripts/mb-rules-resolve.sh, tests/bats/test_mb_rules_resolve.bats
**Budget:** 80000

**What to do:**
- Новый `scripts/mb-rules-resolve.sh` по контракту C2, два режима:
  - **discovery** (без `--spec`/`--declared-source`): собрать все проектные источники
    (`<repo>/AGENTS.md`, `<repo>/RULES.md`, `<bank>/RULES.md`, активный профиль через
    `bash scripts/mb-profile.sh path`), fallback на `rules/RULES.md`;
  - **validation** (`--spec SPEC_DIR` и/или повторяемый `--declared-source PATH`): читать
    объявленные записи `- [<kind>] <path>` из секции `## Quality DoD` файла `<spec-dir>/design.md`;
    каждый объявленный путь обязан существовать, иначе stdout пуст, stderr
    `rule_source_missing=<path>`, exit 1, fallback запрещён.
- stdout JSON с `sources` (отсортирован по `path`), `fallback_used`, `checker`; exit 0/1/2
  (2 — usage/malformed секция). Bash 3.2-совместимо (NFR-004).

**Eval:** `bats tests/bats/test_mb_rules_resolve.bats` — red: `mb-rules-resolve.sh` не реализован, проектный источник не побеждает fallback; exit: 1; output~: not ok [0-9]+ rules_resolve_project_source_wins

**Testing (TDD — tests BEFORE implementation):**
- bats: `rules_resolve_project_source_wins` — проектный источник побеждает fallback;
  `rules_resolve_missing_declared_source_exits_1` — объявленный, но отсутствующий источник → exit 1 с путём в stderr и пустым stdout;
  `rules_resolve_fallback_only_without_project` — fallback только при отсутствии проектных;
  `rules_resolve_malformed_quality_dod_exits_2` — malformed секция → exit 2;
  `rules_resolve_json_is_stable` — два прогона дают байт-идентичный JSON; shellcheck clean.

**DoD:**
- [ ] C2 (оба режима) реализован; bats green (были red); shellcheck clean
- [ ] `bash scripts/mb-rules-check.sh --files <изменённые> --out json` — clean
<!-- /mb-task:1 -->

<!-- mb-task:2 -->
## Task 2: Парс блока `layers` + дефолты в конфиге

**Stage:** 1
**Covers:** REQ-012, REQ-013
**Role:** backend
**Blocked-by:** none
**Scope:** memory_bank_skill/spec_layers.py, references/pipeline.default.yaml, scripts/mb-pipeline-validate.sh, tests/pytest/test_spec_layers.py, tests/bats/test_mb_pipeline_sdd_layers.bats
**Budget:** 100000

**What to do:**
- Новый модуль `memory_bank_skill/spec_layers.py` по контракту C1:
  `read_spec_layers(requirements_path, pipeline_path) -> SpecLayers`
  (`source ∈ {spec, pipeline, legacy}`) + CLI
  `python3 -m memory_bank_skill.spec_layers --requirements PATH --pipeline PATH --json`.
  Канонический владелец блока — frontmatter `requirements.md`; **отсутствие блока → легаси**: все три
  `false`, `source="legacy"`, файл не мутируется (R3-001); при наличии блока дефолты недостающих ключей
  из `pipeline.yaml:sdd.layers`, явное значение спеки побеждает; `false` (в явном блоке) без
  `<layer>_reason` → `SpecLayersError(missing_reason, <layer>)`, exit 1.
- **Sibling-скан канонического владельца (R2-004)**: `read_spec_layers` инспектирует
  `requirements_path.parent / {design.md, tasks.md}` на frontmatter-ключ `layers`; найден →
  `SpecLayersError("noncanonical_owner", "<file>:layers")` ДО резолва дефолтов; stderr
  `spec_layers_error=noncanonical_owner field=<file>:layers`, exit 1; отсутствующий sibling — игнор.
- `references/pipeline.default.yaml`: блок `sdd.layers` **инлайн-мапой**
  `layers: {contract_first: true, integration_tests: true, e2e_tests: true}` — вложенный блок даёт
  `layers: None` в PyYAML-optional fallback `mb-pipeline-validate.sh` (измерено, C1).
- `scripts/mb-pipeline-validate.sh`: валидация `sdd.layers` рядом с существующими `sdd.*`-проверками —
  каждый ключ boolean, неизвестный ключ → fail, отсутствие блока → ок (дефолты).
- `scripts/mb_work_items.py` **не трогать** (он владеет tasks.md, не frontmatter requirements.md).

**Eval:** `pytest tests/pytest/test_spec_layers.py && bats tests/bats/test_mb_pipeline_sdd_layers.bats` — red: модуль `spec_layers` не реализован, спека без блока не читается как легаси; exit: 1; output~: FAILED tests/pytest/test_spec_layers\.py::test_missing_block_is_legacy

**Testing (TDD — tests BEFORE implementation):**
- pytest: `test_missing_block_is_legacy` — нет блока → все три `false`, `source == "legacy"`, файл не мутирован (R3-001);
  `test_present_block_inherits_pipeline_default` — недостающий ключ в явном блоке берётся из pipeline, `source == "pipeline"`;
  `test_spec_value_beats_pipeline_default` — явное значение спеки побеждает;
  `test_false_without_reason_raises` — `false` без `_reason` → `SpecLayersError(missing_reason, …)`;
  `test_read_does_not_mutate_file` — sha256 requirements.md до/после чтения совпадает (NFR-002);
  `test_layers_block_outside_requirements_rejected` — блок `layers` в design.md/tasks.md → `SpecLayersError(noncanonical_owner, …)`, exit 1 (R2-004).
- bats: `pipeline_sdd_layers_inline_map_parses_in_both_paths` — инлайн-мапа парсится одинаково с PyYAML и без него;
  `pipeline_sdd_layers_non_boolean_fails` — не-boolean значение → fail валидатора.

**DoD:**
- [ ] C1 (API + CLI + дефолты конфига) реализован; pytest и bats green (были red)
- [ ] `bash scripts/mb-pipeline-validate.sh` проходит с новым блоком `sdd.layers`
- [ ] `bash scripts/mb-rules-check.sh --files <изменённые> --out json` — clean
<!-- /mb-task:2 -->

<!-- mb-task:3 -->
## Task 3: Структурные гейты слоёв в валидаторе

**Stage:** 2
**Covers:** REQ-001, REQ-007, REQ-008, REQ-014
**Role:** backend
**Blocked-by:** 2
**Scope:** scripts/mb-spec-validate.sh, tests/bats/test_mb_spec_validate_layers.bats
**Budget:** 100000

**What to do:**
- **Легаси-короткое замыкание (R3-001)**: `source == "legacy"` (спека без блока `layers`) → НИ ОДИН
  layer-гейт не применяется, печатается `layers=legacy`, спека проверяется как pre-S8 (byte-identical);
  найденные `Layer:`-задачи в легаси-спеке violation НЕ дают (grandfather, включая саму S8).
- Гейты по C3/C4 в `mb-spec-validate.sh` для `source ∈ {spec, pipeline}`, ровно по таблице C3
  (predicate `has_gated_req` = есть хотя бы один EARS-критерий с нормативным SHALL/MUST; SHOULD/MAY не
  gated — D-06):
  - `contract_first: true` **и** `has_gated_req: true` → ровно одна задача `Layer: contract`, её
    индекс меньше индекса любой implementation-задачи (задачи без поля `**Layer:**`);
  - `contract_first: true` **и** `has_gated_req: false` → контрактная задача не требуется, печатается
    `contract_layer=not_applicable`;
  - `contract_first: false` → задача `Layer: contract` отсутствует, найденная → violation;
  - слои по **матрице C4** (R3-003): `integration=true` → integration после всех implementation;
    `e2e=true` → e2e после всех implementation и, **если integration-задача есть**, после неё
    (`integration=false, e2e=true` → implementation → e2e, отдельная строка матрицы); при `false`
    задача не требуется, отключённый слой печатается в отчёте.
- Схема реестра `Contract-checkers` (C3a, JSON) проверяется, когда контрактная задача закрыта: каждый
  gated REQ покрыт хотя бы одним `covers`; `argv` — непустой массив строк; `evidence` bank-relative под
  `tmp/contract-gate/<topic>/` c плейсхолдером `{phase}`; `output_ere` компилируется как ERE;
  неизвестный/отсутствующий ключ или невалидный тип → violation.

**Eval:** `bats tests/bats/test_mb_spec_validate_layers.bats` — red: гейты слоёв не добавлены, фикстура без контрактной задачи проходит зелёной; exit: 1; output~: not ok [0-9]+ spec_validate_missing_contract_task_fails

**Testing (TDD — tests BEFORE implementation):**
- bats на фикстурных спеках: `spec_validate_missing_contract_task_fails` — нет контрактной задачи при `true` + gated → exit≠0;
  `spec_validate_contract_task_after_impl_fails` — контрактная задача после implementation-задачи → exit≠0;
  `spec_validate_no_gated_req_not_applicable` — `true` без gated REQ → exit 0 + `contract_layer=not_applicable`;
  `spec_validate_contract_first_false_ok` — та же фикстура при `false` → exit 0, слой назван в отчёте;
  `spec_validate_e2e_before_integration_fails` — e2e перед integration (при обеих `true`) → exit≠0;
  `spec_validate_e2e_without_integration_ok` — `integration=false, e2e=true`: implementation → e2e → exit 0 (R3-003);
  `spec_validate_legacy_spec_without_layers_ok` — легаси-спека без `layers` (с `Layer:`-задачами) валидна, печатает `layers=legacy` (R3-001, регресс на саму S8);
  `spec_validate_registry_schema_checked_when_closed` — JSON-реестр с `evidence` вне `tmp/contract-gate/<topic>/` или неизвестным ключом → exit≠0.

**DoD:**
- [ ] C3/C4-гейты (матрица слоёв R3-003) + легаси-короткое замыкание (R3-001) + схема JSON-реестра реализованы; bats green (были red)
- [ ] легаси-спеки (включая саму S8) проходят без изменений и печатают `layers=legacy` (NFR-002/R3-001)
- [ ] `bash scripts/mb-rules-check.sh --files <изменённые> --out json` — clean
<!-- /mb-task:3 -->

<!-- mb-task:4 -->
## Task 4: Детерминированный рендерер слоёв и Quality DoD

**Stage:** 2
**Covers:** REQ-002, REQ-003, REQ-009, REQ-011, REQ-015, REQ-018
**Role:** architect
**Blocked-by:** 1, 3
**Scope:** scripts/mb-sdd-layers-render.py, commands/sdd.md, references/templates.md, tests/pytest/test_sdd_layers_render.py
**Budget:** 120000

**What to do:**
- Новый `scripts/mb-sdd-layers-render.py` по контракту C8: вход `--requirements`, `--pipeline`,
  `--rules-json --json`; stdout — **ровно** `{"tasks_markdown":"<string>","quality_dod_markdown":"<string>"}`
  (два типизированных фрагмента, R2-010): `tasks_markdown` — блок задач слоёв (контрактная задача с 5
  шагами C3 и DoD со шагами 4–5; integration/e2e с полными `test_id` по правилу отображения C4, порядок
  по матрице C4); `quality_dod_markdown` — ровно одна секция `## Quality DoD` по формату C5.
  **Все три слоя `false` → `tasks_markdown == ""`, но `quality_dod_markdown` непуст** (REQ-015 не
  теряется). Неизвестные/отсутствующие ключи JSON → exit 1. **Файлов не пишет** (чистая функция),
  exit 0/1/2.
- `commands/sdd.md`: генератор спрашивает про слои, пишет `layers` во frontmatter requirements.md с
  причиной при отказе, вызывает рендерер и вставляет `tasks_markdown` ТОЛЬКО в `tasks.candidate.md`, а
  `quality_dod_markdown` ТОЛЬКО в `design.candidate.md`; запись принятого триплета остаётся за
  оркестратором по S2-C3 (candidate → гейт → атомарный перенос, S2-X-06).
- `references/templates.md`: шаблоны трёх задач и секции Quality DoD.
- Граница честности (R2-010): кодом проверяется рендерер, а не LLM-промпт; корректность
  сгенерированной спеки ловится гейтами T3 и батареей S2-C8 **после** генерации.

**Eval:** `pytest tests/pytest/test_sdd_layers_render.py` — red: рендерер C8 не существует, порядок contract → impl → integration → e2e не рендерится; exit: 1; output~: FAILED tests/pytest/test_sdd_layers_render\.py::test_task_order_contract_impl_integration_e2e

**Testing (TDD — tests BEFORE implementation):**
- pytest на фикстурах: `test_task_order_contract_impl_integration_e2e` — порядок задач в `tasks_markdown`;
  `test_contract_task_has_five_steps_no_business_code` — 5 шагов C3, бизнес-кода нет;
  `test_layer_tasks_list_full_test_ids` — DoD слоёв перечисляет полные `test_id` из `mb-scenario-extract.py`, без сокращений;
  `test_e2e_without_integration_order` — `integration=false, e2e=true` → implementation → e2e (R3-003);
  `test_all_layers_false_empty_tasks_keeps_quality_dod` — при всех слоях `false`: `tasks_markdown == ""` **и** `quality_dod_markdown` содержит ровно одну секцию `## Quality DoD` (R2-010, REQ-015);
  `test_quality_dod_references_paths_not_text` — Quality DoD содержит пути из C2 + буллеты рубрики и не содержит скопированного текста правил;
  `test_renderer_writes_no_files` — снимок дерева до/после вызова совпадает.

**DoD:**
- [ ] C8-рендерер + вызов из `commands/sdd.md` + шаблоны; pytest green (был red)
- [ ] рендерер не пишет файлов; запись триплета — только оркестратор (S2-C3)
- [ ] `bash scripts/mb-rules-check.sh --files <изменённые> --out json` — clean
<!-- /mb-task:4 -->

<!-- mb-task:5 -->
## Task 5: Реестр чекеров, раннер и контрактный гейт в verify

**Stage:** 3
**Covers:** REQ-004, REQ-005, REQ-006, REQ-020, REQ-021
**Role:** backend
**Blocked-by:** 4
**Scope:** scripts/mb-contract-gate.sh, commands/mb.md, commands/work.md, tests/bats/test_mb_contract_gate.bats
**Budget:** 110000

**What to do:**
- Новый `scripts/mb-contract-gate.sh red|verify --spec SPEC_DIR [--mb BANK] [--json]` по контракту
  C3a: читает JSON-блок `Contract-checkers` из тела контрактной задачи `<spec-dir>/tasks.md`
  (парс Python-stdlib `json`; неизвестный/отсутствующий ключ, невалидный тип `path`/`argv`, `evidence`
  с абсолютным/`..`/symlink-escape путём или невалидный ERE → **exit 2 до запуска чекеров**, R3-002),
  исполняет `argv` каждого чекера **shell=false** из корня репо, пишет evidence **закрытой схемы**
  (`{version, topic, checker_id, phase, cmd, cmd_sha256, exit, output_match, verdict}`) temp+`mv`.
  - `red`: чекер обязан упасть **по заявленной причине** (`exit != 0` **и** совпадение `output_ere`);
    зелёный до реализации → `verdict=fake_red`, exit 1; упал не по заявленной причине →
    `verdict=foreign_failure`, exit 1; все совпали → `verdict=pass`.
  - **`verify` precondition — red-evidence gate (CPR-A)**: до verify-чекеров по каждому требуется
    существующий валидный red-evidence с `verdict=pass` и byte-identical `cmd`/`cmd_sha256`; missing,
    malformed или дрейф → **exit 2 БЕЗ запуска verify**. Затем все чекеры обязаны вернуть 0; иначе
    exit 1 → верификация FAIL; verify пишет отдельный `<id>.verify.json`.
  - exit 0/1/2 (2 — usage / отсутствующий-невалидный реестр / проваленный red-evidence gate).
- `commands/work.md` — **контрактная задача = один чекбокс, два implementer-диспатча (R2-001)**:
  **Dispatch A (declare)** не пишет product/checker-файлы, возвращает `MB_CONTRACT_CHECKERS_JSON={…}`
  отдельным блоком **перед** финальным `MB_WORK_RESULT_JSON=` (S5-C4 не нарушается: последним непустым
  блоком остаётся envelope), завершается; оркестратор валидирует, пишет реестр в тело задачи (D-23) и
  фиксирует шаг `contract_declared` (`mb-work-state.sh step`). **Dispatch B (build)** получает
  замороженный реестр, пишет только юнит-тесты чекеров и реализации чекеров, завершается штатным
  envelope. Resume: валидный реестр + шаг `contract_declared` → A пропускается; иначе A повторяется. До
  успешного `red` бизнес-диспатч запрещён. Шаг 5 — оркестратор запускает `mb-contract-gate.sh red`;
  `fake_red`/`foreign_failure` — локальный hard stop, чекбокс не закрывается (C7); ненаблюдаемое
  требование → hard stop «дефект спеки». В `§ 5c` verify-шага — вызов `mb-contract-gate.sh verify`.
  Канонический порядок стадий не меняется.
- `commands/mb.md § verify`: тот же вызов `mb-contract-gate.sh verify` перед вердиктом plan-verifier.
  (`commands/verify.md` не существует — проверено `ls commands/`.)

**Eval:** `bats tests/bats/test_mb_contract_gate.bats` — red: `mb-contract-gate.sh` не существует, зелёный-до-реализации чекер не даёт `fake_red`; exit: 1; output~: not ok [0-9]+ contract_gate_fake_red_fails

**Testing (TDD — tests BEFORE implementation):**
- bats на фикстурах: `contract_gate_fake_red_fails` — чекер, зелёный до реализации → exit 1 + `verdict=fake_red`, задача открыта;
  `contract_gate_foreign_failure_rejected` — чекер упал, но `output_ere` не совпал → exit 1 + `verdict=foreign_failure`;
  `contract_gate_red_all_matched_passes` — все чекеры красные по заявленной причине → exit 0 + `verdict=pass`;
  `contract_gate_verify_red_checker_fails` — красный чекер на verify → exit 1;
  `contract_gate_verify_all_green_passes` — все зелёные (при валидном red-evidence) → exit 0;
  `contract_gate_missing_registry_exits_2` — реестра нет → exit 2;
  `contract_gate_invalid_schema_exits_2` — JSON-реестр с неизвестным ключом / `evidence` вне `tmp/contract-gate/<topic>/` / `..`-путём → exit 2 до запуска (R3-002);
  `contract_gate_evidence_exact_schema` — evidence несёт РОВНО поля `{version,topic,checker_id,phase,cmd,cmd_sha256,exit,output_match,verdict}` (CPR-A);
  `contract_gate_verify_missing_red_evidence_exits_2` — verify без red-evidence → exit 2 без запуска (CPR-A);
  `contract_gate_verify_malformed_evidence_exits_2` — malformed red-evidence → exit 2 без запуска;
  `contract_gate_verify_cmd_drift_exits_2` — `cmd_sha256` реестра ≠ evidence (реестр изменён после red) → exit 2 без запуска;
  `contract_gate_evidence_atomic_no_partial` — прерывание до `mv` не оставляет частичного evidence (crash-before-mv, CPR-A);
  `bash scripts/mb-pipeline-validate.sh` подтверждает неизменность порядка стадий.

**DoD:**
- [ ] C3a-раннер (JSON/argv, R3-002) + двухфазный диспатч A/B + resume (R2-001) + red-evidence gate перед verify (CPR-A); bats green (были red)
- [ ] `fake_red` и `foreign_failure` — локальные hard stop, в S5 не маршрутизируются (C7)
- [ ] `bash scripts/mb-rules-check.sh --files <изменённые> --out json` — clean
<!-- /mb-task:5 -->

<!-- mb-task:6 -->
## Task 6: Доставка Quality DoD исполнителю, ревьюеру и судье

**Stage:** 3
**Covers:** REQ-010, REQ-019
**Role:** architect
**Blocked-by:** 5
**Scope:** scripts/mb-review.sh, commands/work.md, agents/mb-reviewer.md, agents/mb-judge.md, tests/pytest/test_quality_dod_delivery.py
**Budget:** 80000

**What to do:**
- По контракту C6: оркестратор рендерит один канонический **статический** блок `## Quality DoD` из
  `mb-rules-resolve.sh --spec <dir> --json` (источники + **буллеты `review_rubric`** + строка чекера,
  R2-012) и доставляет **байт-идентично** трём получателям:
  - `scripts/mb-review.sh`: новый флаг `--quality-dod <path>` добавляет секцию `## Quality DoD`
    шестой в фиксированный порядок payload (оркестрированный ревьюер файлов не читает —
    `agents/mb-reviewer.md:36-40`);
  - `commands/work.md § 5a` — промпт исполнителя; `§ 5e` — промпт судьи.
- **Детерминированная evidence чекера в Prior evidence (R2-012)**: перед диспатчем ревьюера И судьи
  оркестратор один раз запускает `mb-rules-check.sh --files <touched> --out json`; ненулевой код
  **блокирует диспатч**, канонический JSON-результат добавляется в секцию **Prior evidence** payload'а
  (ВНЕ статического блока `## Quality DoD`, поэтому его sha256 остаётся общим у трёх получателей).
- `pipeline.yaml` и `references/pipeline.default.yaml` **не мутируются** (C6 п.5) — рантайм-правка
  конфига создала бы второй источник правды о правилах.
- `agents/mb-reviewer.md`, `agents/mb-judge.md`: пересечение контрактных и интеграционных/e2e тестов —
  не дефект DRY (REQ-010).

**Eval:** `pytest tests/pytest/test_quality_dod_delivery.py` — red: доставки нет, три payload не несут байт-идентичный блок; exit: 1; output~: FAILED tests/pytest/test_quality_dod_delivery\.py::test_three_payloads_share_one_sha256

**Testing (TDD — tests BEFORE implementation):**
- pytest: `test_three_payloads_share_one_sha256` — sha256 **статического** блока в промпте исполнителя, payload ревьюера и промпте судьи совпадает;
  `test_reviewer_payload_carries_rubric_bullets` — payload ревьюера/судьи несёт буллеты `review_rubric` (R2-012);
  `test_rules_check_json_in_prior_evidence` — JSON-результат `mb-rules-check.sh` присутствует в Prior evidence ревьюера/судьи, вне статического блока (R2-012);
  `test_rules_check_nonzero_blocks_dispatch` — ненулевой `mb-rules-check.sh` блокирует диспатч ревьюера/судьи;
  `test_missing_rule_source_fails_dispatch` — отсутствующий объявленный источник валит диспатч (REQ-017);
  `test_pipeline_files_not_mutated` — sha256 `pipeline.default.yaml` до/после диспатча совпадает;
  `test_overlap_not_reported_as_dry_violation` — фикстура с пересекающимся покрытием не даёт вердикта-нарушения.

**DoD:**
- [ ] C6 реализован; pytest green (был red)
- [ ] конфиги не мутируются; новых каналов доставки не появилось (S8-D-09)
- [ ] `bash scripts/mb-rules-check.sh --files <изменённые> --out json` — clean
<!-- /mb-task:6 -->

<!-- mb-task:7 -->
## Task 7: Интеграционные тесты слайса

**Stage:** 4
**Layer:** integration
**Covers:** REQ-001, REQ-002, REQ-007, REQ-008, REQ-009, REQ-011, REQ-012, REQ-013, REQ-014, REQ-015, REQ-016, REQ-017, REQ-019
**Role:** qa
**Blocked-by:** 6
**Scope:** tests/pytest/test_integration_contract_test_loop.py
**Budget:** 100000

**What to do:**
- Интеграционные тесты на реальной связке компонентов (моки только на внешние границы):
  рендерер C8 → `mb-spec-validate.sh` принимает спеку со слоями → `mb_work_items.py` отдаёт задачи в
  порядке contract → impl → integration → e2e с корректными ролями; `mb-rules-resolve.sh` резолвит
  Quality DoD и доставляет его трём получателям.
- Имена тест-функций — по правилу отображения C4: `test_` + `test_id` с `-` → `_`.

**Eval:** `pytest tests/pytest/test_integration_contract_test_loop.py` — red: связка не собрана, спека со слоями не проходит валидатор; exit: 1; output~: FAILED tests/pytest/test_integration_contract_test_loop\.py::test_REQ_001__contract_task_comes_first

**Testing (TDD — tests BEFORE implementation):**
- Success: `REQ-001__contract_task_comes_first`, `REQ-007__two_test_layers_at_the_end_of_the_spec`,
  `REQ-012__legacy_spec_read_without_mutation`, `REQ-015__project_rules_beat_bank_rules`.
- Edge: `REQ-011__fast_mode_refusal_is_recorded`, `REQ-017__missing_rule_source_fails_loudly`.

**DoD:**
- [ ] Интеграционные тесты покрывают scenario test_ids: `REQ-001__contract_task_comes_first`, `REQ-007__two_test_layers_at_the_end_of_the_spec`, `REQ-011__fast_mode_refusal_is_recorded`, `REQ-012__legacy_spec_read_without_mutation`, `REQ-015__project_rules_beat_bank_rules`, `REQ-017__missing_rule_source_fails_loudly`; green (были red)
- [ ] Внешних моков ≤5 (правило Testing Trophy, `rules/RULES.md:286`)
- [ ] `bash scripts/mb-rules-check.sh --files <изменённые> --out json` — clean
<!-- /mb-task:7 -->

<!-- mb-task:8 -->
## Task 8: E2E-тесты слайса

**Stage:** 4
**Layer:** e2e
**Covers:** REQ-003, REQ-004, REQ-005, REQ-006, REQ-020, REQ-021
**Role:** qa
**Blocked-by:** 7
**Scope:** tests/pytest/test_e2e_contract_test_loop.py
**Budget:** 100000

**What to do:**
- E2E на фикстурном банке через реальные команды: полный путь спека → контрактная задача →
  реестр чекеров → красный прогон `mb-contract-gate.sh red` → бизнес-код → `mb-contract-gate.sh verify`.
- Имена тест-функций — по правилу отображения C4: `test_` + `test_id` с `-` → `_`.

**Eval:** `pytest tests/pytest/test_e2e_contract_test_loop.py` — red: сквозной путь не собран, verify не гоняет контрактные чекеры; exit: 1; output~: FAILED tests/pytest/test_e2e_contract_test_loop\.py::test_REQ_020__verify_runs_the_contract_checkers

**Testing (TDD — tests BEFORE implementation):**
- Success: `REQ-020__verify_runs_the_contract_checkers`.
- Edge: `REQ-004__fake_red_fails_the_contract_task`, `REQ-003__checker_without_a_negative_fixture_rejected`,
  `REQ-006__unobservable_requirement_escalates`.

**DoD:**
- [ ] E2E покрывают scenario test_ids: `REQ-003__checker_without_a_negative_fixture_rejected`, `REQ-004__fake_red_fails_the_contract_task`, `REQ-006__unobservable_requirement_escalates`, `REQ-020__verify_runs_the_contract_checkers`; green (были red)
- [ ] Прогон детерминирован (нет зависимости от сети и времени)
- [ ] `bash scripts/mb-rules-check.sh --files <изменённые> --out json` — clean
<!-- /mb-task:8 -->
