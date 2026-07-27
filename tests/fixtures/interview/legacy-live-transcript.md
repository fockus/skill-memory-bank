# Interview transcript: sdd-vision-pipeline (2026-07-17)

FROZEN FIXTURE (r5 review [8]) — a minimal transcript in the LEGACY shape, kept
here so the legacy grammar is tested against bytes that never change. It carries
exactly the two relaxations `--legacy-live-fixture` exists for:

  * an answer given as `Ответ голосом (суть): «…»` instead of `**A<N>.** …`;
  * rejected alternatives collected in one file-level section instead of a
    per-block rejection marker inside every Q-block. (This paragraph must not
    contain that marker literally — the file-level rule scans the whole file.)

Both must make it FAIL the strict grammar and PASS the legacy one — that
difference is the whole content of the flag.

## Q&A

**Q1 (первый вопрос).** Что делаем?
**A1.** «Вариант 1 (Recommended)» → **D-01**.

**Q2 (второй вопрос).** Первая формулировка отклонена пользователем для уточнения. Ответ голосом (суть): «делаем вариант 2, потому что так дешевле» → **D-02**.

**Финальный гейт.** Есть ли что добавить?
**Ответ.** «Всё ok».

## Отклонённые альтернативы (сводно)

- вариант 3 — дороже по токенам;
- вариант 4 — не покрывает edge-сценарии.
