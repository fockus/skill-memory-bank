# /mb idea-promote — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `idea-promote <I-NNN> <type>` — Promote a `READY` idea → plan. Creates plan file via `mb-plan.sh`, moves the idea `READY → IN-PROGRESS`, adds `**Plan:** [plans/...]` link, runs plan-sync. `type ∈ feature\|fix\|refactor\|experiment`

### idea-promote <I-NNN> <type>

Promote an existing idea into an active plan.

**Arguments:**

- `I-NNN` — ID of the idea in `backlog.md`; it must be in `READY` status with a valid `**Brief:**`.
- `type` — `feature`, `fix`, `refactor`, or `experiment` (passed through to `mb-plan.sh`).

**Effect** (all under `.locks/backlog.lock`):

- Creates a plan file via `mb-plan.sh` using the idea title as the topic (title → slug).
- Moves the idea `READY → IN-PROGRESS` and adds `**Plan:** [plans/YYYY-MM-DD_<type>_<slug>.md](plans/...)` in one atomic write, through the same transition code as `mb-backlog-state.sh`.
- Runs `mb-plan-sync.sh` so the new plan appears in `roadmap.md` / `status.md` `<!-- mb-active-plans -->` blocks and its stages are appended to `checklist.md`.

**Behaviour change:** promote used to accept `NEW` and `TRIAGED` ideas and write `PLANNED`. It now requires `READY` and the `PLANNED` token is never written. The path is `NEW → NEEDS-INFO → TRIAGED → READY (needs a Brief) → promote`:

```bash
mb-backlog-state.sh transition I-007 NEEDS-INFO
mb-backlog-state.sh transition I-007 TRIAGED
mb-backlog-state.sh annotate I-007 --brief "the export should retry when the upstream is unavailable"
mb-backlog-state.sh transition I-007 READY
mb-idea-promote.sh I-007 feature
```

**Refuses** (exit 2): `NEW`, `NEEDS-INFO` and `TRIAGED` ideas (with this path), `IN-PROGRESS`, `DONE` and `WONTFIX` ideas, and legacy tokens (`PLANNED`, `DEFERRED`, `OPEN`, `PROPOSED`, `RESOLVED`, `DECLINED`) — run `mb-backlog-migrate.sh` first; it turns a legacy `PLANNED` into `IN-PROGRESS`. An unknown status exits 1, an invalid type exits 3.

**Partial failure:** if the plan exists but the backlog write or the sync failed, the script exits 1 with `code=promote_partial plan=<path> backlog_updated=<true|false>`. Run the same promote again: it reuses that plan and finishes the missing step.

Run directly:

```bash
bash ${MB_SKILLS_ROOT:-$HOME/.claude/skills/memory-bank}/scripts/mb-idea-promote.sh <I-NNN> <type>
```

**Typical flow:**

```
User: /mb idea-promote I-007 feature
→ [promote] I-007 → 2026-04-21_feature_telemetry-opt-in.md
  plans/2026-04-21_feature_telemetry-opt-in.md
```

The idea's `**Plan:**` link lets anyone navigate from `backlog.md` to the live plan; `mb-plan-done.sh` marks the idea `DONE` when the plan is closed.
