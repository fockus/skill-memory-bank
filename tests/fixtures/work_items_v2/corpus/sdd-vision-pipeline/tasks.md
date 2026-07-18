# Tasks: sdd-vision-pipeline

> Umbrella-задачи группы `sdd-vision-pipeline`. T1 — прямая задача; T2–T10 — мета-задачи слайсов
> (контракт Delegate, umbrella design §Interfaces-8): каждая = JIT-интервью → child-спека `specs/svp-*`
> (созданы 2026-07-17…18) → исполнение через `/mb work <слайс>` до done.
> Порядок (ICE-убывание внутри DAG, синхронно с design §DAG и roadmap § Group):
> T1 → T2 (S1, 504) → T8 (S7, 448) → T3 (S4, 432) → T4 (S2, 400) → T9 (S8, 360) → T5 (S6, 336) → T10 (S9, 336, после S2) → T7 (S3, 252) → T6 (S5, 294, после S3).
> Порядок выше — рекомендация; **жёсткие рёбра DAG задаёт только поле `Blocked-by:` каждой задачи**
> (номера задач ЭТОГО файла, не слайсов).
> Формат задач — легаси (tasks.md v2 появится в S2, D-26); поле `Blocked-by:` записано заранее по
> грамматике S2-C1 (`<csv|none>`), т.к. легаси-дефолт v2 — «предыдущая задача»: без явного поля
> umbrella выродилась бы в цепь T1→…→T9 вместо заявленного DAG (ревью SVP-008).
> Eval мета-задач — детерминированный Delegate-гейт (red, пока в child-спеке есть незакрытые чекбоксы).
>
> Ревизия 3 (2026-07-17): закрыты находки круга 2 (SVP-008, R2-002, R2-010-adjacent) + смысловой
> аудит — DAG зашит в `Blocked-by:` всех 9 задач и сверен с frontmatter 8 child-спек, порядок
> синхронизирован с design/roadmap (D-31), attribution-Eval стал поведенческим (R2-002).
>
> Ревизия 4 (2026-07-17): каждый `Eval:` несёт `output~:`-якорь настоящего провала (групповая норма
> X-05, S2-C1 + S2 REQ-054/055). Delegate-гейт T2–T9 получил **наблюдаемую** сигнатуру: прежняя форма
> `… && [ "$(grep -c '^- \[ \]' …)" -eq 0 ]` падала с exit 1 и **нулём байт вывода** (измерено), т.е.
> не поддавалась ERE-якорю вовсе, а якорь на ошибке `mb-spec-validate.sh` не подошёл бы — валидатор
> на всех 8 child-спеках **зелёный** (exit 0), red даёт именно чекбокс-конъюнкт. Семантика гейта не
> изменена (зелено ⟺ валидатор ok И ноль открытых чекбоксов); провальный конъюнкт теперь печатает
> `delegate_incomplete spec=<topic> open_dod=<N>`. `|| true` в подстановке обязателен: `grep -c` при
> нуле совпадений выходит с кодом 1 и без него зелёная спека ломала бы `&&`-цепь (измерено).

<!-- mb-task:1 -->
## Task 1: MIT-атрибуция mattpocock/skills

**Covers:** REQ-038
**Role:** developer
**Blocked-by:** none

**What to do:**
- Добавить credits-блок в README (источник: https://github.com/mattpocock/skills, MIT; заимствованные паттерны: grilling rules, red-capable eval gate, tracer-bullet/DAG, triage state machine, agent briefs).
- Добавить ссылку на источник **и MIT-атрибуцию** в `commands/discuss.md` рядом с grilling rules (сейчас цитируют grill-me/grill-with-docs без атрибуции).
- Упомянуть Karpathy LLM-wiki gist как источник правил будущего `/mb docs` в том же credits-блоке.

**Eval:** `bats tests/bats/test_mattpocock_attribution.bats` — red: bats-файл материализован, credits-блоков в `README.md` и `commands/discuss.md` нет — позитивные кейсы обоих файлов падают; exit: 1; output~: `not ok [0-9]+ attribution: `

**Testing (TDD — tests BEFORE implementation):**
- **Конвенция именования (обязательна — она и есть red-якорь)**: имя каждого bats-теста начинается с `attribution: `. Причина: `bats` на отсутствующем файле даёт exit 1 + `not ok 1 bats-gather-tests`, то есть тот же код, что и настоящий провал, — exit-only якорь принял бы «файла нет» за red; ERE не поддерживает negative lookahead, поэтому якорь опирается на положительный именованный префикс, которого у `bats-gather-tests` нет.
- Новый `tests/bats/test_mattpocock_attribution.bats` (конвенция docs-тестов: `test_cursor_docs.bats`, `test_sdd_docs.bats`; CI гоняет `bats tests/bats/`).
- Тест требует в КАЖДОМ из `README.md` и `commands/discuss.md` credits/source-блок, содержащий и ссылку `https://github.com/mattpocock/skills`, и слово `MIT` **в пределах одного блока** (проверка окна строк вокруг ссылки, а не по всему файлу).
- Негативная половина обязательна: голая ссылка без MIT и «MIT где-то в файле» (у README уже есть MIT-бейдж и строка лицензии — `README.md:18,704`) не зеленят тест.

**DoD:**
- [x] README содержит credits-блок со ссылкой на репозиторий и MIT в том же блоке
- [x] commands/discuss.md ссылается на источник grilling-паттернов с MIT-атрибуцией
- [x] `bats tests/bats/test_mattpocock_attribution.bats` зелёный; на фикстуре «ссылка без MIT» — красный
<!-- /mb-task:1 -->

<!-- mb-task:2 -->
## Task 2: Слайс S1 — svp-interview-upgrade (ICE 504)

**Covers:** REQ-004, REQ-010, REQ-011, REQ-012, REQ-013, REQ-014, REQ-015, REQ-033, REQ-034, REQ-040, REQ-054
**Role:** architect
**Delegate:** svp-interview-upgrade
**Blocked-by:** none
**Eval:** `bash scripts/mb-spec-validate.sh --require-scenarios .memory-bank/specs/svp-interview-upgrade && { n=$(grep -c '^- \[ \]' .memory-bank/specs/svp-interview-upgrade/tasks.md || true); [ "$n" -eq 0 ] || { echo "delegate_incomplete spec=svp-interview-upgrade open_dod=$n"; false; }; }` — red: child-спека валидна (валидатор зелёный), но её tasks.md несёт незакрытые чекбоксы — делегирование не завершено; exit: 1; output~: `delegate_incomplete spec=svp-interview-upgrade open_dod=[1-9][0-9]*`

**What to do:**
- Короткое JIT-интервью по слайс-специфике (эвристика оценки объёма; формат interview-plan файла; поведение self-interview assumptions).
- Создать child-спеку `specs/svp-interview-upgrade/` (group: sdd-vision-pipeline) по контексту D-04/09/10/11/12/18/22/29.
- Исполнить через `/mb work svp-interview-upgrade`: доработка `commands/discuss.md` (план интервью, финальный гейт, размерный триаж, глоссарий, транскрипт, batch-режим).

**Testing (TDD — tests BEFORE implementation):**
- bats-тесты новых скрипт-помощников; проверка генерации interview-plan и транскрипта на фикстурном топике.

**DoD:**
- [ ] child-спека создана и валидна (mb-spec-validate)
- [ ] REQ слайса покрыты задачами child-спеки
- [ ] /mb work по слайсу завершён (verify green)
<!-- /mb-task:2 -->

<!-- mb-task:3 -->
## Task 3: Слайс S4 — svp-roadmap-backlog-db (ICE 432)

**Covers:** REQ-024, REQ-025, REQ-026, REQ-027, REQ-028, REQ-029, REQ-041
**Role:** backend
**Delegate:** svp-roadmap-backlog-db
**Blocked-by:** none
**Eval:** `bash scripts/mb-spec-validate.sh --require-scenarios .memory-bank/specs/svp-roadmap-backlog-db && { n=$(grep -c '^- \[ \]' .memory-bank/specs/svp-roadmap-backlog-db/tasks.md || true); [ "$n" -eq 0 ] || { echo "delegate_incomplete spec=svp-roadmap-backlog-db open_dod=$n"; false; }; }` — red: child-спека валидна (валидатор зелёный), но её tasks.md несёт незакрытые чекбоксы — делегирование не завершено; exit: 1; output~: `delegate_incomplete spec=svp-roadmap-backlog-db open_dod=[1-9][0-9]*`

**What to do:**
- JIT-интервью (формат реестра декомпозированных спек; схема ICE/group frontmatter; рендер Group-секций).
- Child-спека `specs/svp-roadmap-backlog-db/`; исполнение: расширение mb-roadmap-sync (ICE-сортировка, %, счётчики, Group), беклог-стейт-машина + валидатор, out-of-scope-реестр.

**Testing (TDD — tests BEFORE implementation):**
- bats: сортировка по ICE, pin-override, % из чекбокс-фикстур, недопустимые переходы статусов падают.

**DoD:**
- [ ] child-спека создана и валидна
- [ ] roadmap рендерит Group: sdd-vision-pipeline с ICE-порядком и прогрессом автоматически
- [ ] /mb work по слайсу завершён (verify green)
<!-- /mb-task:3 -->

<!-- mb-task:4 -->
## Task 4: Слайс S2 — svp-sdd-core (ICE 400)

**Covers:** REQ-001, REQ-002, REQ-003, REQ-005, REQ-006, REQ-007, REQ-008, REQ-009, REQ-016, REQ-022, REQ-035, REQ-039, REQ-047, REQ-048
**Role:** architect
**Delegate:** svp-sdd-core
**Blocked-by:** none
**Eval:** `bash scripts/mb-spec-validate.sh --require-scenarios .memory-bank/specs/svp-sdd-core && { n=$(grep -c '^- \[ \]' .memory-bank/specs/svp-sdd-core/tasks.md || true); [ "$n" -eq 0 ] || { echo "delegate_incomplete spec=svp-sdd-core open_dod=$n"; false; }; }` — red: child-спека валидна (валидатор зелёный), но её tasks.md несёт незакрытые чекбоксы — делегирование не завершено; exit: 1; output~: `delegate_incomplete spec=svp-sdd-core open_dod=[1-9][0-9]*`

**What to do:**
- JIT-интервью (грамматика tasks.md v2; схема sdd.spec_review в pipeline.yaml; бюджет-эвристика; размерный триаж самого слайса — при >1M разбить).
- Child-спека `specs/svp-sdd-core/`; исполнение: sdd-конвейер (оркестрация discuss, генерация контента, §Contract+seams, Eval-декларации), парсер v2 backward-compatible, spec-review этап.
- Размерная эскалация на генерации (D-35): превышение бюджета останавливает sdd ДО записи tasks.md → выбор пользователя: разбить сейчас (доп-интервью на слайс) / MVP-урезка с беклог-реестром / тонкая umbrella+JIT / override во frontmatter; auto-режим — self-interview слайсы по умолчанию (REQ-047/048).

**Testing (TDD — tests BEFORE implementation):**
- Контрактные тесты mb_work_items.py на легаси-фикстурах ДО изменений; тесты v2-полей; негативные (Eval:none на gated → fail).

**DoD:**
- [ ] child-спека создана и валидна
- [ ] легаси-фикстуры парсятся byte-identical (REQ-039)
- [ ] /mb work по слайсу завершён (verify green)
<!-- /mb-task:4 -->

<!-- mb-task:5 -->
## Task 5: Слайс S6 — svp-docs-wiki (ICE 336, blocked by S2)

**Covers:** REQ-036, REQ-037
**Role:** developer
**Delegate:** svp-docs-wiki
**Blocked-by:** 4
**Eval:** `bash scripts/mb-spec-validate.sh --require-scenarios .memory-bank/specs/svp-docs-wiki && { n=$(grep -c '^- \[ \]' .memory-bank/specs/svp-docs-wiki/tasks.md || true); [ "$n" -eq 0 ] || { echo "delegate_incomplete spec=svp-docs-wiki open_dod=$n"; false; }; }` — red: child-спека валидна (валидатор зелёный), но её tasks.md несёт незакрытые чекбоксы — делегирование не завершено; exit: 1; output~: `delegate_incomplete spec=svp-docs-wiki open_dod=[1-9][0-9]*`

**What to do:**
- JIT-интервью (структура страниц вики; хранение last-documented SHA; поведение на первом запуске без истории).
- Child-спека `specs/svp-docs-wiki/`; исполнение: команда `/mb docs` (diff-инкремент, Karpathy-правила: index.md, append-only log.md, wikilinks, противоречия), конфиг пути в pipeline.yaml.

**Testing (TDD — tests BEFORE implementation):**
- bats: SHA-стейт, инкрементальный прогон на фикстурном репо, формат log.md-префикса.

**DoD:**
- [ ] child-спека создана и валидна
- [ ] /mb docs генерирует и обновляет вики на фикстурном репо
- [ ] /mb work по слайсу завершён (verify green)
<!-- /mb-task:5 -->

<!-- mb-task:6 -->
## Task 6: Слайс S5 — svp-adapt-escalation (ICE 294, blocked by S2, S3)

**Covers:** REQ-030, REQ-031, REQ-032
**Role:** backend
**Delegate:** svp-adapt-escalation
**Blocked-by:** 3, 4, 7
**Eval:** `bash scripts/mb-spec-validate.sh --require-scenarios .memory-bank/specs/svp-adapt-escalation && { n=$(grep -c '^- \[ \]' .memory-bank/specs/svp-adapt-escalation/tasks.md || true); [ "$n" -eq 0 ] || { echo "delegate_incomplete spec=svp-adapt-escalation open_dod=$n"; false; }; }` — red: child-спека валидна (валидатор зелёный), но её tasks.md несёт незакрытые чекбоксы — делегирование не завершено; exit: 1; output~: `delegate_incomplete spec=svp-adapt-escalation open_dod=[1-9][0-9]*`

**What to do:**
- JIT-интервью (порог циклов эскалации по телеметрии pivot-log; формат complexity_escalation; текст развилки для вайбкодеров).
- Child-спека `specs/svp-adapt-escalation/`; исполнение: сигнал + дет-гарды в /mb work, развилки auto/interactive, stub-за-флагом + беклог-запись.

**Testing (TDD — tests BEFORE implementation):**
- bats: каждый гард триггерит развилку; auto-режим создаёт беклог-элемент и продолжает; интерактив предлагает 4 варианта.

**DoD:**
- [ ] child-спека создана и валидна
- [ ] эскалации логируются структурно (JSONL)
- [ ] /mb work по слайсу завершён (verify green)
<!-- /mb-task:6 -->

<!-- mb-task:7 -->
## Task 7: Слайс S3 — svp-parallel-engine (ICE 252, blocked by S2)

**Covers:** REQ-017, REQ-018, REQ-019, REQ-020, REQ-021, REQ-022, REQ-023, REQ-042, REQ-043, REQ-044
**Role:** architect
**Delegate:** svp-parallel-engine
**Blocked-by:** 4
**Eval:** `bash scripts/mb-spec-validate.sh --require-scenarios .memory-bank/specs/svp-parallel-engine && { n=$(grep -c '^- \[ \]' .memory-bank/specs/svp-parallel-engine/tasks.md || true); [ "$n" -eq 0 ] || { echo "delegate_incomplete spec=svp-parallel-engine open_dod=$n"; false; }; }` — red: child-спека валидна (валидатор зелёный), но её tasks.md несёт незакрытые чекбоксы — делегирование не завершено; exit: 1; output~: `delegate_incomplete spec=svp-parallel-engine open_dod=[1-9][0-9]*`

**What to do:**
- JIT-интервью (механика claims + TTL; параллель × review-ансамбль; worktree-опция).
- Child-спека `specs/svp-parallel-engine/`; исполнение: --parallel в /mb work, frontier API, Scope-дизъюнктность, claim-слой, orchestrator-only записи банка, platform_limited деградация.
- Group-target: `/mb work <group>` исполняет членов группы по DAG+ICE (REQ-042); при старте — вопрос о режиме исполнения (sequential / parallel: teammates | сабагенты | несколько сессий через worktree/COORDINATION.md) и режиме вмешательства HITL/автономный (REQ-043); автономный прерывается только на эскалациях, проблемы репортятся всегда (REQ-044).

**Testing (TDD — tests BEFORE implementation):**
- bats/pytest: фронтир-выборка, цикл DAG → fail, Scope-сверка диффа, stale-claim release; негативные parity-тесты на хостах без диспатча.

**DoD:**
- [ ] child-спека создана и валидна
- [ ] параллельный прогон на фикстурной спеке без конфликтов записи
- [ ] /mb work по слайсу завершён (verify green)
<!-- /mb-task:7 -->

<!-- mb-task:8 -->
## Task 8: Слайс S7 — svp-brief (ICE 448, blocked by S1)

**Covers:** REQ-045, REQ-046
**Role:** developer
**Delegate:** svp-brief
**Blocked-by:** 2
**Eval:** `bash scripts/mb-spec-validate.sh --require-scenarios .memory-bank/specs/svp-brief && { n=$(grep -c '^- \[ \]' .memory-bank/specs/svp-brief/tasks.md || true); [ "$n" -eq 0 ] || { echo "delegate_incomplete spec=svp-brief open_dod=$n"; false; }; }` — red: child-спека валидна (валидатор зелёный), но её tasks.md несёт незакрытые чекбоксы — делегирование не завершено; exit: 1; output~: `delegate_incomplete spec=svp-brief open_dod=[1-9][0-9]*`

**What to do:**
- JIT-интервью (формат одностраничника; папка briefs/ + связь с inputs-registry sdd-openspec-parity; порог «лёгких» вопросов).
- Child-спека `specs/svp-brief/`; исполнение: команда `/mb brief <topic>` — анализ запроса+документов любого формата, лёгкие уточнения, генерация одностраничника (суть / цель+импакт / референсы / решение JTBD / сценарии / ограничения / UX / критерии готовности / приложения), сохранение с исходниками, хендоф в `/mb discuss` (Phase 0 читает бриф).

**Testing (TDD — tests BEFORE implementation):**
- bats: структура папки брифа, обязательные секции одностраничника; ручной сценарий — бриф из свободного промта + приложенного PRD.

**DoD:**
- [ ] child-спека создана и валидна
- [ ] /mb brief генерирует одностраничник на фикстурном запросе; discuss подхватывает его в Phase 0
- [ ] /mb work по слайсу завершён (verify green)
<!-- /mb-task:8 -->

<!-- mb-task:9 -->
## Task 9: Слайс S8 — svp-contract-test-loop (ICE 360, blocked by S2)

**Covers:** REQ-049, REQ-050, REQ-051, REQ-052, REQ-053
**Role:** developer
**Delegate:** svp-contract-test-loop
**Blocked-by:** 4
**Eval:** `bash scripts/mb-spec-validate.sh --require-scenarios .memory-bank/specs/svp-contract-test-loop && { n=$(grep -c '^- \[ \]' .memory-bank/specs/svp-contract-test-loop/tasks.md || true); [ "$n" -eq 0 ] || { echo "delegate_incomplete spec=svp-contract-test-loop open_dod=$n"; false; }; }` — red: child-спека валидна (валидатор зелёный), но её tasks.md несёт незакрытые чекбоксы — делегирование не завершено; exit: 1; output~: `delegate_incomplete spec=svp-contract-test-loop open_dod=[1-9][0-9]*`

**What to do:**
- Self-interview проведён 2026-07-17 (S8-D-01…11); child-спека `specs/svp-contract-test-loop/` создана и валидна.
- Исполнение: резолвер правил (`mb-rules-resolve.sh`), парс `layers` во frontmatter, структурные гейты слоёв в `mb-spec-validate.sh`, генерация контрактной задачи + задач integration/e2e + секции Quality DoD в `/mb sdd`, контрактный гейт в `verify` с вердиктом `fake_red`, доставка Quality DoD ревьюеру и судье через существующий `review_rubric`.

**Testing (TDD — tests BEFORE implementation):**
- bats/pytest по Eval-декларациям слайса (T1–T6 child-спеки); интеграционная и e2e задачи слайса (T7/T8) покрывают его собственные 12 сценариев.

**DoD:**
- [ ] child-спека создана и валидна
- [ ] контрактная задача, integration- и e2e-задачи генерируются в правильном порядке; при всех слоях `false` вывод байт-идентичен текущему генератору
- [ ] `fake_red` валит контрактную задачу на фикстуре зелёного-до-реализации чекера
- [ ] /mb work по слайсу завершён (verify green)
<!-- /mb-task:9 -->

<!-- mb-task:10 -->
## Task 10: Слайс S9 — svp-spec-review-loop (ICE 336, blocked by S2)

**Covers:** REQ-035
**Role:** developer
**Delegate:** svp-spec-review-loop
**Blocked-by:** 4
**Eval:** `bash scripts/mb-spec-validate.sh --require-scenarios .memory-bank/specs/svp-spec-review-loop && { n=$(grep -c '^- \[ \]' .memory-bank/specs/svp-spec-review-loop/tasks.md || true); [ "$n" -eq 0 ] || { echo "delegate_incomplete spec=svp-spec-review-loop open_dod=$n"; false; }; }` — red: child-спека валидна (валидатор зелёный), но её tasks.md несёт незакрытые чекбоксы — делегирование не завершено; exit: 1; output~: `delegate_incomplete spec=svp-spec-review-loop open_dod=[1-9][0-9]*`

**What to do:**
- Self-interview проведён 2026-07-18 (D-01…08); child-спека `specs/svp-spec-review-loop/` создана и валидна; codex-ревью waived (AGR-022, frontmatter `review: waived`; ревью-долг гасится первым боевым прогоном самого механизма S9 по этой спеке — dogfooding).
- Исполнение через `/mb work svp-spec-review-loop`: pipeline-схема `sdd.spec_judge` + валидация (C1), журнал `record --kind judge|override`/`check --judge`/`status` (C2), детерминированный промпт-сборщик + bundled-рубрика + реестр отклонений (C4/C6), петля review→judge→fix в `commands/sdd.md` (C3), work-гейт `mb-work-spec-gate.sh` + врезка в `commands/work.md` (C5). Автоматический судья расширяет S2-C5, судья-человек остаётся дефолтом (D-30); dual-ownership REQ-035 с S2.

**Testing (TDD — tests BEFORE implementation):**
- bats по Eval-декларациям слайса (T1–T5 child-спеки): spec_judge-конфиг, journal-подкоманды judge/override/status, промпт-сборщик + рубрика + реестр отклонений, петля review→judge→fix, work-гейт.

**DoD:**
- [ ] child-спека создана и валидна
- [ ] автоматический spec_judge + fix-петля + durable реестр отклонений + preflight-гейт `/mb work` реализованы
- [ ] /mb work по слайсу завершён (verify green)
<!-- /mb-task:10 -->
