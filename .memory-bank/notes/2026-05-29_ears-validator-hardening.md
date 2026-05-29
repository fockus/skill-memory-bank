# EARS-валидатор и spec-checking — что ужесточить

Date: 2026-05-29

## Контекст

Замечено во время реального прохода `/mb discuss` → `context/<topic>.md` (внешний проект-потребитель скила). Пайплайн `discuss → context → sdd → plan → traceability` работает и полезен, но проверка спеки **поверхностная**. Фиксирую улучшения, чтобы не забыть.

## Что улучшить (`scripts/mb-ears-validate.sh` + смежное)

1. **Per-pattern structural regex вместо «триггер + shall».** Сейчас валидатор требует лишь наличие слова `The|When|While|Where|If` И слова `shall` как отдельных токенов в строке `- **REQ-NNN** ...`. Строка `The when shall while` проходит. Усилить до реальных шаблонов EARS с порядком слов:
   - Ubiquitous: `^The .+ shall .+`
   - Event-driven: `^When .+, the .+ shall .+`
   - State-driven: `^While .+, the .+ shall .+`
   - Optional: `^Where .+, the .+ shall .+`
   - Unwanted: `^If .+, then the .+ shall .+`
   (REQ-строка должна матчить ровно один шаблон).

2. **Atomicity warning.** Предупреждать, если в одной REQ-строке >1 `shall` — это составное требование, его надо разбить (атомарность → тестируемость).

3. **REQ-ID uniqueness/monotonic check.** Линт на дубли `REQ-NNN` и пропуски в нумерации (сейчас уникальность нигде не проверяется на этапе discuss/sdd).

4. **Ранний REQ→task coverage lint.** Сейчас покрытие REQ задачами проверяется только в `/mb verify`. Дешёвый ранний линт (каждый REQ упомянут хотя бы в одной `tasks.md` строке `**Covers:** REQ-NNN`) сэкономил бы цикл.

5. **Traceability drift-resistance.** `mb-traceability-gen.sh` на regex молча промахивается при дрейфе формата (например, REQ написан не bullet'ом). Добавить warning, если найдены REQ-подобные строки, не попавшие в матрицу.

## Почему это note, а не сразу фикс

Дыры не критичные — валидатор ловит главное (отсутствие триггера/`shall`). Это quality-of-life ужесточение, бэклог-кандидат. Заведено как **I-062** в `backlog.md`.

## Связано

- `scripts/mb-ears-validate.sh`, `scripts/mb-traceability-gen.sh`, `commands/discuss.md`, `commands/sdd.md`
- backlog **I-062**
