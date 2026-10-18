# Cross-agent setup (Stage 8, v3.0)

Memory Bank works across 7+ AI coding clients. Canonical global skill lives under
`~/.claude/skills/skill-memory-bank`; Claude, Codex, and Cursor consume it through
managed aliases (`~/.claude/skills/memory-bank`, `~/.codex/skills/memory-bank`,
`~/.cursor/skills/memory-bank`). OpenCode also gets native global files under
`${XDG_CONFIG_HOME:-$HOME/.config}/opencode/`. Cursor additionally receives global hooks, slash commands,
an `AGENTS.md` marker section, and a paste-ready rules file at the user level.
Per-project adapters write client-specific configs + hooks.

## Supported clients

| # | Client | Native hooks | Config format |
|---|--------|--------------|---------------|
| 1 | Claude Code | Full (SessionEnd/PreCompact/PreToolUse) | `~/.claude/settings.json` |
| 2 | **Cursor** (1.7+) | **Full global + project, CC-compat** `hooks.json` | **Global:** `~/.cursor/{skills,hooks,commands,AGENTS.md,memory-bank-user-rules.md,hooks.json}` · **Project:** `.cursor/rules/*.mdc` + `.cursor/hooks.json` |
| 3 | Windsurf | Cascade Hooks (JSON+shell) | `.windsurf/rules/*.md` + `.windsurf/hooks.json` |
| 4 | Cline | `.clinerules/hooks/*.sh` | `.clinerules/*.md` + `hooks/` |
| 5 | Kilo | ❌ (FR #5827 open) — git-hooks fallback | `.kilocode/rules/*.md` |
| 6 | OpenCode 2 | V2 plugin `setup`; native command, session and tool hooks; memory tier opt-in | `${XDG_CONFIG_HOME:-$HOME/.config}/opencode/` + project `AGENTS.md` and `.opencode/` |
| 7 | Codex | Global native hooks + skill and roles | `~/.codex/skills/memory-bank` + `~/.codex/AGENTS.md` + `~/.codex/hooks.json` + optional project settings |
| 8 | Pi Code | Global skill + prompt templates + `AGENTS.md` | `~/.pi/agent/skills/memory-bank`, `~/.pi/agent/prompts/*.md`, `~/.pi/agent/AGENTS.md` + optional project `AGENTS.md` |

## Storage modes per agent

Memory Bank supports **local**, **global**, and **rules-only** storage modes. The table below shows per-agent support and global bank locations.

| Agent | Global config dir | Local mode | Global mode | Rules-only |
|-------|-------------------|------------|-------------|------------|
| Claude Code | `~/.claude` | `/mb init --storage=local` | `/mb init --storage=global --agent=claude-code` | ✅ `[MEMORY BANK: ABSENT]` |
| Cursor | `~/.cursor` | `/mb init --storage=local` | `/mb init --storage=global --agent=cursor` | ✅ `[MEMORY BANK: ABSENT]` |
| Codex | `~/.codex` | `/mb init --storage=local` | `/mb init --storage=global --agent=codex` | ✅ `[MEMORY BANK: ABSENT]` |
| OpenCode | `${XDG_CONFIG_HOME:-$HOME/.config}/opencode` | `/mb init --storage=local` | `/mb init --storage=global --agent=opencode` | ✅ `[MEMORY BANK: ABSENT]` |
| Pi Code | `~/.pi/agent` | `/mb init --storage=local` | `/mb init --storage=global --agent=pi` | ✅ `[MEMORY BANK: ABSENT]` |
| Windsurf | `~/.windsurf` | `/mb init --storage=local` | via `MB_AGENT=windsurf` (adapter-only) | ✅ rules via adapter |
| Cline | `~/.cline` | `/mb init --storage=local` | via `MB_AGENT=cline` (adapter-only) | ✅ rules via adapter |
| Kilo | `~/.kilocode` | `/mb init --storage=local` | via `MB_AGENT=kilo` (adapter-only) | ✅ rules via adapter |

**Notes:**
- **Local mode** — bank lives in the repo (`.memory-bank/`), committable, team-shared. Default of `/mb init`.
- **Global mode** — bank lives under `~/.<agent>/memory-bank/projects/<id>/.memory-bank`, personal storage, **do not commit to the repo**. Requires `--storage=global --agent=<agent>` on init.
- **Rules-only mode** — no `/mb init` at all; engineering rules (TDD, SOLID, Clean Architecture, DRY/KISS/YAGNI) are always-on via globally installed rules files; Memory Bank lifecycle commands stay inactive. Valid steady state for projects that want rules without bank overhead.
- Native-skill agents (Claude Code, Cursor, Codex, OpenCode, Pi) support all three modes directly. Adapter-only agents (Windsurf, Cline, Kilo) support local and rules-only; global mode is available via `MB_AGENT` env override.
- OpenCode global host files honor XDG; the shared bank registry remains at `$HOME/.config/opencode/memory-bank/registry.json`. XDG does not relocate that registry.

## Install

```bash
# Global install + cross-agent adapters in one command
bash install.sh --clients claude-code,cursor,windsurf --project-root .

# All supported clients
bash install.sh --clients claude-code,cursor,windsurf,cline,kilo,opencode,codex,pi --project-root .

# Select project adapters; global host resources still update
bash install.sh --clients cursor,opencode --project-root ~/my-project
```

**Flags:**
- `--clients <list>` — comma-separated project adapters. Default: `claude-code` only; not a global-host selector.
- `--project-root <path>` — where to place adapters. Default: `$PWD`.
- `--help` — full usage.

### OpenCode-only lifecycle

Use the existing installer with an explicit scope, from a stable bundle location:

```bash
memory-bank install --only opencode --project-root ~/my-project --non-interactive
# Explicit extension opt-in; retained on subsequent installs/updates:
memory-bank install --only opencode --project-root ~/my-project --non-interactive --with-extensions=opencode
memory-bank uninstall --only opencode --project-root ~/my-project --non-interactive
```

The same flags work with `bash install.sh` / `bash uninstall.sh`. This scope points
only OpenCode's skill alias directly at the selected bundle; it does not replace
the shared Claude alias, change other hosts, rewrite user OpenCode configuration,
or select global rules/pipelines. MB instruction blocks may be refreshed, retaining
user text outside them. Conflicting `--clients`, non-OpenCode extensions, `--key-rules`
and scoped uninstall `--force` are refused before installation writes.

Fresh scoped installs keep ownership/options in
`${XDG_CONFIG_HOME:-$HOME/.config}/opencode/.mb-install-manifest.json`, outside the
package bundle. A plain `memory-bank install` then retains this scope and recorded
extension opt-in, including after package updates. `mb-upgrade.sh` also accepts
`--only opencode --with-extensions=opencode`. Package managers independently replace
their own bundle; the installer cannot isolate those changes for other bundle users.

Edited or hashless resources are preserved with a nonzero refusal. Restore the
authoritative manifest or arrange separately approved exact manual replacements;
matching incoming bytes or managed markers do not authorize adoption. For an owned
older mixed install, explicitly select its existing record with `MB_MANIFEST_PATH`
on install/update/uninstall; keep this override across updates. Scoped removal
retains other-host entries in that record. Known conflicts are preflighted; handled
I/O failures retain the existing recovery material when restoration cannot finish.
This is not whole-install atomicity, crash recovery or concurrent-installer support.

### Default global resources (A25 / CDX-I13)

Without an explicit or recorded `--only` scope, `install.sh` calls
`install_opencode_global_agents`, `install_codex_global_agents`, and
`install_pi_global_agents` on every run, **independently of `--clients`**.
That means the global skill alias, global `AGENTS.md` entrypoint, and prompt templates for
OpenCode, Codex, and Pi are installed even when `--clients` doesn't include them — so those
hosts are ready to use the moment you open them, without a separate install step. Only the
**project-local** adapter (`.codex/config.toml`, `.opencode/plugins/…`, project `AGENTS.md`,
etc.) is actually gated by `--clients`.

`--clients` still selects project adapters only; use `--only opencode` for isolation.

## Per-client cheatsheet

### Cursor (full global parity + project adapter)

Cursor is a first-class **global** target: `install.sh` writes all six artifacts
automatically with **no `--clients cursor` flag required**. The project-level
adapter (`.cursor/rules/*.mdc` + `.cursor/hooks.json`) is an optional add-on.

**Global install (always):**

```bash
bash install.sh --non-interactive
# or: memory-bank install
```

Creates under `~/.cursor/`:
- `skills/memory-bank/` — symlink on canonical skill bundle (auto-discovered by Cursor)
- `hooks.json` — ten hook commands tagged `_mb_owned: true` (scripts run from skill bundle `~/.cursor/skills/memory-bank/hooks/`, not copied to `~/.cursor/hooks/`):
  `sessionStart` (auto-context), `sessionEnd` (autosave), `preCompact` (reminder),
  `beforeShellExecution` (block-dangerous), four `preToolUse` entries (protected paths, EARS, context-slim, sprint-guard),
  two `postToolUse` entries (file-change-log, plan-sync)
- `commands/*.md` — user-level slash commands mirrored from the skill
- `agents/mb-*.md` — the roles as native [Cursor subagents](https://cursor.com/docs/agent/subagents)
  (dispatch by name via the Task tool or `/mb-backend …`). Rendered with
  `scripts/mb-agent-render.py --host cursor`: partials composed in, frontmatter cut to
  `name`/`description`, no `model` so the subagent inherits the parent model. Cursor also reads
  `~/.claude/agents/`; on a same-name clash `.cursor/` wins, so these copies replace the Claude ones.
  `adapters/cursor.sh uninstall-global` removes only the files listed in `~/.cursor/.mb-manifest.json`
- `AGENTS.md` — marker section `memory-bank-cursor:start/end` (managed block,
  user content above/below is preserved)
- `memory-bank-user-rules.md` — paste-ready bundle for **Settings → Rules → User Rules**
  (Cursor has no file API for global User Rules; this is a one-time manual copy-paste)

**Cursor User Rules paste flow:**

```bash
# macOS
pbcopy < ~/.cursor/memory-bank-user-rules.md
# Linux
xclip -selection clipboard < ~/.cursor/memory-bank-user-rules.md
```

Then in Cursor: Settings → Rules → User Rules → paste.

The paste file includes version markers `<!-- memory-bank:start vX.Y.Z -->` … `<!-- memory-bank:end -->`.
Cursor cannot write User Rules via file API — manual paste only.

**Optional project adapter:**

```bash
bash install.sh --clients cursor --project-root ~/my-project
# or: memory-bank install --clients cursor --project-root ~/my-project
# or directly: adapters/cursor.sh install ~/my-project
```

Creates:
- `.cursor/rules/memory-bank.mdc` — YAML frontmatter (`alwaysApply: true`) + RULES.md
- `.cursor/hooks.json` — CC-compat, all ten events wired to skill-bundle hook scripts + `MB_AGENT=cursor`
- No `.cursor/hooks/*.sh` copies — hooks execute from `~/.cursor/skills/memory-bank/hooks/` or repo skill bundle

**Limitation (IDE vs CLI hook firing):** The Cursor *agent CLI* fires the full CC-compatible hook
set. The Cursor *IDE* does not guarantee every hook event (notably `sessionEnd`) fires on every
interaction — treat IDE auto-capture as best-effort and rely on explicit `/mb done` for durable
session closure. See [docs/cursor-extension.md](cursor-extension.md#limitations) for the
architecture-level detail.

### Windsurf

```bash
adapters/windsurf.sh install ~/my-project
```

Creates:
- `.windsurf/rules/memory-bank.md` (`trigger: always_on` frontmatter)
- `.windsurf/hooks.json` (Cascade, events: `user-prompt-submit`, `model-response`)
- Pre-hooks exit with code `2` to block.

### Cline

```bash
adapters/cline.sh install ~/my-project
```

Creates:
- `.clinerules/memory-bank.md` (`paths: ["**"]` frontmatter)
- `.clinerules/hooks/before-tool.sh` — blocks `rm -rf /` family (exit 2)
- `.clinerules/hooks/after-tool.sh` — auto-capture (idempotent per `sessionId`)
- `.clinerules/hooks/on-notification.sh` — weekly compact reminder (opt-in)

### Kilo (git-hooks fallback mandatory)

```bash
adapters/kilo.sh install ~/my-project   # must be a git repo
```

Creates:
- `.kilocode/rules/memory-bank.md` — rules
- `.git/hooks/post-commit` + `.git/hooks/pre-commit` (via `git-hooks-fallback.sh`)

Post-commit auto-captures to `progress.md` (respects `.session-lock`,
`MB_AUTO_CAPTURE=off|strict|auto`). Pre-commit warns on staged `<private>` blocks.

**Why git-hooks:** Kilo has no native lifecycle hooks — FR
[Kilo-Org/kilocode#5827](https://github.com/Kilo-Org/kilocode/issues/5827).

### OpenCode

**OpenCode 2 integration draft: final acceptance is pending.** Enable the native
memory tier explicitly:

```bash
bash install.sh --clients opencode --project-root ~/my-project --with-extensions=opencode
```

`--clients` selects project adapters only: the full installer still updates global
host resources. OpenCode host files use `${XDG_CONFIG_HOME:-$HOME/.config}/opencode/`
(`AGENTS.md`, `commands/`, the skill alias and opted-in roles); the bank registry
stays at `$HOME/.config/opencode/memory-bank/registry.json`. The project uses shared
`AGENTS.md`, `.opencode/commands/`, `.opencode/agent/` and the auto-discovered
`.opencode/plugins/memory-bank.js`. No global lifecycle plugin is installed.

**Native boundary.** The bootstrap imports the bundle's
[`{id, setup(ctx)}` plugin](../adapters/opencode_plugin.mjs). It uses command
bindings, `ctx.session.hook` for `context`, `prompt` and `compaction`, and native
tool-before/tool-after hooks. Cleanup disposes registrations and subscriptions.
Parents and children receive current Key rules, task context and pointers to
applicable [detailed RULES](../rules/RULES.md), not full rulebook copies.
Native `subagent` dispatch takes `agent`, `description` and `prompt`; `model` is optional.

**Memory and retrieval** ([source](../adapters/opencode_session.mjs)):
- `session.execution.succeeded` reconciles completed root turns once into shared session records, with model-free
  extractive sections: What changed, Decisions, Open questions and Files. Private
  spans and secrets are filtered; tool bodies, reasoning and attachment contents
  are excluded. Children receive context but cannot capture or close the parent
  bank; foreign project/location/workspace events are excluded.
- `MB_SESSION_CAPTURE=off` disables completed-turn capture independently of
  `MB_AUTO_CAPTURE`, which controls the legacy progress stub. Context autoload and
  precompact handoff retain their own switches. No bank is created implicitly.
- Restore uses core/recent memory and persisted handoff. Optional automatic recall
  uses the shared in-memory BM25 retriever and bounded, filtered note/session bodies;
  it creates no persistent index and runs no hidden semantic catchup.
  Explicit graph/semantic helpers remain available through
  [`mb-graph.sh` and `mb-code-context.py`](../SKILL.md#graphrag-lite-retrieval-routing).
- No implicit paid summarizer or Claude CLI fallback runs. An external summarizer
  requires explicit `MB_SUMMARIZE_BIN`; ordinary capture is model-free.

**Workflow and guards** ([source](../adapters/opencode_workflow.mjs)):
- `/mb work` and `/work` reuse the selected pipeline and canonical item/step,
  Eval and checkbox helpers. Native guards enforce dangerous-command,
  protected-path, EARS and budget policies before actions; guard errors refuse
  the action, optional retrieval failures do not. Writes reuse shared post-write sync.
- Explicit provider/model/variant pins remain authoritative. Requested inheritance
  uses the exact parent reference for that run without changing permanent pins.
  Unsupported selections refuse explicitly; permissions and nesting are not widened.
  OpenCode 2.0.29 Markdown roles retain separate `model` and `variant` fields.
- Grouped canonical `done; flip; clear` (including repeated clear) retains and
  revalidates run-specific completion proof before releasing the run override.
  Failed Eval, stale checkboxes, missing state and idle are not completion proof.
  A plan with no declared Eval stays `UNVERIFIED`, not verified success.
- Resume unfinished work explicitly with the same target, flags and matching
  `--run-id`; foreign/prior runs are not adopted. After reload, re-invoke `/mb work`;
  transparent continuation is not guaranteed.

**Limits and safe upgrades:**
- Capture reconciles only active context through public `ctx.session.context`:
  at most the last 128 messages; serialized batches above 512 KiB are rejected.
  The API returns the active array before local slicing, so this is not a transport
  or pagination bound. A 1 MiB session-record ceiling stops new commits without
  overwriting prior data. Compacted/deleted history cannot be replayed; opaque
  provider-native compaction coverage is unproven.
- Session idle never certifies done; there is no native blocking Stop veto.
  Tool, commit and workflow gates remain the enforcement points.
- AGR-110 cleanup covers process groups and observed descendants of trusted bundled
  hooks only. Fast unobserved reparenting or a detached fork/`setsid` can escape;
  no OS sandbox, absolute containment or concurrent-filesystem safety is promised.
- On whole-file user-edited or unowned collisions, the installer refuses replacement
  or removal and leaves files in place. Inspect ownership and reconcile explicitly
  with the owner; do not delete or reset configuration to bypass a refusal.
  A manifest entry alone is not removal authority.
- Automatic OpenCode upgrades require verifiable ownership; hashless v5.3.1 installs and files left after manifest deletion are preserved and automatic replacement is refused.
  Manual migration requires separately approved exact preimages and replacements; inferred options, matching bytes and existing backups do not authorize adoption.

API background:
[V2 migration](https://opencode.ai/v2/docs/migrate-v1),
[V2 plugins](https://opencode.ai/v2/docs/build/plugins).

### Codex (OpenAI)

The standard installer registers the skill, `AGENTS.md`, native agent roles, and all
eight Memory Bank lifecycle hooks globally. `CODEX_HOME` selects the Codex directory;
the default is `~/.codex`. Hooks run across projects after the user reviews and trusts
their current definitions in Codex `/hooks`. Installation does not grant that trust.

```bash
bash install.sh --clients codex --project-root ~/my-project
```

The selected project receives shared `AGENTS.md` and `.codex/config.toml` settings.
Where global hooks are installed, the adapter removes its own local legacy/native
registrations to prevent duplicate execution and preserves foreign hooks. For other
previously configured projects, re-run `adapters/codex.sh install PROJECT_ROOT`.
Standalone project adapters without global native hooks retain the legacy fallback.

Global agent roles use the shipped Codex model profile, independent of the project
from which installation runs. Explicit `adapters/codex.sh render-agents PROJECT_ROOT`
can apply a project's pipeline to the global roles; reload Codex afterward. Per-call
model/effort overrides depend on the host's support for overriding loaded roles.

See [native Codex hooks](../references/codex-native-hooks.md) for event mappings,
trust, migration, model-free conversation capture, child context and remaining limits.

### Pi Code

Global Pi support is installed automatically by `memory-bank install`:

- `~/.pi/agent/skills/memory-bank` — global Pi skill alias
- `~/.pi/agent/prompts/*.md` — Pi slash prompt templates (`/mb`, `/start`, `/done`, `/plan`, etc.)
- `~/.pi/agent/AGENTS.md` — always-loaded Memory Bank entrypoint + core rules

After installing in a running Pi session, run `/reload`.

Optional project adapter:

```bash
adapters/pi.sh install ~/my-project
# or: memory-bank install --clients pi --project-root ~/my-project
```

The project adapter writes shared `AGENTS.md`. If the project is a git repo it
also installs the git-hooks fallback; otherwise it safely installs only
`AGENTS.md`. `MB_PI_MODE=skill` is supported for compatibility, but it leaves an
existing global Pi skill symlink unchanged so it cannot overwrite the bundled
`SKILL.md` installed by `memory-bank install`.

## Shared AGENTS.md coexistence

OpenCode, Codex, and Pi (agents-md mode) all use `AGENTS.md`. Cline also reads it
automatically. Multiple MB adapters installing at once share a single marker section:

```markdown
<!-- memory-bank:start -->

# Memory Bank — Project Rules
...

<!-- memory-bank:end -->
```

Ownership is refcounted in `.mb-agents-owners.json`:

```json
{
  "owners": ["opencode", "codex", "pi"],
  "initial_had_user_content": false
}
```

**Uninstall rules:**
- Remove one client → refcount decremented, section kept
- Remove last client → managed section removed; delete only a genuinely empty remainder, preserving later user additions.

## Hook matrix — our hook categories → client events

Our own lifecycle set is broader than 4 events (see `settings/hooks.json`: `Setup`,
`PreToolUse`, `PostToolUse`, `Notification`, `PreCompact`, `Stop`, `UserPromptSubmit`,
`SessionStart`, `SessionEnd`) — the table below groups them into the cross-client-relevant
categories; not every category has an equivalent on every host.

| Our hook | Cursor | Windsurf | Cline | Kilo | OpenCode | Pi | Codex |
|----------|--------|----------|-------|------|----------|-----|-------|
| SessionStart context injection | `sessionStart` (`mb-session-start-context.sh`) | — | — | — | `ctx.session.hook("context")`: root/child rules; opt-in memory restore | — | global `SessionStart` and `SubagentStart` |
| Stop turn capture (creates `session/*.md`) | `stop` (`mb-session-turn.sh`, CC-compatible — adapter-parity T7/REQ-021) | — | — | — | Opt-in completed-root capture via `ctx.session.context`; no Stop veto | (session-memory extension, accept-path only) | global `Stop` (model-free Codex capture) |
| SessionEnd auto-capture (summarize) | `sessionEnd` (`mb-session-end.sh`, CC-compatible) | `model-response` | `afterToolExecution` | `post-commit` (git) | `session.execution.succeeded` reconciles completed root turns; model-free capture, no Stop veto | `post-commit` (git-hooks-fallback, same mechanism as Kilo/Codex) | global `SessionEnd` (bounded extractive fallback); project commit fallback remains separate |
| PreCompact actualize | **`preCompact`** | — | — | — | `ctx.session.hook("compaction")`: portable handoff; public surface only | — (no installed fallback; git hooks only fire on commit) | global `PreCompact` (capture + portable handoff) |
| PreToolUse block | `preToolUse`+`beforeShellExecution` | Cascade pre-hook (exit 2) | `beforeToolExecution` (exit 2) | rules guidance | `ctx.tool.hook("execute.before")`: portable guard refusal | — (no installed fallback) | global `PreToolUse` (Bash/edit/agent guards) |
| Weekly compact reminder | `sessionEnd` check | `model-response` check | `onNotification` | git-fallback | Idle notice only, never completion certification | git-fallback (`post-commit` staleness check) | global `Stop` freshness reminder |

**Pi native extension status:** `adapters/pi_session_memory_extension.ts` (a TypeScript extension listening
to `session_start`/`input`/`tool_execution_end`/`agent_end`/`session_before_compact`/`session_shutdown`
events) ships in the bundle as source AND has a real, opt-in install path as of adapter-parity T3:
accepting the Pi parity-extension offer (`install.sh --clients pi --with-extensions=pi` — `--clients pi`
is required, not optional: the offer only ever applies to hosts present in `--clients`, and it defaults
to `claude-code` when omitted — or the interactive/CI-flag prompt) installs it — alongside
`pi_graph_rag_extension.ts` — into the GLOBAL
`~/.pi/agent/extensions/` directory, no separate project-local run required. The table row above
(git-hooks-fallback/post-commit) still describes the DEFAULT, pre-consent tier — a bare `--clients pi`
install with the offer declined or skipped never installs the extension (opt-in only, AGR-013); once
accepted, Pi graduates to the same rich `session/*.md` capture tier as Claude Code/Cursor, plus the
update-notify notice on every session start (REQ-013).

## Resource availability matrix

| Resource | Claude global | Codex global | Cursor global | Native host surface in Codex |
|----------|---------------|--------------|---------------|-------------------------------|
| `SKILL.md` | `~/.claude/skills/memory-bank/` | `~/.codex/skills/memory-bank/` | `~/.cursor/skills/memory-bank/` | Yes, via skill discovery |
| `commands/` | bundled + Claude commands installed | bundled in Codex skill alias | bundled + mirrored to `~/.cursor/commands/` | No separate native slash-command install |
| `agents/` | bundled + Claude global agents installed | rendered roles in `$CODEX_HOME/agents/` (default `~/.codex/agents/`) | rendered roles in `~/.cursor/agents/mb-*.md` (native subagents) | Named native subagent roles |
| `hooks/` | bundled + Claude global hooks installed | eight events in `$CODEX_HOME/hooks.json` (default `~/.codex/hooks.json`) | bundled at `~/.cursor/skills/memory-bank/hooks/` + twelve `_mb_owned` entries in `~/.cursor/hooks.json` | Global native lifecycle hooks; user trust required |
| Global rules | `~/.claude/CLAUDE.md` managed section | `~/.codex/AGENTS.md` managed section | `~/.cursor/AGENTS.md` managed section **+** paste-file for Settings → Rules → User Rules | n/a |

## Uninstall

Every adapter has idempotent `uninstall`:

```bash
adapters/cursor.sh uninstall ~/my-project
adapters/kilo.sh uninstall ~/my-project
# ...
```

Adapters preserve user content:
- User hooks in `.cursor/hooks.json` / `.windsurf/hooks.json` — only `_mb_owned: true`
  entries are removed.
- User rules in `.clinerules/` / `.kilocode/rules/` — only our `memory-bank.md` removed.
- User `AGENTS.md` content — preserved via refcount + marker section removal.
- User `.git/hooks/*` — restored from `.pre-mb-backup` backups.

## Troubleshooting

**Q: My `AGENTS.md` lost its custom sections after uninstall.**
A: Only our managed marker sections are removed; content outside them is preserved.
Compare the current file with a saved version and reconcile missing sections with
the owner. Do not overwrite the whole file: that can discard newer user edits.

**Q: Cursor hooks don't fire reliably (e.g. `sessionEnd` auto-capture missing).**
A: This is an IDE limitation, not a CLI one — the Cursor *agent CLI* fires the full
CC-compatible hook set, but the Cursor *IDE* does not guarantee every hook event fires on
every interaction. Rely on explicit `/mb done` for durable session closure in the IDE; see
[docs/cursor-extension.md](cursor-extension.md#limitations).

**Q: I installed Memory Bank but Cursor's User Rules panel is empty.**
A: Cursor exposes **no file API for global User Rules** — they are only editable
via Settings → Rules → User Rules. `install.sh` writes a paste-ready file to
`~/.cursor/memory-bank-user-rules.md`. Run:
```bash
# macOS
pbcopy < ~/.cursor/memory-bank-user-rules.md
# Linux
xclip -selection clipboard < ~/.cursor/memory-bank-user-rules.md
```
Then paste once into Settings → Rules → User Rules. This is a one-time manual
step per machine.

**Q: Does Cursor need `--clients cursor` for the global install?**
A: No. Global Cursor artifacts (`~/.cursor/skills/`, `~/.cursor/hooks.json`,
`~/.cursor/commands/`, `~/.cursor/AGENTS.md`, `~/.cursor/memory-bank-user-rules.md`)
are written by `install.sh` unconditionally. Pass `--clients cursor` only when
you also want the project-level adapter (`.cursor/rules/*.mdc` + `.cursor/hooks.json`)
in your current project.

**Q: Codex CLI ignores `.codex/hooks.json`.**
A: Check three things (verified on Codex CLI 0.144.1, where `codex features list` shows
`hooks … stable true`): the project must be trusted (`[projects."<path>"] trust_level =
"trusted"` in `~/.codex/config.toml`); the file must carry no top-level key besides `hooks`
(Codex skips the whole file otherwise, without an error); and hooks installed by an older
MB version need a re-run of `adapters/codex.sh install` to migrate. `codex exec` prints
`hook: UserPromptSubmit Blocked` when the guard fires.

**Q: Pi doesn't show `/mb` after install.**
A: Run `/reload` in the current Pi session. Pi prompt templates are installed to
`~/.pi/agent/prompts/*.md`; new sessions pick them up automatically. If you had
an older local Pi skill directory, its backup is stored under
`~/.pi/agent/.memory-bank-backups/` so Pi does not discover it as a duplicate
skill.

**Q: Kilo adapter fails with "requires git repo".**
A: Kilo has no native hooks → git-hooks-fallback is mandatory. Run `git init`
before `adapters/kilo.sh install`, or use a different client.

**Q: Multiple adapters installed, uninstalling one breaks others.**
A: Should not happen — refcount design prevents it. If it does, file an issue with
`.mb-agents-owners.json` content attached.

## See also

- [Research notes (2026-04-20)](../.memory-bank/notes/2026-04-20_03-36_cross-agent-research.md)
- [Plan Stage 8](https://github.com/fockus/skill-memory-bank/blob/main/.memory-bank/plans/done/2026-04-20_refactor_skill-v2.1.md)
- [ADR-010 (Codex)](../.memory-bank/adr.md)
- [ADR-011 (Repo migration)](../.memory-bank/adr.md)
