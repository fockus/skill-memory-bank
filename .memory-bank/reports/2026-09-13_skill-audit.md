# Ревью Memory Bank Skill — 2026-09-13

Объект: весь текущий скил **5.3.1**, исходники на `f3e23f1`, включая скрипты, инструкции команд, установку и тесты. Это аудит, исправления не выполнялись. Незакоммиченные изменения банка от предыдущей сессии сохранены.

Вывод: **нужны исправления до признания lifecycle и completion gates надёжными**. Ниже 15 замечаний: 7 P1 и 8 P2. У 12 замечаний есть воспроизведение поведения скриптов или точного shell-фрагмента; ещё три относятся к контрактам инструкций (R11, R14, R15; у R11/R14 ошибочные shell-фрагменты также исполнены). Это не полный аудит безопасности и не утверждение об отсутствии других проблем.

P1 — потеря пользовательских настроек, раскрытие явно приватного текста или обход проверки завершения/лимита повторов. P2 — некорректная маршрутизация, неполное удаление, потеря полезного контекста или неработающий документированный сценарий.

## P1 — исправить в первую очередь

### R01. Uninstall удаляет существующий Pi settings.json целиком

- Код: [uninstall.sh:115](/Users/fockus/Apps/skill-memory-bank/uninstall.sh:115), строки 115–122; регистрация файла — [install.sh:1193](/Users/fockus/Apps/skill-memory-bank/install.sh:1193).
- Сценарий: в изолированном HOME заранее существует `~/.pi/agent/settings.json` с пользовательскими `theme`, `packages`, `skills`. Выполнить install, затем uninstall.
- Факт: install корректно объединяет настройки, но uninstall возвращает 0 и удаляет весь файл. Pi settings отсутствует в исключениях для merge-managed файлов, хотя попадает в `manifest.files`; backup для него не создаётся. Воспроизводится даже при `--clients claude-code`: глобальная Pi-настройка всё равно выполняется.
- Исправление: сохранять файл и удалять только принадлежащую MB запись из `skills`; остальные ключи и новые пользовательские изменения должны переживать uninstall.
- Пробел тестов: нужен полный install → uninstall с заранее существующими настройками, а не только проверка корректного merge при install.

### R02. Reinstall теряет ссылку на оригинальную резервную копию

- Код: [install.sh:841](/Users/fockus/Apps/skill-memory-bank/install.sh:841), строки 841–844; аналогичный shortcut в `install_file`, строки 743–746. Новый manifest — строки 113–119.
- Сценарий: создать пользовательский `~/.claude/RULES.md` → install → идентичный reinstall → uninstall.
- Факт: после первого install оригинальная backup есть в manifest; после второго `backups=[]`; после uninstall исходный `RULES.md` не восстановлен. Backup остаётся на диске, но больше не связана с uninstall.
- Причина: совпадающий файл проходит shortcut до регистрации существующей backup; manifest собирается заново только из массива текущего запуска.
- Исправление: переносить сохранённую информацию о принадлежащих install резервных копиях между запусками. Проверять восстановление после двух и более установок.
- Это отдельный сценарий от уже известного I-150 о Pi skill.

### R03. Галочка спецификации B ставится по результату проверки спецификации A

- Код: [mb-work-checkbox.sh:111](/Users/fockus/Apps/skill-memory-bank/scripts/mb-work-checkbox.sh:111), строки 111–118.
- Сценарий: создать specs A/B, в обеих Task 1; A имеет `Eval: none` с waiver, B — `Eval: false`. Инициализировать state для A, выполнить `done`, затем вызвать `flip` для Task 1 спецификации B.
- Факт: команда возвращает 0 и меняет DoD B на `[x]`, хотя Eval B не выполнялся.
- Причина: gate проверяет только `phase == done` и `item_no`; `source_path`/`source_topic` не сопоставляются с изменяемым файлом. Номера задач локальны для каждой спецификации.
- Исправление: привязать состояние к каноническому пути источника и номеру задачи; отвергать чужой source даже при совпавшем номере. Добавить отрицательный cross-spec тест.

### R04. Done-gates проверяет пути относительно чужого cwd

- Код: [mb-done-gates.sh:288](/Users/fockus/Apps/skill-memory-bank/scripts/mb-done-gates.sh:288), строки 288–292; аналогично rules gate, строки 267–270.
- Сценарий: во временном git-проекте создать untracked Python-файл с маркером незавершённой реализации. Запустить `mb-done-gates.sh --dir <проект> --mb <банк> --out json` сначала снаружи, потом из каталога проекта.
- Факт: снаружи exit 0, из проекта exit 2 с найденным placeholder. Использовались настоящие scripts, без подмены rules checker.
- Причина: список файлов собирается для `--dir`, но относительные имена передаются checker, запущенному из cwd вызывающего процесса.
- Исправление: запускать проверки в целевом каталоге либо передавать нормализованные абсолютные пути. Один и тот же target должен давать одинаковый verdict из любого cwd.

### R05. Документированный resume drive обнуляет счётчик повторов

- Код: [drive.md:78](/Users/fockus/Apps/skill-memory-bank/commands/drive.md:78), строки 78–83; обещание resume — строки 166–171.
- Сценарий: извлечь и выполнить точный preflight из Markdown, увеличить `cycle` до 2 при `max_cycles=3`, снова выполнить preflight с тем же `MB_WORK_RUN_ID`.
- Факт: `cycle: 2 → 0`. Preflight безусловно вызывает `mb-work-state.sh init` вместо загрузки существующего состояния.
- Следствие: возобновление теряет историю повторов, и лимит max-cycles начинает отсчитываться заново. Это противоречит обещанию продолжить прерванный run с сохранённым счётчиком.
- Исправление: различать создание и возобновление run; при существующем валидном state сохранять cycle, steps и остальные накопленные поля. Проверять resume с тем же run-id на границе лимита.

### R06. Поиск по тегу раскрывает private-блок с угловыми скобками внутри

- Код: [mb-search.sh:68](/Users/fockus/Apps/skill-memory-bank/scripts/mb-search.sh:68), строки 68–72.
- Сценарий: заметка с `tags: [audit]` и строкой `<private>Alice <alice@example.invalid> private-marker</private>`; запустить `mb-search.sh --tag audit <банк>` без разрешения раскрытия.
- Факт: вся строка, включая адрес и `private-marker`, выводится открыто. Все данные примера синтетические.
- Причина: regex `[^<]*` не допускает `<` внутри блока, но ветка всё равно печатает исходную строку. Подобное возникает у адресов, HTML и фрагментов кода.
- Исправление: использовать единый полноценный sanitizer для tag/freetext/index/capture. Добавить случаи вложенной разметки и нескольких блоков на строке, включая незакрытый последний блок.

### R07. Индексатор lessons не удаляет private-контент

- Код: [mb-index-json.py:175](/Users/fockus/Apps/skill-memory-bank/scripts/mb-index-json.py:175), строки 175–176.
- Сценарий: `lessons.md` содержит `### L-001: <private>lesson-private-marker</private>`; выполнить `mb-index-json.py <банк>`.
- Факт: `index.json` содержит приватную строку целиком в `lessons[0].title`. Приватный блок вокруг целой записи также не исключается перед поиском заголовков.
- Причина: `_index_notes` применяет `_strip_private`, `_index_lessons` индексирует сырой текст.
- Исправление: очищать весь lessons-текст до выделения записей; проверить закрытый, многострочный и незакрытый блок. Это нарушение заявленного контракта исключения `<private>` из индекса, а не требование автоматически распознавать любые секреты.

## P2 — функциональные гэпы

### R08. Обычный поиск скрывает публичный хвост после закрытого private-блока

- Код: [mb-search.sh:190](/Users/fockus/Apps/skill-memory-bank/scripts/mb-search.sh:190), строки 190–193.
- Сценарий: после закрытого `<private>text</private>` идёт отдельная строка `Public result: visible-evidence`; поискать `visible-evidence`.
- Факт: возвращается `[REDACTED match in private block]` вместо публичного результата.
- Причина: regex незакрытого блока ищется по исходному тексту и захватывает от первого `<private>` до EOF даже при наличии закрывающего тега.
- Исправление: учитывать только реально незакрытый остаток, сохраняя корректные offsets; проверить публичный текст между блоками и после них.

### R09. Code-context заполняет лимит архивами раньше точного определения символа

- Код: [mb_code_context_core.py:119](/Users/fockus/Apps/skill-memory-bank/scripts/mb_code_context_core.py:119), строки 119–127; ранний лимит text-search — строки 75–89.
- Сценарий: 10 заметок `.memory-bank/notes/` упоминают `process_payment`; в `src/payment.py` находится функция и в graph.json есть точный node. Выполнить code-context для `process_payment` без внешнего semantic-candidates файла.
- Факт: и `candidate_files`, и `recommended_next_reads` содержат только 10 заметок. Исходник отсутствует, warnings пусты.
- Причина: text-search берёт первые 10 совпадений в лексикографическом порядке; они заполняют общий лимит до добавления структурных кандидатов. `.memory-bank`, архивы, backup и зависимости не исключены из этого канала.
- Подтверждение на самом репозитории: запрос `private redaction session recall search memory` предложил `.claude/memory/session-log.md`, `.memory-bank/.index/model.txt` и migration-backups вместо реализации.
- Исправление: ранжировать и объединять кандидатов до финального лимита; резервировать место для точных graph definitions и отделять source от памяти/архивов. Добавить fixture с переполнением конкурирующих упоминаний.

### R10. Первый drive-step попадает в repair вместо implement

- Код: [mb-drive.sh:255](/Users/fockus/Apps/skill-memory-bank/scripts/mb-drive.sh:255), строки 255–258.
- Сценарий: валидная новая goal с одним невыполненным acceptance-пунктом, `init drive 0`, затем `status`/`next` с настоящим default firewall.
- Факт: `next_item="Result file delivered"`, `current_item="(current)"`, `action="repair (current)"`, `gate=1`. Конкретный следующий пункт теряется при выборе действия.
- Причина: полная firewall-проверка включает ещё не выполненный acceptance; этот нормальный для старта факт используется как сигнал красной проверки текущей задачи. Путь `implement` требует green gate, несовместимый с pending acceptance при default-наборе проверок.
- Контракт: REQ-DR-020 требует implement следующего невыполненного пункта, REQ-DR-021 — repair красной текущей задачи. `commands/drive.md:111` дополнительно списывает cycle на repair.
- Исправление: отделить финальную готовность цели от проверки текущей выполненной работы. Интеграционный тест должен проверять первый implement без подмены firewall; нынешний unit-сценарий implement использует green stub.

### R11. Start/done противоречат собственному контракту global storage

- Инструкции: [start.md:43](/Users/fockus/Apps/skill-memory-bank/commands/start.md:43), строки 43–46; [done.md:15](/Users/fockus/Apps/skill-memory-bank/commands/done.md:15) и строки 47–51.
- Факт: при cwd без локальной `.memory-bank` и `MB_PATH`, указывающем на существующий банк, resolver возвращает банк, а точный start-snippet печатает `INACTIVE` и инструкция требует остановиться. Done передаёт явный `.memory-bank`, который перекрывает env/global resolver и направляет команды в другой путь.
- Верхние storage-notes не исправляют противоречащие им конкретные шаги. Фактическое поведение LLM, самостоятельно исправляющей такие инструкции, не оценивалось.
- Исправление: один resolved bank для всех проверок, скриптов и записей. Smoke-тест сценария global-only из каталога пользовательского проекта.
- Пробел тестов: `test_runtime_contract.py:66–80` проверяет лишь наличие слова resolver/global в тексте, поэтому неправильные шаги проходят.

### R12. Canonical uninstall удаляет свои helper-файлы до cleanup

- Код: [uninstall.sh:120](/Users/fockus/Apps/skill-memory-bank/uninstall.sh:120), строки 120–122; последующие `run_texttool`/adapter cleanup зависят от уже удалённого bundle.
- Сценарий: копия checkout установлена в стандартный `~/.claude/skills/skill-memory-bank`; install с проектным Codex adapter, затем uninstall из этого bundle.
- Факт: exit 0, но stderr содержит `adapters/cursor.sh: No such file or directory`; глобальный MB-блок Codex и проектные `.codex`-файлы остаются.
- Причина: manifest.files содержит сам source-каталог; удаление выполняется раньше stripping глобальных инструкций и adapter uninstall. Ошибки подавляются.
- Исправление: загрузить manifest/cleanup-зависимости заранее и удалять bundle последним. Проверять e2e именно из canonical install location, а не только внешнего checkout.

### R13. Init игнорирует документированный `--project-root PATH`

- Код: [mb-init-bank.sh:92](/Users/fockus/Apps/skill-memory-bank/scripts/mb-init-bank.sh:92); собственный пример через пробел — строки 121–122.
- Сценарий: из `work/` вызвать init с `--storage=global --agent=pi --project-root <другой target>`.
- Факт: exit 0; registry содержит `work/`, а не переданный target.
- Причина: поддерживается только форма `--project-root=PATH`; неизвестные аргументы молча пропускаются.
- Исправление: поддержать обе формы либо выдавать usage error; документированный пример обязательно исполнять из cwd, отличного от target.

### R14. Session-memory snippets вычисляют путь относительно shell `$0`

- Инструкции: [mb.md:136](/Users/fockus/Apps/skill-memory-bank/commands/mb.md:136), также строки 124, 156, 183.
- Сценарий: выполнить точную команду conflicts из Markdown в пользовательском проекте: `bash "$(dirname "$0")/../scripts/mb-conflicts.sh"`.
- Факт: exit 127, `No such file or directory`. `$0` принадлежит Bash/zsh, а не Markdown-файлу; recap, consolidate и recent-rebuild используют ту же схему.
- Исправление: брать установленный skill root; сохранять cwd проекта и resolved bank. Нужен smoke-test буквальных snippets.

### R15. Финальный verify не умеет выбирать spec-driven источник

- Инструкции: [mb.md:535](/Users/fockus/Apps/skill-memory-bank/commands/mb.md:535), [done.md:36](/Users/fockus/Apps/skill-memory-bank/commands/done.md:36); обещание plan/spec — [SKILL.md:33](/Users/fockus/Apps/skill-memory-bank/SKILL.md:33).
- Противоречие: рекомендованный `discuss → sdd → work → verify → done` может не создавать plan, но самостоятельный verify ищет только `plans/`, а done требует его лишь при наличии plan. При нескольких планах предлагается брать самый свежий, что не связывает проверку с завершённой работой.
- Следствие на уровне инструкций: нет определённого пути выбрать `specs/<topic>/tasks.md`, либо может проверяться посторонний план. Это не утверждение, что item-level verify внутри work отсутствует.
- Исправление: использовать target/source resolver work для финального verify и явно поддержать закрытие spec-only сессии. Проверить сценарии spec-only и постороннего более свежего plan.

## Что показали тесты

- Основная проверка: **160 pytest passed** — index/privacy/code-context (79), runtime-contract/coverage-omit contracts (81).
- Поиск: **16 Bats passed** — private, tags, archives, argument safety.
- Дополнительный installer-review: **32 pytest passed** — CLI language и global-storage contracts. Wheel и sdist успешно собраны; tracked adapters/scripts/hooks/references присутствуют в wheel.
- Дополнительный runtime-review: **33 pytest passed** — work checkbox/state/eval-proof.
- Дополнительный runtime-review: **184 Bats cases — 183 passed, 1 skipped** (нет `timeout/gtimeout`); drive, drive-command, flow-verify, done-gates, goal-acceptance, plan-source и checkbox.
- Всего в перечисленных наборах: **225 pytest passed; 199 Bats passed, 1 skipped**. Это целевые наборы, не полная матрица.
- Ruff по `mb_code_context_core.py` и `mb-index-json.py`: passed.
- Полная pytest/Bats/host UI матрица в рамках этого аудита не запускалась. Native client conversations не оценивались; выводы о Markdown ограничены текстовым контрактом и исполненными shell-snippets.
- 4 runtime-воспроизведения повторены основным ревьюером через `/tmp/mb-runtime-review-repro.py`: cross-spec flip, done cwd, первый drive-step и resume reset. Все утверждения воспроизведены.

Зелёные целевые тесты не опровергают находки: отсутствуют отрицательные проверки identity/source, другие cwd, вложенная разметка, repeated-install → uninstall и resume roundtrip. Это главный общий гэп тестирования. Простая проверка наличия слов в инструкциях не доказывает, что описанный workflow исполним.

## Уже известные проблемы и порядок исправления

В [предыдущем ревью Sprint 1](2026-09-13_sprint1-review.md) уже зафиксированы I-194/I-195/I-196 и I-208: обход через пустую spec, сохранность архивирования и красная общая батарея. Они не пересчитаны здесь как новые findings. Раздувание инструкций уже стоит в cost-diet Sprint 3; это известный долг, а не новая находка данного аудита.

Рекомендуемый порядок: (1) R01/R02 — сохранность пользовательских данных при install/uninstall; (2) R03–R05 — корректность gates и resume; (3) R06–R08 — общий sanitizer и privacy-регрессии; (4) R09/R10 — реальная работа retrieval/drive; (5) R11–R15 — исправить и исполнять документированные сценарии. Параллельно требуется закрыть уже известные блокирующие находки, не принимая текущую зелёную узкую батарею за release gate.

## Артефакты воспроизведения

- [Лог installer/uninstaller с пользовательскими файлами](</var/folders/vj/d87hwmp15j1flcqptvqxymhr0000gp/T/mb-install-review-ccbnbo1j/uninstall.log>).
- [Лог canonical uninstall](</var/folders/vj/d87hwmp15j1flcqptvqxymhr0000gp/T/mb-canonical-uninstall-review-3g_lil99/uninstall.log>).
- [Скрипт четырёх runtime-воспроизведений](/tmp/mb-runtime-review-repro.py).

Проверки используют временные каталоги и синтетические данные. Настоящие настройки клиентов не изменялись. Автообновление graph при первом code-context вызове изменило два изначально чистых generated-файла; эти два артефакта возвращены к исходным байтам, копии результата сохранены во временном каталоге. Исходники скила не изменены.
