# /mb doctor — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `doctor` — Find and fix internal MB inconsistencies

### doctor

Diagnose and fix inconsistencies INSIDE Memory Bank.

**Session-memory checks** run first, before the subagent. Run `mb-session-doctor.sh` if it exists (implemented in Stage 2):

```bash
if [ -x ${MB_SKILLS_ROOT:-$HOME/.claude/skills/memory-bank}/scripts/mb-session-doctor.sh ]; then
  bash ${MB_SKILLS_ROOT:-$HOME/.claude/skills/memory-bank}/scripts/mb-session-doctor.sh "$PWD"
fi
```

If the script is not yet implemented, the agent must manually check the items from `references/session-memory.md` § "Doctor checks":

- `.memory-bank/session/*.md` files with `summarized:false` (WARN — suggest catchup).
- Missing `.memory-bank/session/_recent.md` (WARN — suggest recent-rebuild).
- Empty semantic index (INFO — suggest reindex).
- Installed Claude hooks missing `mb-session-catchup.sh`/`mb-session-summarize.sh`/`mb-pre-compact.sh` (WARN — suggest adapter install).
- Pi session adapter extension not present (INFO — suggest `adapters/pi.sh install`).
- `progress.md` contains `### Auto-capture` stubs (WARN — suggest consolidation or `MB_AUTO_CAPTURE=off`).

**v2 naming migration check** is delegated to the subagent — see `agents/mb-doctor.md` → "Check: v2 naming migration". The agent will flag v1 files missing their v2 counterpart (WARN) or coexisting v1+v2 pairs (ERROR, manual resolution required) and point the user to `scripts/mb-migrate-v2.sh`.

Run the MB Doctor subagent:

```
Agent(
  subagent_type="mb-doctor",
  description="MB Doctor",
  prompt="action: doctor

Check consistency across all core files in .memory-bank/:
- roadmap.md statuses vs checklist.md
- status.md metrics vs reality (pytest, source files)
- status.md constraints vs real code
- backlog.md vs roadmap.md
- progress.md completeness
- plan files in plans/ vs their statuses
- duplicates and stale references"
)
```

Show the report to the user: what was found, what was fixed, and what still needs a decision.
