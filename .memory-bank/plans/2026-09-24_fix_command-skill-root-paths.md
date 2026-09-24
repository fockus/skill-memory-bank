---
type: fix
topic: command-skill-root-paths
status: in_progress
depends_on: []
parallel_safe: false
linked_specs: []
created: 2026-09-24
---
# Plan: fix — command-skill-root-paths

**Baseline commit:** cfee2e04ffdf53b25f57b4ceaf5dd34d7306b0cc

## Context

**Problem:** 13 command files run bundled scripts through a hard-coded Claude Code path
(`bash ~/.claude/skills/memory-bank/scripts/…`, `bash ~/.claude/hooks/…`). On Codex, OpenCode, and
pi the skill is loaded from its own directory (`~/.codex/skills/memory-bank`, …); these commands only
work because `install.sh` also creates the Claude alias. The rest of the commands already use the
`$SKILL_DIR` convention (`commands/mb.md` line 16, the "Skill bundle root" block in
`commands/groom.md`).

**Expected result:** every command runs bundled scripts and hooks through `"$SKILL_DIR"`; a contract
test keeps the hard-coded form out.

**Related files:**
- `commands/{security-review,db-migration,api-contract,observability,plan,catchup,commit,adr,roadmap-sync,traceability-gen}.md`
- `commands/mb.md` (lines with `bash ~/.claude/…`: recall, core-cap, semantic-bootstrap)
- `commands/groom.md` — the "Skill bundle root" block to reuse verbatim
- Out of scope: `agents/*.md` (an agent's shell has no `SKILL_DIR`; needs the dispatch prompt to carry
  the skill path first — separate item). Mentions of `~/.claude/...` that are documentation, not a
  command to run (e.g. `commands/mb.md` § upgrade), stay.

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: commands run bundled scripts through `$SKILL_DIR`

**What to do:**
- In each listed command file replace `~/.claude/skills/memory-bank/scripts/` with `"$SKILL_DIR"/scripts/`
  and `~/.claude/hooks/<hook>` with `"$SKILL_DIR"/hooks/<hook>` wherever it is a command to run
  (`bash …`, `python3 …`, `eval "$(bash …)"`).
- `commands/plan.md`: the `~/.claude/skills/memory-bank/references/templates.md` read step → `$SKILL_DIR/references/templates.md`.
- `hooks/lib/session-common.sh` `sc_semantic_py`: after `$1/.venv`, fall back to `$HOME/.claude/hooks/.venv`
  (the venv `mb-semantic-bootstrap.sh` creates and `semantic_index.py` `_GLOBAL_VENV_PY` reads). Recall now
  runs from `"$SKILL_DIR"/hooks/`, where no venv lives; without the fallback `/mb recall` silently loses
  its semantic hits (found in review of the first implement pass).
- Each touched file other than `commands/mb.md` gets the "Skill bundle root" block from
  `commands/groom.md` (heading + two-line bash snippet), placed before its first use, unless the file
  already has it. `commands/mb.md` already defines `$SKILL_DIR` at the top.

**Testing (TDD — tests BEFORE implementation):**
- New `tests/pytest/test_commands_skill_root.py`, written first and failing on the current tree:
  - `test_commands_run_no_hardcoded_claude_skill_path` — no line in `commands/*.md` matches
    `(bash|python3) ~/\.claude/` (parametrized per file, id = file name);
  - `test_commands_using_skill_dir_define_it` — every `commands/*.md` except `mb.md` that contains
    `"$SKILL_DIR"` also contains the line `SKILL_DIR="${MB_SKILLS_ROOT:-${SKILL_DIR:-$HOME/.claude/skills/memory-bank}}"`.
- bats (in the existing session-common / recall suite): with `HOME` set to a temp dir holding
  `.claude/hooks/.venv/bin/python` (executable stub) and no venv beside the hook dir, `sc_semantic_py`
  returns that stub; with `MB_SEMANTIC_PY` set it still wins; with neither it returns `python3`.
- Edge: `commands/mb.md` § upgrade text naming `~/.claude/skills/skill-memory-bank` is prose, not a
  `bash`/`python3` invocation — the regex must not flag it.

**DoD (Definition of Done):**
- [x] `grep -nE '(bash|python3) ~/\.claude/' commands/*.md` prints nothing.
- [x] `tests/pytest/test_commands_skill_root.py` exists, fails on the baseline tree, passes now.
- [x] every non-`mb.md` command file that uses `"$SKILL_DIR"` has the bundle-root block (checked by the test above).
- [x] `.venv/bin/python -m pytest -q tests/pytest` green (no new failures).
- [x] `sc_semantic_py` finds `~/.claude/hooks/.venv` when the hook dir has no venv (bats test above passes).
- [x] only files under `commands/`, `hooks/lib/session-common.sh`, and the tests changed by this stage.

**Code rules:** SOLID, DRY, KISS, YAGNI, Clean Architecture

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| An existing contract test pins the old literal path | M | run the full pytest battery; update a pinning test only to the `$SKILL_DIR` form |
| A bash snippet quoted inside prose loses its meaning when rewritten | L | rewrite only invocations; leave prose mentions |

## Gate (plan success criterion)

Stage 1 DoD all checked and `plan-verifier` PASS.
