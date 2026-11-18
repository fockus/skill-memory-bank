# /mb help — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `help [subcommand]` — Help. No argument → list all subcommands. With argument → show details for that specific one (`/mb help compact`, `/mb help tags`, ...)

### help [subcommand]

Help for `/mb` subcommands. Reads the router table in `commands/mb.md` and the per-subcommand files in `references/mb/`.

**Modes (first word after `help`):**

1. `/mb help` (no argument) — print the router table of all subcommands with one-line descriptions.
2. `/mb help <subcommand>` — print the reference file `references/mb/<subcommand>.md` (the third column of the router table in `commands/mb.md` names it). A subcommand that shares a file (for example `note` → `context.md`) is resolved through the table.

**Algorithm for the agent:**

```bash
SKILL_MD="${MB_SKILLS_ROOT:-$HOME/.claude/skills/memory-bank}/commands/mb.md"
SUB="$SUBCOMMAND_ARG"  # first word after "help"; may be empty

SKILL_MD="$SKILL_MD" SUB="$SUB" python3 - <<'PY'
import os, re, sys
path = os.environ["SKILL_MD"]
root = os.path.dirname(os.path.dirname(path))
sub = os.environ.get("SUB", "").strip()
lines = open(path, encoding="utf-8").read().splitlines()

if not sub:
    # Mode 1: router table: between "### Routing" and the next "---"
    in_section = False
    for line in lines:
        if line.startswith("### Routing"):
            in_section = True
            continue
        if in_section and line.startswith("---"):
            break
        if in_section:
            print(line)
    print("\nDetails: /mb help <subcommand>  (e.g. /mb help compact)")
    sys.exit(0)

# Mode 2: find the router row with a backticked command in its first cell whose first word is `sub`
for line in lines:
    if not line.startswith("| "):
        continue
    cell = re.split(r"(?<!\\)\|", line)[1]
    if sub not in [tok.split()[0] for tok in re.findall(r"`([^`]+)`", cell) if tok.split()]:
        continue
    ref = re.search(r"`(references/mb/[\w\-]+\.md)`", line)
    if ref:
        print(open(os.path.join(root, ref.group(1)), encoding="utf-8").read())
        sys.exit(0)
print(f"No subcommand '{sub}'. Run /mb help for the list.", file=sys.stderr)
sys.exit(1)
PY
```

**Examples:**

```
User: /mb help
→ prints the router table

User: /mb help compact
→ prints references/mb/compact.md with logic, examples, and limitations

User: /mb help tags
→ prints references/mb/tags.md
```

**Do not confuse with:**

- `/help` — built-in Claude Code command (not a skill).
- `commands/catchup.md` / `commands/start.md` / `commands/done.md` — standalone top-level slash commands (lightweight), not `/mb` subcommands.
