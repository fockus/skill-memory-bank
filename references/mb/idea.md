# /mb idea — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `idea <title> [HIGH\|MED\|LOW]` — Capture new idea in `backlog.md` with auto-generated monotonic `I-NNN` ID (priority defaults to `MED`)

### idea [--force] [--] <title> [HIGH|MED|LOW]

Capture a new idea in `backlog.md ## Ideas` with an auto-generated monotonic `I-NNN` ID.

**Arguments:**

- `title` — free-form idea title (first positional).
- priority (optional) — `HIGH`, `MED` (default), or `LOW`. Case-insensitive.

**Effect:**

- Appends `### I-NNN — <title> [PRIO, NEW, YYYY-MM-DD]` plus a `**Type:** IDEA` line under `## Ideas` in `backlog.md`.
- `I-NNN` is allocated **globally across the bank** by one helper, `mb_next_backlog_id` (`scripts/_lib.sh`): max over `backlog.md`, `progress.md`, `progress-archive.md` and `index.json`, plus one (zero-padded 3 digits), under `.locks/backlog.lock`.
- Before writing, the title is compared with the titles under `## Out of scope`; a match prints `similar_out_of_scope=<I-NNN> score=<0..1>` on stderr and exits 1. `--force` (first argument only) bypasses only that refusal; `--` ends option parsing for a title that starts with dashes.
- `[SPEC:<group>] <child-topic>` registers a SPEC entry (`**Type:** SPEC`, `**Group:**`, `**Parent:** none`, `**Spec:**`) and skips the similarity check.
- Idempotent: re-running with the exact same title reports the existing ID and exits without a duplicate.
- Invalid priority → exit 2 with usage hint.

Run directly (systems-level, no LLM needed):

```bash
bash ${MB_SKILLS_ROOT:-$HOME/.claude/skills/memory-bank}/scripts/mb-idea.sh "<title>" [HIGH|MED|LOW]
```

## Backlog state machine

`NEW → NEEDS-INFO ⇄ TRIAGED → READY → IN-PROGRESS → DONE | WONTFIX`. It replaces the legacy `NEW/TRIAGED/PLANNED/DONE/DECLINED/DEFERRED` tokens.

| From | To |
|------|----|
| `NEW` | `NEEDS-INFO` |
| `NEEDS-INFO` | `TRIAGED` |
| `TRIAGED` | `NEEDS-INFO`, `READY` |
| `READY` | `IN-PROGRESS` |
| `IN-PROGRESS` | `DONE`, `WONTFIX` |

`DONE` and `WONTFIX` are terminal. Any other transition exits 1 and lists the allowed ones.

- **READY gate:** the entry needs a `**Brief:**` that describes observable behaviour (should/must/shall/когда/если) and contains no file path or line number. Write it with `annotate`.
- **WONTFIX:** needs a non-empty `--reason TEXT`; the block moves from `## Ideas` to `## Out of scope` with a `**Reason:** <TEXT>` line.
- **Hierarchy:** an optional `**Parent:** <I-NNN|none>` line; `list --tree` prints parents before children with `depth=`.

```
mb-backlog-state.sh transition <I-NNN> <NEW_STATE> [--reason TEXT] [--mb PATH]
mb-backlog-state.sh annotate   <I-NNN> --brief <TEXT> [--parent <I-NNN|none>] [--mb PATH]
mb-backlog-state.sh list [--tree] [--mb PATH]
```

Each `list` line is `item=<I-NNN> state=<STATE> parent=<I-NNN|none> depth=<int> title=<JSON-string>`.

**Legacy backlogs:** `mb-backlog-migrate.sh [--dry-run|--apply] [mb_path]` converts old tokens (`OPEN|PROPOSED|DEFERRED → TRIAGED`, `PLANNED → IN-PROGRESS`, `RESOLVED → DONE`, `DECLINED → WONTFIX` plus the move to `## Out of scope`) and types `[SPEC:<group>]` titles. `--dry-run` is the default; a second `--apply` changes nothing.

**Lint:** `mb-bank-lint.sh <roadmap|backlog|all> [--mb PATH]` is read-only. It prints one `severity=… code=… file=… line=… detail=…` line per finding; exit 1 only when an error is present. Un-migrated legacy tokens are warnings (`legacy_state`), not errors.

```
mb-bank-lint.sh <roadmap|backlog|all> [--mb PATH]
mb-backlog-migrate.sh [--dry-run|--apply] [mb_path]
mb-idea.sh [--force] [--] <title> [priority] [mb_path]
```

**Typical flow:**

```
User: /mb idea "Telemetry opt-in" LOW
→ [idea] I-007 added (LOW)

User: /mb idea "Add dark mode"
→ [idea] I-008 added (MED)
```

Surface the created ID back to the user so they can reference it in `/mb idea-promote`.
