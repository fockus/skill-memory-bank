# /mb drive — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `drive [--goal PATH] [--budget TOK] [--serial] [--host-serial] [--resume [RUN_ID]]` — Plan a goal with the user, then run it unattended: `scripts/mb-drive.sh next` prints ONE action (`work`, `team`, `pivot`, `qa`, `wait`, `final_qa`, `stop_*`), executed through `/mb work` or `/mb team` until a `stop_*`. See `commands/drive.md`

### drive

**Alias** for `/drive` — dispatch to `commands/drive.md` for the canonical workflow: plan a goal with the user, then drive it to `stop_success` through `/mb work` and `/mb team`.

```
/mb drive [--goal PATH] [--budget TOK] [--serial] [--host-serial] [--resume [RUN_ID]]
```

**You are the runtime.** Run the `<!-- mb-drive:start -->` fence of `commands/drive.md` (`mb-drive.sh start` refuses an absent or invalid goal and prints the run id), plan every criterion with the user and open execution with `mb-drive.sh phase execution`, then loop:

```bash
SKILL_DIR="${MB_SKILLS_ROOT:-${SKILL_DIR:-$HOME/.claude/skills/memory-bank}}"
. "$SKILL_DIR/scripts/_lib.sh"
BANK="$(mb_resolve_path "${BANK:-}")"
# → one action line: plan | work | team | pivot | qa | wait | final_qa | stop_success | stop_human <why> | stop_budget
bash "$SKILL_DIR/scripts/mb-drive.sh" next --bank "$BANK" --run-id <run_id>
```

Run the action, report it with `mb-drive.sh returned --action "<line>" --tokens N`, and call `next` again until it starts with `stop_`. Record every stop with `scripts/mb-drive-stop.sh record --run-id <run_id> --action "<line>"`. `stop_success` is the ONLY done signal — never self-certify. Several drives share a bank on distinct goal files (`--goal`); `--resume [RUN_ID]` continues a stored run.
