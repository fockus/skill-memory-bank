# Ремедиация круга 3 spec-ревью группы sdd-vision-pipeline

> Дата: 2026-07-18 · План: [plans/2026-07-18_fix_spec-group-round3-remediation.md](../plans/2026-07-18_fix_spec-group-round3-remediation.md) (исполнен через `/mb work`, 6 стадий).
> Вход: [2026-07-17_review_spec-group-round3.md](2026-07-17_review_spec-group-round3.md) — 73 технические находки (7 critical, 60 major, 5 minor, 1 nit) + 2 смысловые; raw: `2026-07-17_review_spec-group-round3-raw/`.
> Схема: **4 Opus-фиксера, две волны по 2** (владельцы контрактов → потребители), непересекающиеся файловые пакеты, независимая верификация оркестратором после каждого фиксера, кросс-пакетные запросы — только через оркестратора владельцу.

## Итог

**Все 75 находок закрыты: 73 fixed (включая обе смысловые — AGR-020/021) + cross-package-хвосты CPR-A…G, X-03, X-04 исполнены владельцами.** Обоснованные отказы от буквы `proposed_fix` (2) приняты по якорным цитатам владельцев. Финальная батарея: **10/10 спек GREEN** (9 группы + новый S9), 124 сценария child (test_id уникальны, ASCII), 62 задачи child + 10 umbrella парсятся, cross-slice grep обеих сторон контрактов без расхождений, изменённые red-якоря проверены двусторонне. Изменения НЕ закоммичены.

## Волны и пакеты

| Фиксер | Пакет | Позиции | Верификация оркестратора |
|---|---|---|---|
| F1 owners-state (волна 1) | umbrella + S4 | 7 + 11 + D-14/AGR-021 → **fixed** (5 позиций частично как CPR наружу) | батарея ✓, owner-marker/rmdir в обоих design ✓, `unconfirmed_ice=`/REQ-013/сценарий 16 ✓, PIPE_BUF только как опровержение ✓, якоря не менялись (9 = 9) ✓ |
| F2 owners-norms (волна 1) | S2 + S1 | 9 + 6 → **fixed**; + CPR-D, X-03 | батарея ✓ (21+20 сценариев, 9+6 задач), eval-red/eval-green без caller-флагов ✓, `<private>` не подавляет скан ✓, byte-identity Eval design↔tasks (diff пуст) ✓, якоря A/B ✓ |
| F3 consumers-west (волна 2) | S7 + S3 + S5 | 9 + 6 + 8 + AGR-020 → **fixed** (R3-002 — с обоснованным отказом от буквы, якоря S2:124-125/338-342 подтверждены); + CPR-B/C/D/E/G | батарея ✓ (7+16+10 сценариев), Cursor 4-й хост ✓, `mb_adapt_bounded_run` вместо GNU timeout ✓, 4 новых якоря S7 A/B ✓, `svp_group_ordering.json`/escalations-lock/рёбра к S4 ✓ |
| F4 consumers-east (волна 2) | S6 + S8 | 10 + 7 → **fixed**; + CPR-A/B | батарея ✓ (11+12 сценариев), bootstrap≠stale_run ✓, plan-авторитетность apply ✓, grandfather `layers=legacy` ✓, evidence-схема с `cmd_sha256` ✓, якорь `test_missing_block_is_legacy` A/B ✓ |

Полные per-finding таблицы — в отчётах фиксеров (транскрипт сессии); статусы сведены и перепроверены оркестратором построчно.

## Cross-package запросы (все исполнены и верифицированы)

- **CPR-A → S8**: закрытая evidence-JSON схема red-прогона + red-gate перед verify.
- **CPR-B → S3/S5/S6**: task-level `Blocked-by`-рёбра к S4#1/#2, fallback-фразы удалены.
- **CPR-C → S5**: сериализация эскалационного журнала под `mb_lock_acquire`, PIPE_BUF-тезис снят.
- **CPR-D → S2/S7**: `\|`→`|` в `output~:`-ERE; §Eval declarations переведены из markdown-таблиц в fenced-списки byte-identical tasks.md + гейт byte-identity в валидаторе (корень класса дефектов).
- **CPR-E → S7/S5**: X-01/X-02/X5-01 → SATISFIED, stale-риски сняты.
- **CPR-F → roadmap** (оркестратор): «57 child полный v2; 9(10) umbrella — bootstrap legacy/meta».
- **CPR-G → S3**: выравнивание под авторитетный S4-C2 (created из context, `ice=null` legacy_tail, общая фикстура).
- **X-03 → S1**: детерминированный алгоритм классификации scannable (readable→NUL→magic→UTF-8).
- **X-04 → umbrella**: REQ-022 dual-ownership (Task 4 spec-time + Task 7 runtime).
- **Ребро Task 6→Task 3 (umbrella)** + **интеграция S9** (строка таблицы, DAG S9←S2, мета-задача Task 10 с delegate-гейтом; гейт проверен двусторонне: as-is `delegate_incomplete spec=svp-spec-review-loop open_dod=10` exit 1, при закрытых DoD — exit 0).

## Смысловые решения пользователя

- **AGR-020**: Cursor включён в полный режим intra-session параллели S3 (четырёхостовый scope, D-07 восстановлен; честная деградация до появления транспорта).
- **AGR-021**: `ice_confirmed` больше не декоративен — `unconfirmed_ice=<csv>`-ворнинг в ordering + эскалация подтверждения пользователю + флип оркестратором (S4-C2, REQ-013, сценарий 16); порядок не блокируется.

## Финальная батарея (2026-07-18, один прогон)

```
GREEN sdd-vision-pipeline    (1 сценарий,  10 задач)   — spec-validate базовый
GREEN svp-interview-upgrade  (20 сценариев, 6 задач)
GREEN svp-brief              (7 сценариев,  4 задачи)
GREEN svp-roadmap-backlog-db (16 сценариев, 9 задач)
GREEN svp-sdd-core           (21 сценарий,  9 задач)
GREEN svp-docs-wiki          (11 сценариев, 7 задач)
GREEN svp-adapt-escalation   (10 сценариев, 5 задач)
GREEN svp-parallel-engine    (16 сценариев, 10 задач)
GREEN svp-contract-test-loop (12 сценариев, 8 задач)
GREEN svp-spec-review-loop   (11 сценариев, 5 задач)   — S9, ревью waived (AGR-022)
итог: 10 GREEN / 0 RED · EARS 10/10 · парсер задач 10/10 · cross-slice grep чист
```

## Нормы, введённые/уточнённые кругом 3

1. Lock-reclaim: owner-marker `owner.<token>` + targeted `rmdir` мёртвого токена; `rmdir <lock>` только на пустом; никаких `mv`/`rm -rf` (umbrella Interface 2 / S4-C6, потребители выровнены).
2. Eval-декларации в design.md — fenced-список, byte-identical строкам tasks.md; markdown-таблица запрещена (экранирование `\|` ломает ERE); byte-identity — гейт валидатора.
3. work-state `eval-red --cmd-file --output-re [--expected-exit]` / `eval-green --cmd-file`: helper сам исполняет и судит; caller-флаги вердикта удалены (фальсификация невозможна по построению).
4. Scope-грамматика — restricted glob (литералы + `*` в сегменте + сегмент `**`), остальное malformed.
5. Секрет-политика: `<private>`/`mb-secret-ok` не подавляют скан; plaintext-секрет не достигает git-tracked файлов; классификация scannable детерминирована (readable→NUL→magic→UTF-8).
6. Переносимость: никакого голого GNU `timeout` — `mb_adapt_bounded_run` (timeout→gtimeout→Bash-watchdog).

## Следующий шаг

Группа готова к **контрольному кругу 4** (по команде пользователя; ревьюерам передавать реестр принятых отклонений — теперь это штатная механика S9). S9 сам не ревьюился (AGR-022) — его первый боевой прогон делает dogfooding по этой же спеке.
