# Native Codex hooks

## Contents

- [Installation and lifecycle](#installation-and-lifecycle)
- [Conversation capture and privacy](#conversation-capture-and-privacy)
- [Remaining integration gaps](#remaining-integration-gaps)

## Installation and lifecycle

The standard `install.sh` / `memory-bank install` installs eight lifecycle hooks in
`$CODEX_HOME/hooks.json` (default `~/.codex/hooks.json`) alongside the global skill and
agent roles. This runs independently of the project client selection, so new projects
inherit the hooks without a project installation. The command uses the installed skill
alias; as with other Memory Bank aliases, its linked bundle must remain installed.

Registration and trust are separate. Codex skips new or changed non-managed hook
definitions until the user reviews and trusts them in `/hooks`. The installer never
changes trust or approval policy. An explicitly disabled hooks feature stays disabled.
Reopen/resume after installation, inspect `/hooks`, and check `hook/completed` events
before claiming automatic execution. An isolated CLI 0.160.0 native probe confirmed
all eight user-scope MB events, automatic capture in chat A and recall in chat B,
child context, source-edit logging, completed compaction and SessionEnd (542 ms).
Foreign plugin events were distinguished by source; normal approval policy stayed unchanged.
The harness has earlier execution evidence from Desktop 0.153.4.

For a manual project installation, the additive helper remains available:

```bash
python3 "$SKILL_DIR/adapters/codex-native-hooks.py" install /absolute/project/.codex
```

The helper preserves unrelated hooks/config, backs up existing hooks once, and is
idempotent. `uninstall` removes only Memory Bank-owned entries. The standard project
adapter removes owned local registrations when global hooks exist, avoiding duplicate
execution. Existing projects not selected during installation retain their local hooks;
re-run their project adapter after the global install to migrate them. Do not manually
add a project registration on top of the global one.

The runner reuses the existing checks rather than copying their rules. Native Codex
normalizes `exec_command` to `Bash` for hook matching (see the protocol reference):

| Event | Action |
|---|---|
| SessionStart | Bounded core/handoff restoration, rebuild recent index from captured sessions, recent memory, graph freshness and update notification; reset graph nudge after compaction |
| SubagentStart | Bounded existing-bank context and applicable skill/rule pointers; child completion remains separate from root closure |
| UserPromptSubmit | Relevant-memory retrieval |
| PreToolUse | Dangerous Bash commands, protected paths, EARS for added requirement files, graph nudge; map spawn_agent message to Agent prompt for slim/context-budget checks |
| PostToolUse | File-change checks/logging, graph queue and semantic-index invalidation; validate complete edited requirement files; sync changed plans and spec indexes |
| PreCompact / SessionEnd | Incremental root-session capture and portable handoff; SessionEnd has a shared 2.5-second deadline |
| Stop | Incremental root-session capture, flow closure, drive-resume, core-file-cap checks and freshness reminder |

Codex passes the `apply_patch` patch string in `tool_input.command`. The adapter extracts paths,
including move destinations. New requirement files are checked before writing;
updates are checked after writing because a patch can omit unchanged continuation
lines. A post-write rejection cannot undo the edit. Fix the file and revalidate.
Protected-path denials reuse the existing checker. Codex does not support its
Claude `ask` response, so this adapter selects `MB_PROTECTED_MODE=deny`.
When the user already authorized a protected edit, use the existing
`MB_ALLOW_PROTECTED=1` execution mechanism within that authorized scope.

Limitations: arbitrary shell/MCP writes do not produce a structured file diff;
run the explicit EARS/spec/plan checks after such writes. These hooks are not a
filesystem security boundary and do not prove the implementation works. Claude CLI summaries/judge and OS notification hooks are not registered; Codex
uses model-free extractive memory. Retain explicit `/mb done` for actualizing project
progress, checklists and decisions.
The global native installer does not add the old prompt-text blacklist or git hooks.
The project adapter retains its commit-time fallback; that fallback is not conversation capture.

Protocol reference: [OpenAI hook documentation](https://learn.chatgpt.com/docs/hooks).
The local `codex app-server generate-json-schema --experimental` and `hooks/list`
provide version-specific schemas, errors, current hashes and trust status.

Core context, handoff, recent history and semantic recall share resolution for local
ancestor banks, explicit `MB_PATH`, global registry entries and legacy storage. The
Codex registry honors `CODEX_HOME`. Isolated runner tests cover these paths; they do
not prove native event delivery.

A real model-free BM25 probe confirmed note edit → PostToolUse → dirty index →
updated recall on the next prompt. A source edit likewise refreshed the graph on
the next query, adding the new symbol and removing the old one. Recall intentionally
injects compact titles/source IDs; expand or read the note for its full contents.

## Conversation capture and privacy

The runner invokes `hooks/mb-codex-session.py` on root Stop, PreCompact and as a
bounded SessionEnd fallback. It reads the host-provided `transcript_path`, validates
session metadata and records user requests plus final assistant answers. Tools,
reasoning, developer instructions, commentary and inherited child transcripts are
excluded. Missing/unsupported transcripts fail open; the adapter does not search
other chats or initialize a bank.

Records have `agent: codex`, `summary_mode: extractive` and `summarized: true`: a
summary already exists, and no model generated it. Shared Claude catchup therefore
does not send these records to Claude. Private spans and recognized secrets are
removed before persistence; fenced code is omitted and each message is capped at
1600 characters with an explicit truncation marker. Filtering is pattern-based;
use `<private>` for information that must not enter project memory.

Cursor, pending sanitized state and live log are replaced atomically. Repeated
hooks and resumed transcripts do not duplicate turns; partial trailing records
are retried. Long sessions retain indexed parts, each bounded to 1 MiB. Existing
parts are read with the same bound; redirected session directories/locks/parts
are rejected using anchored no-follow descriptors. Explicit bank-root symlinks
resolve to the selected storage location. Capture is supported on POSIX hosts;
native Windows lacks the required descriptor/locking APIs and safely skips capture
(use WSL). Codex transcript JSONL is not a stable public format: unknown variants
are ignored rather than guessed.

`MB_SESSION_CAPTURE=off` disables transcript persistence while restoration and
recall remain available. `MB_AUTO_CAPTURE=off` controls the legacy progress stub;
Codex does not create that stub and continues rich session capture. Derived
`session/_recent.md` is rebuilt after capture and at SessionStart; an existing
semantic index is marked dirty for the next recall. Extractive memory does not
replace `/mb done` or automatically curate agreements, ADRs or notes.

## Remaining integration gaps

- **Native delivery:** registration and real helper probes do not prove host event
  delivery. Use `/hooks` to trust the exact definitions, then inspect completed
  events. SessionEnd is advisory; prefer Stop capture because end delivery cannot
  guarantee successful persistence after forced process termination.
- **Summary limits:** recent history may display several parts of a long session.
  Recall searches all indexed parts; use expand/read for full retained extracts.
  Existing Claude `/mb recap` replaces a progress stub and is not a Codex extractive
  record consumer. No model-backed summarizer or durable-note judge is wired.
- **Static agent roles:** global roles use the shipped Codex profile; project-specific
  rendering is explicit (`adapters/codex.sh render-agents PROJECT_ROOT`). Rendered
  reasoning effort respects role `thinking`. A running host may fix named-role
  model and effort at load time; render and reload roles for unsupported overrides.
  Global role rendering affects all projects.
- **Instruction loading:** global/project `AGENTS.md` supply the entry point and
  inline Key rules. Linked `RULES.md` is read explicitly, and `SKILL.md` uses skill
  progressive disclosure. Child context adds rule pointers; it does not inline the
  full rule book or capture a child's inherited transcript.
- **Graph limits:** file-scoped matching preserves qualified identities. Static,
  repository-local subprocess script paths now create dependency edges, so invoked
  runner tests can be found after a normal graph refresh. Dynamic invocation paths
  remain unknown; fall back to code search instead of assuming no tests exist.
- **Cost accounting:** `/mb cost` still reads Claude session data, not Codex usage.
- **Optional embeddings:** BM25 passed the real capture/recall probes. The optional
  embedding-store integration test also fails on unchanged HEAD; it is not certified.

These hooks provide context, memory and checks. Shell/MCP writes still need explicit
validation when no structured edit is delivered, and helper tests alone do not prove
native event delivery. The eight-event set deliberately excludes OS notifications,
permission handling and root closure on child completion.
