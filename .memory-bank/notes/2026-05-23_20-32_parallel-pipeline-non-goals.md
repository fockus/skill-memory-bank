# parallel-pipeline — non-goals snapshot (S5 of harness-upgrade)

Date: 2026-05-23 20:32

## What was done

Зафиксирован первоначальный список non-goals в дизайне `parallel-pipeline` (S5). Часть пунктов потом перешла в Goals по решению пользователя — список сохранён как «контракт первого среза» и стартовая точка для будущих расширений.

## Non-goals snapshot (verbatim)

- ❌ Cross-plan параллелизм (worktree per plan) — отдельный sub-project, появится в S6 если потребуется. **[Позже перешло в G8 — реализуется сразу]**
- ❌ Менять механику existing `/mb work` без флага — full backward compat.
- ❌ Менять схему `severity_gate` (`mb-work-severity-gate.sh`).
- ❌ DAG cycles вне `loop_target` (например, фаза A зависит от себя через сложную тропу). Только явные loops.
- ❌ Динамическое создание новых ролей по ходу — все роли определены в `pipeline.yaml` до запуска.
- ❌ Real-time UI / progress bars — только текстовый stderr log.
- ❌ Полная замена движка `mb-pipeline-engine.py` на что-то ещё (Approach B / A откладываем).
- ❌ Шаринг engine'а с claude-skill-build (только schema).

## New knowledge

- Non-goals — это контракт: пункты остаются за рамками первого среза, но фиксируются как **возможные** будущие расширения (см. идеи I-036..I-042 в `backlog.md`).
- Schema-совместимость с claude-skill-build — это про **формат yaml** (одинаковые ключи `phases/role/parallelism/loops/gate`), но **не про общий engine** — каждый скил имплементит свой исполнитель.
- Worktree модель: per plan, не per item. Внутри плана items живут в shared worktree (plan дисциплинирует scope).
- Cherry-pick conflict policy — fail-fast в первой итерации; auto-resolve через mb-architect — отдельная идея (I-040).
