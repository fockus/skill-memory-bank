# Red-якоря Eval: грабли сигнатур настоящего провала

Норма X-05 (S2 REQ-054/055): gated `Eval:` несёт `output~:` — ERE настоящего провала. Измеренные грабли:

- `bats <missing>` → exit 1 + `not ok 1 bats-gather-tests` — **тот же exit-код, что настоящий провал**; exit-only якорь невалиден. ERE без negative lookahead → якорить положительный именованный префикс теста (конвенцию имени фиксировать в Testing).
- `pytest <missing>` → exit 4; настоящий провал → exit 1 + `FAILED <nodeid>`; отсутствующий подмодуль существующего пакета → exit 2 + `ModuleNotFoundError: No module named '<pkg>.<mod>'` — но **только** при `import pkg.mod`/`from pkg.mod import X`; форма `from pkg import mod` даёт `ImportError: cannot import name …`.
- Симуляция провала при верификации якоря обязана следовать конвенции репо (`sys.path.insert(0, REPO_ROOT)`, `tests/pytest/test_cli.py:19-22`), иначе ошибка обрезается до `No module named '<pkg>'` и якорь ложно не матчится.
- Команда без вывода неякорима в принципе (`[ … ] && …` падает молча) — добавить наблюдаемую сигнатуру в саму команду (`echo "reason=…"; false`), не меняя семантики. `grep -c` при нуле совпадений даёт exit 1 — в `&&`-цепях нужен `|| true`.
- Направление отказа безопасное: невоспроизводимый якорь = «нераспознанный red», гейт требует чинить тест; фальшивый green невозможен.
- **Markdown-таблица убивает ERE-якорь** (круг 3, CPR-D): в ячейке таблицы пайп экранируется `\|`, а `\|` в POSIX ERE матчит литерал `|` — альтернатива `(a\|b)` не сматчит настоящий провал никогда. Правило: Eval-декларации в design.md держать fenced-списком, byte-identical строкам tasks.md; byte-identity — гейт валидатора (S2-C8 №6).
- Голый GNU `timeout` непереносим (нет на стоковом macOS) — bounded-run обёртка timeout→gtimeout→Bash-watchdog (прецедент `mb-work-codex-preflight.sh:46-65`).
