# /mb team, волна 1: бриф исполнителей

- **Дизайн:** `.memory-bank/specs/mb-team/` — `requirements.md`, `design.md`, `examples.md`.
- **План:** `.memory-bank/plans/2026-10-10_feature_mb-team.md`.
- **Решения Антона:** AGR-097 в `.memory-bank/agreements.md` скила (в Harness это AGR-148 и AGR-150).
  - Трек размера standard по умолчанию: прямой исполнитель, TDD, plan-verifier в конце, ревью трека нет.
  - Мёртвый замок (обёртка и дочерний процесс мертвы, хост тот же, совпадают PID и время старта) снимает первый в очереди и пишет об этом на доске.
  - Уровень `medium` в ревью необязательный, лимит по умолчанию 0.
  - `mode: work` бывает двух видов, выбирается атрибутом трека: `orchestrated` (цикл `/mb work` ведёт оркестратор) или `light` (агент трека сам проходит этапы, верификатор и ревью запускает оркестратор).

## Правила

- **Где работаем.** Корень репозитория — `~/.claude/skills/memory-bank`. Все `scripts/mb-*.sh` запускать только из корня: запуск из подкаталога создаёт вложенный банк.
- **Чужие правки.** В дереве лежат незакоммиченные правки параллельной сессии done-gates:
  - `commands/mb.md`, `commands/done.md`, `references/scripts.md`, `references/planning-and-verification.md`;
  - `scripts/mb-test-run.sh`, `scripts/_test_select.sh`, `scripts/mb-done-gates.sh`, `scripts/mb-review-cache.sh`, `scripts/mb_rules_check_arch.sh`;
  - `hooks/mb-flow-closure-guard.sh`, `adapters/*`, `agents/mb-manager.md`, `CLAUDE.md`.

  Эти файлы не трогать. Если без правки в них не обойтись, запиши HANDOVER на доску и сообщи оркестратору.
- **Порядок работы.** Сначала тест, который падает, потом код. Тесты пишем так, как принято в скиле: bats в `tests/`, pytest для Python. Линтеры проекта (shellcheck, ruff) должны быть чистыми.
- **Язык.** Тексты в репозитории на английском (AGR-085 скила).
- **Чего не делать.** Не коммитить: коммитит оркестратор. `install.sh` не запускать. `~/.claude` вне репозитория скила не трогать.
- **Доска.** `.memory-bank/COORDINATION.md` скила, через `scripts/mb-coord.sh` из корня. Свой STATUS пиши туда.
- **Отчёт.** `.memory-bank/reports/mb-team/<трек>.md`. В нём:
  - файлы;
  - какие тесты падали до правки и проходят после — с выводом;
  - что осталось.
- **Объём.** Делай свой этап плана и его DoD, ничего сверх. Если контракт с соседним этапом нужно поменять, это HANDOVER и решение оркестратора.

## Волна 2 (добавлено после волны 1)

Готовы этапы 1–7:
- A: T-GUARD + T-COORD;
- B: T-LOCK;
- C: T-CFG + T-RENDER;
- D: T-VCS;
- E: T-ENGINE.

Отчёты: `.memory-bank/reports/mb-team/{A..E}.md`. Решения оркестратора по их отступлениям приняты, ACK записаны на доске:
- пресет large = work + линзы (решил Антон); design.md §4 приводит в соответствие T-DOCS;
- поля C1/C2 добавлены (`work`, `models.lens`, `title`/`dod` трека, `title` команды). **T-STATE обязан сохранять `title` и `dod` в `track add`**;
- B добавил отдельный модуль `scripts/mb_lock_resource.py`, его нужно вписать в install manifest (T-WIRE);
- полярность `stop_threshold.check`: ненулевой код = порог нарушен, как у `preconditions.check`. Это фиксирует T-DOCS в контракте C3;
- строки `mb-lock.sh`, `mb_vcs.sh`, `mb-team*` в `references/scripts.md` — этап T-DOCS. Порядок с сессией done-gates согласовывается через доску.

## Волна 3: что передали T-DOCS и T-WIRE (после G)
- T-REVIEW готов (G.md). Три модуля `mb_team_review.py`, `mb_team_review_core.py`, `mb_team_review_external.py` и `mb-team-review.sh` — в install manifest (T-WIRE) и в `references/scripts.md` (T-DOCS).
- T-DOCS: в схему `previous_issues` в `agents/mb-reviewer-lead.md` добавить поле `id` (бриф цикла его требует).
- `test_doc_counts.py::test_skill_md_script_table_lists_all_scripts` красный до волны 2 (не хватает 20 скриптов): закрывает T-DOCS.
- `next` → `stop_human review-cycles`, `reviews[]`, `init --team-review` — передано T-STATE (F).
