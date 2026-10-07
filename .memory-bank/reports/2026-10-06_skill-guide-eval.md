# Sprint 1 Stage 6 — A/B eval old vs new SKILL.md (2026-10-06)

Old = `~/skills-backup-2026-10-06` (SKILL.md 626 lines), new = repo (SKILL.md ~261 lines). Read-only subagents, workflow wf_38d17eba-7fd.

| scenario | model | ver | skill files | skill lines read | missing paths | cmds | correct |
|---|---|---|---|---|---|---|---|
| s1 | haiku | old | 1 | 471 | — | 3 | yes |
| s1 | haiku | new | 9 | 409 | <repo>/RULES.md | 4 | yes |
| s3 | haiku | old | 4 | 571 | <repo>/RULES.md | 13 | yes |
| s3 | haiku | new | 6 | 461 | <repo>/RULES.md | 5 | yes |
| s3 | sonnet | old | 1 | 627 | ~/skills-backup-2026-10-06/scripts | 7 | yes |
| s3 | sonnet | new | 1 | 261 | <repo>/RULES.md | 3 | yes |

## Confusions reported

- **s1/haiku/old:** None—skill instructions are clear. One clarification: the user asked to "не забудь указать на файл rules.md локальный в проекте" (remind about local rules.md) in CLAUDE.md and AGENTS.md files because users may write it manually. The instructions say to reference global rules/RULES.md in CLAUDE.md/AGENTS.md frontmatter/comments, AND to note that a project may have its own rules.md override. This pr
- **s1/haiku/new:** The claude-md-template.md line 37 says rules come from \"global + .memory-bank/RULES.md when present\" suggesting that location as preferred, but AGR-066 phrasing is \"<repo>/RULES.md или <bank>/RULES.md\" (either place). Current project AGENTS.md line 115 states the rule exists but does not link to it; CLAUDE.md similarly generic. Instructions in SKILL.md line 12 shows `<repo>/RULES.md` or `<bank
- **s3/haiku/old:** 1. The local project RULES.md file doesn't exist but is referenced as mandatory by AGR-066 in both project CLAUDE.md and AGENTS.md — this creates an inconsistency where the project instructs reading a file that isn't present.

2. SKILL.md does not mention where to find the global skill rules (rules/RULES.md in the skill bundle) or advise agents to look there. The location must be inferred from the
- **s3/haiku/new:** None. Documentation is clear and internally consistent. The local RULES.md file is properly referenced in both CLAUDE.md and AGENTS.md as optional user-provided project overrides.
- **s3/sonnet/old:** 1. The skill root /Users/anton-one/skills-backup-2026-10-06 has no scripts/ directory. SKILL.md says "scripts live in scripts/ next to this SKILL.md", so that is only true after redirecting to the repo. The task told me to do that.
2. SKILL.md is 627 lines and the Read tool truncated at 471 (25k token cap), so a second read was needed.
3. The ~92 vs 93 vs 83 numbers differ because they count diffe
- **s3/sonnet/new:** 1) SKILL.md says "scripts/... resolve under SKILL ROOT" and the `~/.claude/RULES.md` install path, but the repo has rules/RULES.md; fine, but the mapping is only stated in one line (252). 2) Fallback described as "relative .memory-bank" in SKILL.md, but code comment header lists registry hit conditioned on MB_AGENT being set, whereas SKILL.md says global mode is found via registry without mentioni

## Verdict

- Both versions answer both scenarios correctly (definition `scripts/_lib.sh:299`, active work list).
- New version: no broken skill paths; SKILL.md is ~261 lines vs 626 old.
- Missing `<repo>/RULES.md` is expected: this repo has no project RULES.md; AGR-066 pointers land with plan key-rules-onboarding.
- Scenario 2 (should NOT trigger the skill) is not measurable with subagents — they don't go through skill selection from the listing. UNVERIFIED; check manually in a fresh session.
- No regression found → no rollback.
