# /mb cost — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `cost [--project <dir>] [--since N] [--json]` — Transcript cost report: per session (turns / tool calls / dispatches / tokens / peak context / compactions), per subagent role (implementer / verifier / reviewer / judge), and per work item (`mb-work-state.sh init` → `mb-work-checkbox.sh flip`). `--json` emits the baseline format the cost-diet gates diff against

### cost [--project <dir>] [--since N] [--json]

Mine Claude Code transcripts for what a `/mb work` session actually costs. Run directly — no subagent:

```bash
python3 ${MB_SKILLS_ROOT:-$HOME/.claude/skills/memory-bank}/scripts/mb-cost-report.py $ARGS_AFTER_COST
```

`--project` defaults to `~/.claude/projects/<cwd with '/' → '-'>`; `--since N` keeps only sessions
whose newest record is under N days old. Three cuts: **sessions**, **subagent roles** (classified from
the dispatch prompt), **work items** (the orchestrator segment between `mb-work-state.sh init` and
`mb-work-checkbox.sh flip`). `--json` is the machine format saved as a baseline under
`.memory-bank/reports/` and diffed by the cost-diet sprint gates.
