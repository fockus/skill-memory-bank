# Skill guide compliance — baseline (Sprint 1 Stage 1)

Gate: `tests/pytest/test_skill_guide_compliance.py` (helpers in `tests/pytest/_skill_guide_checks.py`).
Baseline = committed tree at e351a17 (`git archive HEAD`), scope = SKILL.md, references/, rules/, flow-templates/, commands/.

## 1. SKILL.md frontmatter — 0 violation(s) — GREEN

## 2. SKILL.md size (body ≤300 lines, file ≤36000 B) — 2 violation(s) — RED, xfail → Stage 2

- SKILL.md body: 619 lines > 300
- SKILL.md: 64754 bytes > 36000

## 3. ToC in references >100 lines — 26 violation(s) — RED, xfail → Stage 3

- flow-templates/arch.md: 105 lines, no table of contents
- flow-templates/research.md: 106 lines, no table of contents
- references/agreements.md: 116 lines, no table of contents
- references/claude-md-template.md: 148 lines, no table of contents
- references/code-graph.md: 195 lines, no table of contents
- references/command-template.md: 157 lines, no table of contents
- references/coordination.md: 119 lines, no table of contents
- references/design-principles.md: 135 lines, no table of contents
- references/hooks.md: 305 lines, no table of contents
- references/metadata.md: 133 lines, no table of contents
- references/planning-and-verification.md: 104 lines, no table of contents
- references/rubric-examples/backend.md: 221 lines, no table of contents
- references/rubric-examples/common.md: 199 lines, no table of contents
- references/rubric-examples/frontend.md: 233 lines, no table of contents
- references/rubric-examples/go.md: 195 lines, no table of contents
- references/rubric-examples/mobile.md: 208 lines, no table of contents
- references/rubric-examples/python.md: 182 lines, no table of contents
- references/rubric-examples/typescript.md: 194 lines, no table of contents
- references/rules-profile.schema.md: 116 lines, no table of contents
- references/session-memory.md: 192 lines, no table of contents
- references/structure.md: 322 lines, no table of contents
- references/templates.md: 731 lines, no table of contents
- references/work-loop-v2.md: 128 lines, no table of contents
- references/work-reference.md: 366 lines, no table of contents
- references/workflow.md: 142 lines, no table of contents
- rules/RULES.md: 805 lines, no table of contents

## 4. Every skill .md mentioned in SKILL.md — 20 violation(s) — RED, xfail → Stage 3

- flow-templates/arch.md: not mentioned in SKILL.md
- flow-templates/bugfix.md: not mentioned in SKILL.md
- flow-templates/code-change.md: not mentioned in SKILL.md
- flow-templates/migration.md: not mentioned in SKILL.md
- flow-templates/patterns/adversarial-verify.md: not mentioned in SKILL.md
- flow-templates/patterns/classify-and-act.md: not mentioned in SKILL.md
- flow-templates/patterns/fanout-synthesize.md: not mentioned in SKILL.md
- flow-templates/patterns/generate-filter.md: not mentioned in SKILL.md
- flow-templates/patterns/loop-until-done.md: not mentioned in SKILL.md
- flow-templates/patterns/tournament.md: not mentioned in SKILL.md
- flow-templates/research.md: not mentioned in SKILL.md
- references/rubric-examples/backend.md: not mentioned in SKILL.md
- references/rubric-examples/common.md: not mentioned in SKILL.md
- references/rubric-examples/frontend.md: not mentioned in SKILL.md
- references/rubric-examples/go.md: not mentioned in SKILL.md
- references/rubric-examples/mobile.md: not mentioned in SKILL.md
- references/rubric-examples/python.md: not mentioned in SKILL.md
- references/rubric-examples/typescript.md: not mentioned in SKILL.md
- rules/CLAUDE-GLOBAL.md: not mentioned in SKILL.md
- rules/RULES.md: not mentioned in SKILL.md

## 5. SKILL.md paths exist on disk — 0 violation(s) — GREEN

## 6. Command descriptions (what + when, no disable-model-invocation) — 33 violation(s) — RED, xfail → Stage 4

- commands/adr.md: description has no 'when' marker
- commands/agree.md: description has no 'when' marker
- commands/analyze-task.md: description has no 'when' marker
- commands/api-contract.md: description has no 'when' marker
- commands/brief.md: description has no 'when' marker
- commands/catchup.md: description has no 'when' marker
- commands/changelog.md: description has no 'when' marker
- commands/commit.md: description has no 'when' marker
- commands/config.md: description has no 'when' marker
- commands/contract.md: description has no 'when' marker
- commands/db-migration.md: description has no 'when' marker
- commands/discuss.md: description has no 'when' marker
- commands/doc.md: description has no 'when' marker
- commands/done.md: description has no 'when' marker
- commands/drive.md: description has no 'when' marker
- commands/flow.md: description has no 'when' marker
- commands/goal.md: description has no 'when' marker
- commands/groom.md: description has no 'when' marker
- commands/mb.md: description has no 'when' marker
- commands/observability.md: description has no 'when' marker
- commands/pipeline.md: missing frontmatter
- commands/plan.md: description has no 'when' marker
- commands/pr.md: description has no 'when' marker
- commands/profile.md: description has no 'when' marker
- commands/refactor.md: description has no 'when' marker
- commands/review.md: description has no 'when' marker
- commands/roadmap-sync.md: description has no 'when' marker
- commands/sdd.md: description has no 'when' marker
- commands/security-review.md: description has no 'when' marker
- commands/start.md: description has no 'when' marker
- commands/test.md: description has no 'when' marker
- commands/traceability-gen.md: description has no 'when' marker
- commands/work.md: description has no 'when' marker

## Working tree on 2026-10-06 (uncommitted, parallel sessions) vs baseline

- Check 4: 21 (+1) — `references/pi-native-integration.md` is untracked in the tree, so not in the e351a17 baseline.
- Check 6: 0 — commands/*.md frontmatter was already rewritten in the working tree by a parallel session
  while this stage ran; `test_repo_command_descriptions_compliant` therefore XPASSes (strict) and must have
  its xfail lifted by whoever owns Stage 4.
- Check 2: SKILL.md in tree is 622 body lines / 65774 B (baseline 619 / 64754).
- Checks 1, 3, 5: unchanged.

## Note on check 5 scope

Path tokens are taken from fenced blocks, inline code spans and link targets only; prose is skipped
("local hooks/configs" is wording, not a path), and paths under foreign roots (`.cursor/rules/…`,
`~/.claude/…`) are skipped. Without that, the naive regex yields 2 false positives:
`hooks/configs` (SKILL.md:20) and `rules/memory-bank.mdc` (from `.cursor/rules/memory-bank.mdc`, SKILL.md:460).

## Stage 5 · item 5 — live listing check (2026-10-06)

Live Claude Code session (claude-opus-5-5, this repo): the available-skills listing contains `memory-bank` exactly once; `skill-memory-bank` is not listed separately. The canonical dir + alias do not produce a duplicate entry. No backlog item needed.
