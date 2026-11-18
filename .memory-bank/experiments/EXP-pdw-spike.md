---
id: EXP-pdw-spike
date: 2026-11-19
status: no-go (adopt as engine) / ideas borrowed
decision: AGR-104
---
# EXP-pdw-spike: pi-dynamic-workflows in an isolated Pi agent dir

Package: `@quintinshaw/pi-dynamic-workflows` 3.15.2 (MIT). Pi 1.5.0. Isolated dir:
`PI_CODING_AGENT_DIR=<scratchpad>/pdw-agent` with only our `agents/mb-researcher.md` copied in.

## Isolation evidence
`ls -laT ~/.pi/agent` taken before and after the spike: `diff` reports the files identical (names, sizes, mtimes; e.g. `settings.json`
Nov 18 16:09:05, `AGENTS.md` Nov 18 16:10:51 unchanged).

## What ran
- `pi install npm:@quintinshaw/pi-dynamic-workflows` in the isolated dir: OK ("added 2 packages"), written to the scratch `settings.json` only.
- Live `fanout-synthesize` with `agentType: mb-researcher`: NOT completed. The isolated dir has no provider auth (the owner's
  `auth.json` was deliberately not copied), so `pi -p` produced no output and hung until killed after ~2 min. Per the track rule, this
  is recorded as the result, not worked around. Consequently nothing was piped into `mb-flow-verify.sh`.
- The three measurements below therefore come from the installed source (`src/agent-registry.ts`, `src/agent.ts`), not a live run.

## Measurements
1. **Roster binding.** `agentType` resolves `<PI_CODING_AGENT_DIR>/agents/*.md` and project `.pi/agents/*.md`. Bound: `tools`,
   `disallowedTools`, `model`, `thinking`, `isolation: worktree`, body as prompt. **`compose:` is not read** (the engineering-core
   partial our agents rely on is not composed unless the installer has already inlined it, as ours does). `effort:` is not read either
   (`thinking:` is). `mcp`, `skills`, `background` are parsed-and-ignored.
2. **Child tool scope.** `applyToolPolicy` filters Pi tool objects by an exact-case allowlist. `mb-researcher` declares Claude-style names
   (`Bash, Read, Grep, Glob, WebSearch, WebFetch, SendMessage`); Pi tools are lowercase (`read, bash, grep, find, ls`). By source
   reading, an unmodified roster file would leave the child with no coding tools (only `structured_output` and system tools). The roster
   would need Pi-specific frontmatter. This was not confirmed live (the dist modules need the Pi host to import; a standalone probe failed with
   a missing `@earendil-works/pi-coding-agent`). Children are in-process sessions sharing the parent's process, not separate `pi -p` processes.
3. **Cost vs `mb-fanout.sh` + `pi -p`.** Not measured (no model call possible without auth). Qualitatively: the package adds a model-authored
   workflow script, a run store, token accounting and a TUI; it also needs Pi >= 0.80.8 and a global package install. `mb-fanout.sh` stays
   stateless, host-agnostic and already feeds `mb-flow-verify.sh`.

## Go / no-go
**No-go** for adopting it as Pi's flow engine (confirms AGR-104): it would add a second runtime that bypasses our roster semantics
(`compose:`, tool names), cannot be verified without the owner's provider credentials, and duplicates `mb-fanout.sh`. **Go** for borrowing ideas
(done, no dependency): branch-output schema check and the dry-round stop rule, in `specs/dynamic-flow/design.md` (ADR-11) and
`flow-templates/patterns/loop-until-done.md`.

## Backlog entry text (for the orchestrator to add)
- IDEA (low): Pi roster tool-name mapping: our agents declare Claude-style tool names; if a Pi-side engine ever binds them, an adapter must
  map `Bash/Read/Grep/Glob` to `bash/read/grep/find`. Revisit only if a live run with credentials is approved.
