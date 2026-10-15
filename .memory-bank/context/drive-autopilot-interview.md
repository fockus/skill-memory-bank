# Interview transcript: drive-autopilot (2026-10-15, AGR-099 follow-up)

## Q&A

**Q1 (purpose).** Where does the autopilot start: hybrid (goal.md; items with a plan/spec go to /mb work, items without one are planned by drive, a large spec is approved by the user), execute-only, or fully autonomous?
**A1.** "A" — hybrid. → **D-01**. Отклонено: execute-only; fully autonomous discuss→sdd→plan.

**Q2 (approval).** Where is the "large" boundary that makes drive ask for spec approval: the existing effort tiers, every new plan, or never?
**A2.** "да, берем готовую шкалу A" → **D-02**. Отклонено: stop on every plan; never stop.

**Q3 (decision layer).** When does drive go parallel through /mb team vs serial /mb work: mechanically (≥2 independent items; every track runs through /mb work), model decides, or only with --team?
**A3.** "берем A". Added: QA stage in the plan/spec DoD by default, can be disabled via prompt, flag or pipeline; a small step after plan/spec writes QA test cases from requirements, run after execution; a plan step may follow a spec; the verifier checks against plan and spec; the reviewer sees plan and spec; in drive everything is planned at the start and then the pipeline moves automatically. → **D-03**, **D-04**. Отклонено: model decides; --team only.

**Q4 (QA default).** QA on by default contradicts AGR-098 (off): on by default with --no-qa / prompt / qa.enabled: false, QA off without qa/README.md; or stop without README; or keep off and force it in drive?
**A4.** "да A" → **D-12** (first form, AGR-100). Отклонено: stop without qa/README.md; off by default.

**Q5 (test cases).** Who writes the cases and when: mb-qa right after plan/sdd from requirements into qa/test_cases/<topic>/ with covers: REQ; the planner itself; or after execution?
**A5.** "A + дополнение: можно отключить прогон кейсов на уровне verify и например прогонять их только в самом конце после всего воркфлоу." → **D-05**. Отклонено: planner writes cases; cases after execution.

**Q6 (sources).** What do verifier, reviewer and judge receive: one bundle (spec, plan wrapper, QA report) with per-source verifier reports, or paths only?
**A6.** "да A" → **D-06**. Отклонено: paths only.

**Q7 (acceptance).** How is goal acceptance decided (I-267): from evidence (linked plans/specs closed, verifier PASS, QA green, or check: command), or manual ticks checked by the verifier?
**A7.** "да A" → **D-07**. Отклонено: manual ticks plus verifier.

**Q8 (limits).** Item cycles in /mb work; drive watches stall with one automatic architect pivot, then stop; budget from real tokens — or stop on the first stall?
**A8.** "да A" → **D-08**. Отклонено: stop on first stall.

**Q9 (team).** Cancelled dependency → blocked → stop_human; red goal/flow at the end → stop_human; stop_human alone; fix I-275..I-280 — or auto-cancel dependents?
**A9.** "a" → **D-09**. Отклонено: auto-cancel dependents and continue.

**Q10 (resume).** Drive state in <bank>/.drive/current.json with --resume, unified path resolution, four hosts with serial fallback — or Claude Code and Codex first?
**A10.** "A" → **D-10**. Отклонено: two hosts first.

**Q11 (slicing).** Three specs in [SPEC:autopilot] (S1 planning-qa-sources and S2 team-completion in parallel, then S3 drive-autopilot), or one spec?
**A11.** "давай как ты предлагаешь, только важное дополнение: мы недавно доработали мемори банк, чтобы он был более легковесный и быстрее решал задачи, так как модели поумнели. Важно эту логику не сломать; чтобы не было слишком мелкого дробления планов и слишком частых проверок — на это уходят токены и время." → **D-11**. Отклонено: one spec.

**Q12 (QA cost).** QA default by tier: off for small, on for standard (key user paths), on for large/extra (per REQ) — or on everywhere?
**A12.** "да A" → **D-12** (refined, AGR-101). Отклонено: on for every tier.

**Q13 (failures).** QA blocked by the environment during drive: retry once then stop_human qa-blocked?
**A13.** "нужно попробовать еще раз, если не получится пропустить этап и в конце к нему вернуться еще раз; если и там не получится, то в конце, когда все готово, пишем отчет что сделали и вопрос что будем делать — stop_human qa-blocked:<причина>, но задача при этом выполнена в остальном." → **D-13**. Отклонено: stop at the first failure.

**Финальный гейт.** Confirm the decision summary D-01..D-13, NFR-001; anything to add?
**Ответ.** "да"
