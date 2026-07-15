# Command reference

`/mb` is the single entrypoint for the whole toolkit — one command with subcommands, rather than
25 separate slash commands to remember. Every row below is available as `/mb <subcommand>`; a
handful also have short aliases (`/start`, `/done`, `/plan`, `/discuss`, `/sdd`, `/work`,
`/verify`, `/config`, `/pipeline`) that dispatch to the exact same underlying command.

| Subcommand | Purpose |
|---|---|
| `context` (or empty) | Collect and summarize current project context — status, checklist, active plan. |
| `start` | Extended session start: full context plus the active plan read in. |
| `search <query>` | Search core Memory Bank files. |
| `recall <query>` | Lexical recall over the session-memory log (`session/`) + `notes/`. |
| `recap <sid>` | Reconstruct a full `progress.md` entry from a session file that ended on an auto-capture stub. |
| `conflicts [--judge]` | Surface memory entries with high lexical overlap and an opposing/replacement assertion. |
| `consolidate [--apply]` | Fold old sessions into durable `notes/` candidates; archive them verbatim. |
| `research <query>` | Graph-first multi-source research — codebase, memory, library docs, prior art, web. |
| `note <topic>` | Create a note. |
| `agree <add\|question\|list\|sync>` | Running registry of confirmed decisions (`AGR-NNN`, supersedes-chain); active list mirrored into `CLAUDE.md`/`AGENTS.md`. |
| `update` | Actualize core files from real code-state analysis (no session summary required). |
| `doctor` | Find and fix internal Memory Bank inconsistencies. |
| `tasks` | Show unfinished tasks. |
| `index` | Registry of all entries. |
| `done` | End the session — actualize, note, and append progress. |
| `plan <type> <topic>` | Create a plan (`feature` / `fix` / `refactor` / `experiment`). |
| `discuss <topic>` | 5-phase requirements-elicitation interview producing an EARS-validated `context/<topic>.md`. |
| `sdd <topic> [--force]` | Create the spec triple `specs/<topic>/{requirements,design,tasks}.md`. |
| `config <init\|show\|validate\|path>` | Manage the project's `pipeline.yaml`. |
| `pipeline <list\|new\|use\|show\|path\|validate>` | Manage multiple named pipelines with different model routing per host. |
| `work [target] [--workflow NAME] [--range A-B]` | Execute a plan/spec through the composable implement→verify→(review→judge)→done loop. |
| `verify` | Verify plan/spec execution against the actual codebase — required before `done` when work followed a plan. |
| `map [focus]` | Scan the codebase, write `STACK` / `ARCHITECTURE` / `CONVENTIONS` / `CONCERNS` docs. |
| `upgrade [--check\|--force]` | Update a git-clone install of the skill from GitHub. |
| `compact [--dry-run\|--apply]` | Status-based archival decay for old completed plans and low-importance notes. |
| `import --project <path> [--apply]` | Bootstrap Memory Bank from Claude Code JSONL session transcripts. |
| `graph [--apply] [--cochange] [--questions] [--docs]` | Build/update the code graph (`codebase/graph.json` + `god-nodes.md`). |
| `wiki [--dry-run]` | Opt-in LLM layer: per-community codebase wiki + surprising cross-cutting connections. |
| `tags [--apply] [--auto-merge]` | Normalize frontmatter tags against a closed vocabulary. |
| `init [--minimal\|--full]` | Initialize Memory Bank in the current project. |
| `profile <subcommand>` | Manage rule profiles (role/stack/architecture/delivery-tuned rule sets). |
| `install [<clients>]` | Install Memory Bank for the project across one or more AI-agent clients. |
| `statusline [--force]` | Claude Code only — install the context-window statusline. |
| `help [subcommand]` | Print the router table, or the detailed section for one subcommand. |
| `deps [--install-hints]` | Check required/optional dependencies (`python3`, `jq`, `git`, …). |
| `idea <title> [HIGH\|MED\|LOW]` | Capture a new idea in `backlog.md` with an auto-generated `I-NNN` ID. |
| `idea-promote <I-NNN> <type>` | Promote a captured idea into a plan. |
| `adr <title>` | Capture an Architecture Decision Record with an auto-generated `ADR-NNN` ID. |
| `goal` | Scaffold `goal.md` + `project.md`, then validate the goal. |
| `analyze-task` | Auto-classify goal + git-diff scope into a Dynamic Flow route. |
| `flow <route>` | Explicitly select a Dynamic Flow route, skipping auto-classification. |
| `migrate-structure [--dry-run\|--apply]` | One-shot v3.0 → v3.1 structural migrator. |

## Getting details on one subcommand

```bash
/mb help                # router table (this page's source of truth)
/mb help work            # full "### work" section: behavior, examples, underlying scripts
/mb help compact         # full "### compact" section
```

`/mb help <subcommand>` extracts the exact `### <subcommand>` block from `commands/mb.md` — the
same content this page condenses, kept as the single source of truth so the two never drift.

## Related

- [/mb work](mb-work.md) — the execution engine, documented in full.
- [pipeline.yaml reference](pipeline-yaml.md) — the config `config`/`pipeline` manage.
- [Agents reference](agents-reference.md) — the specialist subagents `work`/`map`/`verify` dispatch.
