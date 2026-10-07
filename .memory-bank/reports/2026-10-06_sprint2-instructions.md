# Sprint 2 «CLAUDE.md» — verification notes (2026-10-06)

## Stage 2 · `/mb init --full` template render (W4)

Rendered `references/claude-md-template.md` for a tmp Python project (pyproject: fastapi + sqlalchemy, ruff, uv):
37 lines, 0 unfilled `{PLACEHOLDER}`s, sections Project → Commands → Stack & conventions → Architecture →
Project rules → Memory Bank. Rendered deterministically (placeholder substitution) — the LLM-driven `/mb init --full`
flow fills the same placeholders; a live interactive run in a fresh session is still recommended.

## Stage 3 · CLAUDE-GLOBAL lines dropped on purpose (W3)

17 non-blank lines of the 84-line baseline are not present verbatim anywhere in SKILL.md / references / rules.
None carries a rule that is lost — each is a heading or a duplicate whose meaning lives elsewhere:

| Baseline line(s) | Content | Where the meaning lives now |
|---|---|---|
| 36, 45, 48, 58, 65, 70, 76, 81 | section headings / framing sentence | removed with their sections; "Detailed rules:" pointer kept |
| 40 | TDD + No placeholders restated | `# Engineering rules` (once) · `rules/RULES.md` § Coding Standards → General |
| 46 | Testing Trophy + Coverage restated | `# Engineering rules` (once); static-analysis part kept as a bullet |
| 49 | Plans restated (second copy) | `# Engineering rules` → Plans · `rules/RULES.md` § Session Pipeline → Phase 2 |
| 54 | three-in-one + design contract | SKILL.md intro · `rules/RULES.md` § Design contract |
| 56 | subagents roster line | `rules/RULES.md` § Subagents · `references/agents.md` |
| 74 | pointer to code-graph reference | the text itself now lives in `references/code-graph.md` |
| 77, 78, 79 | rule profiles · `<private>` · native auto-memory | `rules/RULES.md` § Rule profiles, § Private content, § `.memory-bank/` vs native auto-memory · `references/privacy-and-capture.md` |

## Verifier follow-ups fixed

- ruff E741 in `tests/pytest/test_claude_md_template.py` — renamed.
- Hollow mid-test `[[ … ]]` asserts (bash 3.2) → `assert_substring`/`refute_substring`:
  `tests/bats/test_mb_agree_block_budget.bats` (6), `tests/bats/test_migrate_structure.bats:99` (1).
  Mutation proof: changing the expected `AGR-004: Replacement.` makes test 5 fail; restored → green.

## Stage 4 · repo CLAUDE.md / AGENTS.md budget (P2, P3)

- Guard `tests/pytest/test_repo_instruction_budget.py`: `AGENTS.md` ≤ 32 768 B (Codex default
  `project_doc_max_bytes`; skipped when the gitignored file is not rendered), `CLAUDE.md` ≤ 200 lines and ≤ 10 240 B.
  2 passed; with the limits lowered to 1 000 B / 50 lines both tests fail.
- Codex limit source: `project_doc_max_bytes = 32768` in
  https://github.com/openai/codex/blob/main/codex-rs/config/defaults.toml; the docs say "32 KiB by default"
  (https://developers.openai.com/codex/guides/agents-md).
- Now: `AGENTS.md` 7 987 B, `CLAUDE.md` 8 352 B / 82 lines. Before/after table: `reports/2026-10-06_agents-md-baseline.md` § Stage 5.
- `scripts/mb-drift.sh .`: `drift_warnings=1`, only `plan_vs_git` (12 plans shipped-but-not-closed). The HEAD
  snapshot (`git archive HEAD`) gives the same warning and the same 12 plans, so there are no new findings.
