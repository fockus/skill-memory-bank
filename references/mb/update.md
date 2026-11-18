# /mb update — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `update` — Actualize core files (with real code-state analysis)
- `update --strict` — Cap repair: MB Manager `action: actualize --strict` when `mb-core-cap.sh check` is red

### update

Actualize core files using automatic analysis of the current project state.

Unlike `done`, **update** does not create a note and does not require a session summary — the agent analyzes the state directly:

1. **Collect metrics through the language-agnostic script**:

```bash
# Detects the stack (python/go/rust/node/multi), outputs key=value:
#   stack=<stack>
#   test_cmd=<cmd>
#   lint_cmd=<cmd>
#   src_count=<N>
# For an unknown stack it returns empty values with a warning on stderr (does not fail).
# Override via .memory-bank/metrics.sh if you need custom metrics.
bash ${MB_SKILLS_ROOT:-$HOME/.claude/skills/memory-bank}/scripts/mb-metrics.sh

# Optional — run tests and capture status:
bash ${MB_SKILLS_ROOT:-$HOME/.claude/skills/memory-bank}/scripts/mb-metrics.sh --run

# Git context
git log --oneline -5
git diff --stat HEAD~3 2>/dev/null | tail -5
```

1. **Run MB Manager** with the collected metrics:

```
Agent(
  subagent_type="mb-manager",
  description="MB Manager: actualize",
  prompt="action: actualize

Current metrics from code (from mb-metrics.sh):
- Stack: <detected>
- Tests: <test_status or suggest running them manually>
- Source files: <src_count>
- Lint: <lint output if it was run>
- Recent commits: <git log>
- Changed files: <git diff stat>

Update core files (STATUS metrics, checklist, plan focus) using REAL data from the codebase. Do not rely on the narrative description — verify through grep/find/bash."
)
```

1. Show the user what was updated.

#### `update --strict` — cap repair

Run when `bash "$SKILL_DIR"/scripts/mb-core-cap.sh check --mb .memory-bank` exits non-zero
(the Stop hook `mb-core-cap-guard.sh` says so once per session). First try the deterministic repair:

```bash
bash ${MB_SKILLS_ROOT:-$HOME/.claude/skills/memory-bank}/scripts/mb-core-cap.sh fix --mb .memory-bank
```

Exit 0 — done, no subagent needed. Exit 3 — the checklist is over cap with live plans: that is an owner
decision (pause or close plans), surface it and stop. Exit 1 — dispatch MB Manager with
`action: actualize --strict` (contract in `agents/mb-manager.md`): `status.md` is rewritten to the canonical
skeleton and everything else moves verbatim into `progress.md`, `checklist.md` is only compacted, `⬜` lines
never move, and plans to close or pause come back as a **suggestion list** for you — the subagent never
closes a plan itself. It finishes with `mb-core-cap.sh check` and reports DONE or DONE_WITH_CONCERNS.

**Note:** if `mb-metrics.sh` returns `stack=unknown`, warn the user that auto-metrics are unavailable and suggest creating `.memory-bank/metrics.sh` with custom logic (see `references/templates.md`).
