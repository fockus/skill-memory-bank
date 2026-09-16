# Исправление 15 находок аудита Memory Bank — 2026-09-14

**Состояние:** все **15/15** находок исправлены; **6/6** этапов прошли независимую функциональную проверку. Финальный общий pytest: **2614 passed, 1 skipped**, exit 0.

Исходный аудит: [15 замечаний R01–R15](2026-09-13_skill-audit.md), baseline `f3e23f1c18033e40b0d584d26a7b64bd96dc9422`. Работа выполняется в текущем checkout. Чужие незакоммиченные изменения банка сохранены; commits, push и установка в реальные настройки клиентов не выполнялись.

## Находка → исправление → проверка

| ID | Исправление | Регрессия |
|---|---|---|
| R01 | Uninstall сохраняет Pi settings и удаляет только MB skill из списка | Preexisting settings + изменения после install переживают reinstall/uninstall |
| R02 | Живые backup mappings переносятся в следующий manifest | Original RULES, command и Pi skill восстанавливаются после повторных установок |
| R03 | Init сохраняет canonical source; checkbox проверяет неизменный source + item | Чужая spec, смена cwd, ambiguous/unbound legacy и symlink-retarget отказывают; корректный alias работает |
| R04 | Rules/placeholder checks исполняются в `--dir`; test-runner получает путь отдельным аргументом | Одинаковый verdict внутри/снаружи target с пробелами; TODO найден настоящим checker |
| R05 | Drive preflight сохраняет существующие state/budget/telemetry; создаёт только отсутствующие компоненты | Cycle/steps/spent/limits не обнуляются; corrupt state и конфликтующие лимиты отказывают |
| R06 | Tag/freetext search используют общий parser private spans | Вложенная разметка, несколько и незакрытые блоки скрываются |
| R07 | Lessons очищаются до извлечения записей; source bundle импортируется до старого installed package | Приватные заголовки/записи не входят в index; older-package CLI smoke проходит |
| R08 | Redaction учитывает реальные границы блоков | Публичный текст после и между закрытыми блоками остаётся виден |
| R09 | Exact qualified/short graph definitions получают приоритет до лимита; memory/cache dirs исключены из source text-search | 10+ notes/semantic hits/одноимённых methods не вытесняют точный source; semantic-only и bounds сохранены |
| R10 | Pending acceptance исключается только из промежуточной проверки текущей работы | Первый шаг — concrete implement; настоящий red — repair; stop_success требует полного firewall |
| R11 | Start/done используют один resolved bank и установленный skill root во всех затронутых действиях | Реальные Markdown fences работают при global-only bank и registry lookup без local shadow |
| R12 | Cleanup выполняется до удаления canonical bundle; mappings прочитаны заранее | Uninstall из canonical install location удаляет project adapters/MB markers и восстанавливает RULES |
| R13 | Init поддерживает обе формы value options и отвергает неверные аргументы до записи | Explicit target из другого cwd, paths with spaces, missing/empty/unknown arguments |
| R14 | Recap/conflicts/consolidate/recent-rebuild используют `SKILL_DIR`, а не shell `$0` | Буквальные snippets запускаются из пользовательского проекта |
| R15 | Verify выбирает explicit/current source через work helpers; verifier понимает spec tasks | Spec-only, unrelated newer plan, parallel current run и prompt loading без Claude install |

## Проверки и TDD

Все первоначальные поведенческие регрессии наблюдались RED до исправлений. Для команд проверены исполняемые shell-фрагменты; выбор и загрузка prompt-файлов дополнительно покрыты контрактами инструкций. Это не симуляция всех возможных решений LLM.

- Installer/init: 18 новых cases; 74 существующих Bats прошли в изолированном HOME и copied bundle.
- Privacy/index: первоначально 17 failed / 7 passed → 24 passed; после packaging regression итоговый subset — 75 passed. Связанные search/tag/archive/security Bats — 37 passed.
- Drive: 18 failed / 3 passed → 21 passed. Связанные Bats — 217 passed, 1 skipped (нет timeout/gtimeout).
- Completion/context: cross-source/cwd, canonical legacy и symlink случаи наблюдались RED; focused state/eval subset — 80 passed, related Bats — 92 passed. После дополнительных крайних случаев completion/context/checkbox — 42 passed; финальный code_context — 14 passed; checkbox Bats повторно 3/3.
- Commands: start/done/snippets/verify initially 12 failed; после расширения — 16 контрактов. Commands + tooling-core — 22 passed; agreements docs Bats — 17 passed.
- Полный первый интеграционный pytest: **2602 passed, 2 failed, 1 skipped**. Оба падения устранены: регистрация новых helpers в `SKILL.md` и конфликт имени fixture с v1 naming guard. Повторный subset doc-counts/naming/completion — **37 passed**.
- Финальный полный pytest по стабильным исходникам: **2614 passed, 1 skipped in 578.09s**, exit 0. Новые крайние случаи также вошли в этот прогон.
- Независимый verifier проверил все 6 этапов, нашёл остаточные cwd/legacy/symlink/qualified-name/prompt-path проблемы, затем подтвердил их исправления. Открытых функциональных замечаний в scope R01–R15 не осталось.
- Финальные Ruff, ShellCheck (`-S warning`) и `git diff --check` прошли.
- Wheel и sdist собраны без установки build dependencies; оба содержат `private.py`, `mb-drive-preflight.sh` и `mb_work_source.py`.
- Wheel установлен в отдельный `/tmp` target: реальные CLI index/private search и source-bound init/done/checkbox прошли smoke-проверку. Настройки установленных клиентов не использовались.

## Воспроизводимые команды

```bash
python3 -m pytest hooks/tests/ tests/pytest/ -o 'python_files=*_test.py test_*.py' -q --tb=short
python3 -m pytest tests/pytest/test_audit_completion.py tests/pytest/test_audit_command_contracts.py tests/pytest/test_audit_drive.py tests/pytest/test_audit_install_roundtrip.py tests/pytest/test_audit_privacy.py tests/pytest/test_code_context.py -q
python3 -m build --wheel --sdist --no-isolation --outdir /tmp/mb-audit-final-build
```

## Практические ограничения

- Старые work states без надёжной source identity требуют повторной инициализации и проверки с явным `--source-path`. Неоднозначное состояние больше не даёт право поставить галочку.
- Для resume drive нужен исходный run id и тот же parallel mode; новые лимиты не переписывают уже израсходованный бюджет.
- Планы используют обычные stages без spec Eval clauses. Их RED→GREEN подтверждён pytest/Bats; work-state честно выводит `Eval unverified` для отсутствующей декларации, а не подменяет этим результат тестов.
- Coverage не измерялось; вся Bats-батарея репозитория не запускалась, выполнены связанные наборы. Унаследованные size debt и backlog I-194/I-195/I-196/I-208 не относятся к этим 15 находкам.
- G-001 (`sdd-vision-pipeline`) остаётся paused; этот отчёт не объявляет завершение той цели.

Планы: [data safety](../plans/done/2026-09-13_fix_skill-audit-data-safety.md), [runtime/commands](../plans/done/2026-09-13_fix_skill-audit-runtime.md).
