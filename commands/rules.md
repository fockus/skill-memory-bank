---
description: "Manages the Key rules block — choose catalog rules and add your own rules for CLAUDE.md and AGENTS.md, globally or per project — and the quality settings (architecture, TDD, Trophy, coverage, principles). Use when the user wants to see, turn on/off or add coding rules («мои правила», «отключи правило», «coverage 80»)."
allowed-tools: [Bash, Read, AskUserQuestion]
argument-hint: <list|enable|disable|add|remove|set|init|sync> [args] [--scope=user|project]
---

# /mb rules — Key rules selection: $ARGUMENTS

The `## Key rules` block (`<!-- mb-key-rules:start/end -->`) sits at the top of `CLAUDE.md` and
`AGENTS.md`: one line per rule from the catalog `rules/key-rules.json` plus the user's own rules,
ending with a pointer to the detailed `RULES.md`. The selection lives in the `key_rules` field of the
rules profile (`references/rules-profile.schema.md`); project overrides user. The architecture and
test lines (TDD, Testing Trophy, coverage) and the four principles render from the profile's quality
settings — `architecture` and `quality` — changed with `set`; that is their only place.

With `--scope=project` the same settings are also written, human-readable, into the project
`RULES.md` (`<repo>/RULES.md`, else `<bank>/RULES.md`) between `<!-- mb-project-rules:start -->` and
`<!-- mb-project-rules:end -->`: architecture(s) with the preset rules and severity, principles,
TDD, Trophy, coverage thresholds. Text outside the block is the user's and never changes; only
`init --scope=project` creates a missing `RULES.md`.

The only writer is `scripts/mb-rules.sh` — never edit the block or the profile by hand:

```bash
bash "${MB_SKILLS_ROOT:-$HOME/.claude/skills/memory-bank}/scripts/mb-rules.sh" <subcommand> [args] [--scope=user|project]
```

## Subcommands

| Subcommand | Effect |
|---|---|
| `list` | Numbered checklist by group: `[x]` on, `[ ]` off, `[*]` locked (always on); own rules numbered below |
| `enable <id>` / `disable <id>` | Turn a catalog rule on/off; disabling a locked rule → exit `2` with the reason. For `solid`/`dry`/`kiss`/`yagni`, `tdd`, `testing-trophy`, `coverage` this flips the quality setting |
| `add "<text>"` | Add an own rule (one line, ≤200 chars) |
| `remove <n>` | Remove own rule number `n` from `list` |
| `init [--enable=id,id] [--disable=id,id] [--custom="<text>"]...` | Replace the scope's whole selection (used by onboarding below) |
| `set <key> <value>` | Change one quality setting (table below) |
| `sync` | Re-render the block (and the project `RULES.md` block) from the profiles; `--scope=project` also refreshes the AGENTS.md Memory Bank block and existing per-host rule files — the command the session-start hint names when a block's `mb-stamp` is stale (`MB_AUTO_REFRESH=on` runs it automatically) |

| `set` key | Values | Example |
|---|---|---|
| `set architecture` | `<name>[,<name>…][,custom:<text>]` — `clean`, `hexagonal`, `modular-monolith`, `microservices`, `ddd`, `fsd`, `mobile-udf`, `event-driven` | `set architecture modular-monolith` |
| `set tdd` | `on` · `off` · `small+` (TDD from the small effort tier up; default) | `set tdd off` |
| `set trophy` | `on` · `off` (Testing Trophy) | `set trophy on` |
| `set coverage` | `off` (default) · `<overall>/<core>/<infra>` percentages | `set coverage 80/95/70` |
| `set principle` | `solid`·`dry`·`kiss`·`yagni` + `on`·`off` | `set principle kiss off` |
| `set discipline` | `auto` · `strict` · `calm` (`discipline <value>` still works) | `set discipline strict` |

`--scope=project` → the bank's `rules-profile.json` and the project `CLAUDE.md`/`AGENTS.md` only —
their block lists just the project's differences from the user rules; Windsurf/Cline/Kilo rule files get the full block;
`--scope=user` → `~/.claude/memory-bank/rules-profile.json` and the global files only
(`~/.claude/CLAUDE.md`, Codex/Pi/OpenCode/Cursor `AGENTS.md`). Default: project when a bank resolves,
else user. Every mutating subcommand writes the profile, then syncs that scope. Exit `2` = invalid id,
locked rule, bad text or bad setting value — report the message to the user.

Empty `$ARGUMENTS` → run `list` and show it.

## `init` — onboarding

1. Run `mb-rules.sh list --scope=<scope>` and show the checklist.
2. Ask with `AskUserQuestion` (`multiSelect: true`), question "Which of these rules should be ON?":
   one question per chunk of ≤4 unlocked rules of a group (header = group title, option label =
   rule id, description = rule text), at most 4 questions per call — repeat the call until every
   unlocked rule was offered. Locked principles are not asked; say they are always on. The
   `architecture` row is not a toggle — it is asked in step 4.
3. Ask one more question — "Your own rules (architecture, process, anything)?" — options `None` and
   `Keep current`; the user types own rules into the free-text answer, one per line or separated by `;`.
4. Ask the quality settings in one `AskUserQuestion` call (current values: `mb-profile.sh quality`):
   - **Architecture** (`multiSelect: true`) — options = the most likely presets for this project
     (≤4; the user names others or a custom rule in the free-text answer);
   - **TDD** — `small+` (default) · `on` · `off`;
   - **Trophy** — `on` (default) · `off`;
   - **Coverage** — `off` (default) · `85/95/70` · `80/90/60`; another `<overall>/<core>/<infra>` in
     the free-text answer.
5. Run `mb-rules.sh init --scope=<scope> --enable=<checked ids> --disable=<unchecked ids>
   --custom="<rule>" ...` (one `--custom` per own rule; with `Keep current` pass the current own rules
   from `list`), then one `set` per answered setting (`set architecture <names[,custom:text]>`,
   `set tdd …`, `set trophy …`, `set coverage …`). Show the resulting `list`.

Hosts without `AskUserQuestion`: show the checklist, ask for the numbers to toggle and the own rules
in plain text, then call `init` the same way.

The installer runs the same onboarding on a TTY (`mb-rules.sh init --interactive --scope=user`):
checklist, own rules, then the Quality step (architecture numbers or `c <text>`, TDD, Trophy, coverage;
Enter keeps the current value); `install.sh --key-rules=default|keep` or `--non-interactive` skips it.
