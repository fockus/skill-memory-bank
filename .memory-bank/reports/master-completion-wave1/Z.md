# Track Z report — Stage 19 regressions

STATUS: DONE_WITH_CONCERNS

All 15 failing tests now pass. Evidence: after the fixes, test_global_prompt_guard (10 passed), test_command_descriptions + test_skill_guide_compliance + test_terminology_canonicalization + test_bats_assertion_contract + test_doc_counts + test_mb_router_targets (194 passed, 1 transient error in router_targets that passed on rerun: 7 passed); bats test_mb_team_checkpoint and test_mb_backlog_id_alloc green. Red state was the Stage 19 failing list plus the pre-fix runs shown in this session.

## Product fixes
- commands/critique.md, risk-find.md, final-report.md: descriptions rewritten to "what. Use when ..." form.
- SKILL.md: References section lists all references/mb/*.md files on one line.
- references/mb/init.md, install.md: added `## Contents` with working anchors.
- references/mb/aliases.md: removed Cyrillic planning terms (reworded, no whitelist).
- adapters/_lib_pi_global.sh: Pi global block shortened by ~300 B (largest file now under 8192-1024); sentence pinned by a test kept.
- tests/bats/test_mb_backlog_id_alloc.bats: byte-blind `$(cat)` comparisons replaced by `assert_unchanged` / `refute_cmd cmp -s`.
- tests/bats/test_mb_team_checkpoint.bats: hollow `! grep` replaced with `run bash -c ...; [ "$status" -eq 1 ]`.

## Test/baseline/budget changes (reasons)
- tests/pytest/fixtures/command_descriptions_baseline.json: +3 entries (new commands have no pre-rewrite description; baseline = their "what" text).
- tests/pytest/test_command_descriptions.py TOTAL_BUDGET 6200 -> 6610: the budget pinned the listing size before three commands existed; the three new descriptions add ~400 chars (total now 6603). Descriptions are already minimal in the other commands.

## Concerns
- My first probe ran install.sh with cwd = the repo, which refreshed the managed git hooks (.git/hooks/pre-commit, post-commit) and wrote ignored .codex/.mb-manifest.json, .pi/ (the .pi/ dir was already untracked). Hooks are the same managed hooks refreshed; review if the maintainer cares.
- Graph: 0 queries (changes were mechanical).
