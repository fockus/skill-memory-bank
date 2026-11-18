---
description: "Memory Bank — long-term project memory management: context, plans, specs, work, verify, done. Use when the user types /mb or asks about project memory or status — «что в работе», «восстанови контекст»."
allowed-tools: [Bash, Read, Write, Edit, Task, Glob, Grep]
---

# Memory Bank — /mb

The `/mb` command is the single entrypoint for managing project Memory Bank (`.memory-bank/`).

## Subcommands

Arguments: `$ARGUMENTS`

Determine the subcommand from the first word of `$ARGUMENTS`. Remaining words are parameters for that subcommand.

`$SKILL_DIR` below always means the absolute directory containing the loaded `SKILL.md` (or `MB_SKILLS_ROOT`); bundled scripts run through it, never through a bare `scripts/…` path. For bank-dependent operations below (`recall`, `recap`, `conflicts`, `consolidate`, `verify`), resolve the bank with the setup block. Set `MB_AGENT` to the current host id for a global registry. Keep the project as cwd and include this setup in the same shell invocation as the operation. `init` and bank-independent commands such as user profiles do not require an existing bank; do not run this guard for them. `start` and `done` have their own setup in the canonical command files.

<!-- mb-runtime:setup -->
```bash
SKILL_DIR="${MB_SKILLS_ROOT:-${SKILL_DIR:?Set SKILL_DIR from the loaded skill path}}"
source "$SKILL_DIR/scripts/_lib.sh"
BANK="$(mb_resolve_path)"
if [ ! -d "$BANK" ]; then
  echo "[MEMORY BANK: ABSENT]"
  exit 0
fi
BANK="$(cd "$BANK" && pwd -P)"
export MB_PATH="$BANK"
```

Subagents below are dispatched by name (the Claude Code form is shown; OpenCode, Codex, and Pi use the tools in SKILL.md § Invocation); the prompt carries only the task data, and the agent's model, effort, and tools come from its installed definition. If your agent cannot dispatch a subagent by name, read `$SKILL_DIR/agents/<name>.md` plus each partial listed in its `compose:` frontmatter and pass that text ahead of the prompt.

For the snippets below, parse the remaining user arguments into the named Bash array (`ARGS_AFTER_RECAP`, `ARGS_AFTER_CONFLICTS`, or `ARGS_AFTER_CONSOLIDATE`); use an empty array when omitted. Preserve each argument as a separate element, without `eval` or shell-string interpolation.

### Routing

#### GraphRAG-lite retrieval routing

`code_context is the default` for ambiguous code-understanding questions such as "where is the logic for X?" and "find similar implementation". Exact structural questions use graph tools directly: "who calls/imports/defines X?" → `graph_neighbors`, "reverse deps" or impact analysis → `graph_impact`, and "what tests cover this file/symbol?" → `graph_tests`. User explicitly asks "semantic search" → `search_code`, served by `bash "$SKILL_DIR"/scripts/mb-graph.sh search "<query>"` (one token → BM25, a phrase → local embeddings); respect explicit tool intent.

Fail open: for missing graph or stale graph, explain the limitation and suggest `/mb graph --apply`; for missing semantic provider or unavailable native extension, use `scripts/mb-code-context.py`, `bash "$SKILL_DIR"/scripts/mb-graph.sh who-calls|impact|tests <Symbol>`, `rg`, and `read` as CLI fallback instead of blocking.


| Subcommand | Action | Reference |
| --- | --- | --- |
| (empty) or `context` | Collect project context | `references/mb/context.md` |
| `start` | Extended session start — same per-file cap as `context`, `--full` to disable it | `references/mb/aliases.md` |
| `search <query>` | Search information in the memory bank | `references/mb/context.md` |
| `recall <query>` | Lexical recall over session-memory log + notes (ripgrep over `session/` + `notes/`) — session-memory subsystem | `references/mb/recall.md` |
| `recap <sid>` | Reconstruct a full `progress.md` entry from `session/<sid>*.md` via one Haiku call, replacing that session's... | `references/mb/recap.md` |
| `conflicts [--judge] [--threshold N]` | Surface memory entries with high lexical overlap **and** opposing/replacement assertions (en+ru markers) as conflict... | `references/mb/conflicts.md` |
| `consolidate [--apply] [--days N]` | Fold sessions older than `N` days (default 30) that cluster by shared files / lexical overlap into 5–15 line... | `references/mb/consolidate.md` |
| `research <query>` | Graph-first multi-source research — codebase / memory / library / prior-art / web; dispatches the `mb-research`... | `references/mb/research.md` |
| `note <topic>` | Create a note | `references/mb/context.md` |
| `update` | Actualize core files (with real code-state analysis) | `references/mb/update.md` |
| `update --strict` | Cap repair: MB Manager `action: actualize --strict` when `mb-core-cap.sh check` is red | `references/mb/update.md` |
| `doctor` | Find and fix internal MB inconsistencies | `references/mb/doctor.md` |
| `tasks` | Show unfinished tasks | `references/mb/context.md` |
| `index` | Registry of all entries | `references/mb/index.md` |
| `done` | End session (`actualize + note + progress`; rotates `status.md` via `mb-status-rotate.sh --apply`) | `references/mb/aliases.md` |
| `plan <type> <topic>` | Create a plan | `references/mb/plan.md` |
| `brief <topic>` | Formalize a raw request plus attached documents into a one-page brief under `briefs/<topic>/` — first stage of... (see `commands/brief.md`) | `references/mb/brief.md` |
| `discuss <topic>` | 5-phase requirements-elicitation interview → EARS-validated `context/<topic>.md` (Phase 1 Purpose & Users / Phase 2... | `references/mb/discuss.md` |
| `askme <topic>`, `ask_me <topic>` | **Alias for `discuss`** — same interview, easier to remember | `references/mb/discuss.md` |
| `groom <topic>` (also `grooming`) | Critical grooming session for any task/idea at any stage: challenge necessity + approach, cover white spots, propose... (see `commands/groom.md`) | `references/mb/groom.md` |
| `sdd <topic> [--force]` | Create Kiro-style spec triple `specs/<topic>/{requirements,design,tasks}.md` | `references/mb/sdd.md` |
| `openspec <import\|list\|status\|sync\|export> [args]` | OpenSpec ↔ MB round-trip: import, three-way sync, dry-run export, `export --new` via `scripts/mb-openspec.sh`; `/mb work <change-id>` runs it in place | `references/mb/openspec.md` |
| `config <init\|show\|validate\|path>` | Manage execution `pipeline.yaml` (spec §9) | `references/mb/config.md` |
| `pipeline <list\|new\|use\|show\|path\|validate>` | Manage **multiple named pipelines** under `<bank>/pipelines/<name>.yaml` (different models + workflow per pipeline) | `references/mb/pipeline.md` |
| `work [target] [--range A-B] [--dry-run]` | Execute stages from a plan | `references/mb/work.md` |
| `verify` | Verify plan execution (plan vs code) | `references/mb/verify.md` |
| `map [focus]` | Scan the codebase and write MD documents to `.memory-bank/codebase/` | `references/mb/map.md` |
| `upgrade` | Update the skill from GitHub (`git pull + re-install`) | `references/mb/upgrade.md` |
| `compact [--dry-run\|--apply]` | Status-based decay of old plans and notes; `--dry-run` (default) = reasoning only | `references/mb/compact.md` |
| `import --project <path> [--since YYYY-MM-DD] [--apply]` | Bootstrap MB from Claude Code JSONL (`~/.claude/projects/<slug>/*.jsonl`) | `references/mb/import.md` |
| `graph [--apply] [--cochange] [--questions] [src_root]` | Multi-language code graph | `references/mb/graph.md` |
| `wiki [--dry-run] [src_root]` | **Opt-in LLM layer**: codebase wiki + surprising-connection edges via host subagents (see `references/mb/wiki.md`) | `references/mb/wiki.md` |
| `tags [--apply] [--auto-merge]` | Normalize frontmatter tags: detect synonyms via Levenshtein ≤2 against a closed vocabulary and propose merges | `references/mb/tags.md` |
| `init [--minimal\|--full]` | Initialize Memory Bank. `--full` (default): RULES + CLAUDE.md with stack autodetect; `--minimal`: structure only | `references/mb/init.md` |
| `profile <subcommand>` | Manage rule profiles: `init`, `show`, `path`, `validate`, `set` (see `commands/profile.md`) | `references/mb/profile.md` |
| `rules <subcommand>` | Key rules block at the top of `CLAUDE.md`/`AGENTS.md`: `list`, `enable\|disable <id>`, `add "<text>"`, `remove <n>`,... (see `commands/rules.md`) | `references/mb/rules.md` |
| `language <code> [--comments <code>] \| off \| show` | Per-project response / code-comment language (`en ru es pt zh`), overriding the global install choice | `references/mb/language.md` |
| `install [<clients>]` | Install Memory Bank for the project | `references/mb/install.md` |
| `statusline [--force]` | Claude Code only | `references/mb/statusline.md` |
| `help [subcommand]` | Help | `references/mb/help.md` |
| `deps [--install-hints]` | Dependency check (required: `python3`, `jq`, `git`; optional: `rg`, `shellcheck`, `tree-sitter`, `PyYAML`) | `references/mb/deps.md` |
| `cost [--project <dir>] [--since N] [--json]` | Transcript cost report: per session (turns / tool calls / dispatches / tokens / peak context / compactions), per... | `references/mb/cost.md` |
| `coord <active\|append> [args]` | Read/write the cross-session coordination board without loading it | `references/mb/coord.md` |
| `idea <title> [HIGH\|MED\|LOW]` | Capture new idea in `backlog.md` with auto-generated monotonic `I-NNN` ID (priority defaults to `MED`) | `references/mb/idea.md` |
| `idea-promote <I-NNN> <type>` | Promote an idea → plan | `references/mb/idea-promote.md` |
| `adr <title>` | Capture Architecture Decision Record with auto-generated monotonic `ADR-NNN` ID in the ADR registry `adr.md` —... | `references/mb/adr.md` |
| `agree <subcommand>` | Running list of agreements in `<bank>/agreements.md` (`add [--supersedes N] \| defer \| reject \| question \| resolve \| list \| sync`) (see `commands/agree.md`) | `references/mb/agree.md` |
| `goal` | Scaffold `.memory-bank/goal.md` + `.memory-bank/project.md` from templates (copy-if-absent), then validate the goal... (see `commands/goal.md`) | `references/mb/goal.md` |
| `analyze-task` | Auto-classify goal + git-diff scope into ONE route and write it into the `mb-flow` fence (default Dynamic Flow router) (see `commands/analyze-task.md`) | `references/mb/analyze-task.md` |
| `flow <route>` | Explicitly select a route (skip auto-classification); the deterministic route-floor + firewall STILL apply (see `commands/flow.md`) | `references/mb/flow.md` |
| `drive [--goal PATH] [--budget TOK] [--serial] [--host-serial] [--resume [RUN_ID]]` | Plan a goal with the user, then run it unattended: `scripts/mb-drive.sh next` prints ONE action (`work`, `team`,... (see `commands/drive.md`) | `references/mb/drive.md` |
| `team <subcommand> [args]` | Run one task as parallel tracks in one tree: brief, per-track pipeline by size, fair resource locks (`mb-lock.sh`),... (see `commands/team.md`) | `references/mb/team.md` |
| `qa <run [all\|<name>\|@<tag>\|<dir>/] \| new <name> \| list \| bugs>` | Acceptance QA: md scenarios in `<bank>/qa/test_cases/` run by the `mb-qa-runner` subagent (browser, CLI, API);... (see `commands/qa.md`) | `references/mb/qa.md` |
| `migrate-structure [--dry-run\|--apply]` | One-shot v3.0 → v3.1 structural migrator | `references/mb/migrate-structure.md` |
| (unrecognized) | Search by `$ARGUMENTS` | `references/mb/context.md` |

---

## Loading a route

The table above only routes. After picking the row for the first word of `$ARGUMENTS`, read its reference file `$SKILL_DIR/references/mb/<name>.md` (the third column) and follow it; do not execute a subcommand from this file alone. Load only the matched file. An unrecognized first word is a search over `$ARGUMENTS` (`references/mb/context.md`).

`/mb help` prints this table; `/mb help <subcommand>` prints that subcommand's reference file (`references/mb/help.md`).

---

## General Rules

- If `.memory-bank/` does not exist and the command is not `init` — report `[MEMORY BANK: INACTIVE]` and suggest `/mb init`
- After execution — show the user a short result summary
- progress.md = APPEND-ONLY
- Numbering is global: H-NNN, EXP-NNN, ADR-NNN
