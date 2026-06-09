---
spec_id: mb-research-tooling-core
topic: mb-research as a first-class MB agent + shared tooling-core partial
status: ready
author: brainstorming-session
created: 2026-06-09
---

# Design — mb-research agent + mb-tooling-core partial

## 1. Problem & goals

Two gaps, surfaced during a repo audit:

1. **`mb-research` lives outside the skill.** It is a standalone, project-tuned skill
   (`~/.claude/skills/mb-research/SKILL.md`, customised for "FaberlicApp"). It already calls
   into Memory Bank scripts (`mb-graph-query.py`, `mb-semantic-search.py`) but is **not shipped
   or installed by `skill-memory-bank`**. There is no `mb-*` research role in the agent roster,
   unlike `mb-reviewer` / `plan-verifier`.

2. **The other MB agents don't know about the optional retrieval tools.** The graph-first
   routing (`code_context` / `graph_neighbors` / `graph_impact` / `graph_tests` / `search_code` /
   `recall`) is emitted **only** into the shared-format `AGENTS.md` by
   `adapters/_lib_agents_md.sh` (`## GraphRAG-lite routing`) — it reaches OpenCode/Codex/Pi but
   **never reaches the Claude sub-agent prompts** composed by `/mb work` (engineering-core +
   role delta). So the 9 dev-role implementers, the reviewer, and the plan-verifier currently
   fall back to blind `grep` even when a graph / semantic index exists.

**Goals**

- (A) Make `mb-research` a first-class, portable MB agent (`agents/mb-research.md`) with a
  `/mb research <query>` entrypoint — dispatchable from `/mb work` and the main thread.
- (B) Teach the other agents the optional retrieval tools through a single **shared partial**
  `agents/mb-tooling-core.md`, prepended alongside `mb-engineering-core.md`.

**Non-goals (YAGNI)**

- Refactoring `_lib_agents_md.sh` / `mb.md` to derive their routing text from the new partial
  (possible future consolidation — out of scope here).
- Removing or rewriting the user's local FaberlicApp `mb-research` skill (migration note only).
- Touching `mb-codebase-mapper` — it already builds and reasons over the graph.

## 2. Guiding invariants (already established in this repo — reused, not invented)

- **Fail-open doctrine** (verbatim in `_lib_agents_md.sh` and `commands/mb.md`):
  > *missing graph, stale graph, missing semantic provider, or unavailable native extension must
  > not block work — CLI scripts / `rg` / `read` are the universal fallback.*
  This is the answer to the optionality concern: graph and vector DB are opt-in; every tool
  reference is gated by graceful degradation, never a hard dependency.
- **Single routing vocabulary**: `code_context`, `graph_neighbors`, `graph_impact`,
  `graph_tests`, `search_code`, `recall` — identical to what `mb.md` and `_lib_agents_md.sh`
  already use, so the new partial and the new agent agree with the existing surfaces.
- **`tools:` in frontmatter ≠ MB scripts.** MB scripts run via `Bash` (which all agents already
  have). "Teach the agents" = prompt-level knowledge of *which* `Bash`/script to run; **no new
  tool is registered**.
- **Path convention**: source files write the canonical `~/.claude/skills/memory-bank/scripts/…`
  path; `install.sh::localize_path_inplace` rewrites it per client (codex → `~/.codex/...`,
  pi → `~/.pi/agent/...`). Consistent with how `mb.md` and the current `mb-research` SKILL
  already reference scripts.

## 3. Component A — `agents/mb-research.md`

A generalised, portable port of the current skill content.

**Frontmatter**
```yaml
name: mb-research
description: <research-question triggers — codebase "how does X work / who calls X /
  blast-radius / which tests cover X", project memory "what did we decide", library/API,
  prior-art, open web; graph-first, multi-source, file:line-grounded>
tools: Bash, Read, Grep, Glob   # NO Write/Edit — it researches, it does not write code
model: sonnet
color: <unused-by-roster>
```

**Body (de-FaberlicApp'd)**
- Routing table: pick source by question type — `graph_impact`/`graph_neighbors`/`graph_tests`
  (structural) → `search_code` (concept, opt-in embeddings) → `recall` (decisions/"why") →
  context7 (library docs, if MCP present) → `gh` (prior art, if installed/authed) →
  `WebSearch`/`WebFetch` (open web) → `Grep`/`Glob`/`Read` (raw/regex/freshly-changed).
- "When NOT to use" (single known file → just `Read`; editing → not this agent).
- "Optional-source availability" — explicit graceful degradation per source (context7 absent →
  web; `gh` missing → web; **graph/index absent → skip those rows, use `Grep`/`Read`**; mb-research
  must still work in a repo with no Memory Bank).
- Execution patterns: narrow → single routed command; broad sweep → fan-out parallel subagents.
- Output discipline (anti-hallucination): every structural claim backed by a graph query or
  `file:line`; library/web claims cite the source; state which source answered.

**Entrypoint** — `/mb research <query>` as a router section in `commands/mb.md`: dispatches the
`mb-research` agent via `Task`. Narrow question → one dispatch; broad/multi-area → fan-out.
Also available to the main thread and as blast-radius scouting before a multi-file change.

## 4. Component B — `agents/mb-tooling-core.md`

A `partial: true` block (mirrors `mb-engineering-core.md`), **not** a standalone agent.

**Content** — one compact section, *"Code-understanding tools (graph-first, fail-open)"*:

| Intent | Tool | Command (canonical path) |
|---|---|---|
| fuzzy "where is the logic for X" | `code_context` | `scripts/mb-code-context.py` |
| who calls / imports / defines X | `graph_neighbors` | `scripts/mb-graph-query.py neighbors` |
| change impact / reverse deps / blast-radius | `graph_impact` | `scripts/mb-graph-query.py impact` |
| which tests cover X | `graph_tests` | `scripts/mb-graph-query.py tests` |
| concept / synonym search | `search_code` | `scripts/mb-semantic-search.py` (BM25 default; `--backend embeddings` opt-in) |
| "what did we decide / why" | `recall` | `/mb recall <query>` |

Closes with the verbatim **Fail-open** sentence + one line: *"these indexes are optional; if
absent or stale, fall back to `Grep`/`Glob`/`Read` — never block."* Header note marks it as a
prepended partial, not dispatchable directly (same wording style as engineering-core).

## 5. Wiring (the accepted "+plumbing" cost)

- **`commands/work.md` §3a** — implement-step prompt becomes
  `engineering-core + tooling-core + role delta + item body` (today it is
  `engineering-core + role + item`). One added inline.
- **`commands/work.md` §3c (review)** and **`commands/verify.md`** — when dispatching
  `mb-reviewer` and `plan-verifier`, also inline `tooling-core` (these specialists are dispatched
  standalone and do **not** receive engineering-core).
- **`agents/mb-reviewer.md` / `agents/plan-verifier.md`** — add a standalone fallback note:
  *"If no tooling-core block is present above, read `agents/mb-tooling-core.md` first."*
  (Same pattern the role files already use for engineering-core.)
- **Roster docs** — `SKILL.md` agent list + `install.sh` agent-count message: mention the new
  agent; the `agents/` copy mechanism ships both new files automatically (`*.md` glob).
- **`adapters/_lib_agents_md.sh`** — no behavioural change required (its `GraphRAG-lite routing`
  section already covers AGENTS.md clients); only update if the agent count/listing must reflect
  the new entry.

## 6. Portability & optional-tools handling

- New files use canonical `~/.claude/skills/memory-bank/scripts/…`; install localization rewrites
  per client. **Verification needed**: confirm `localize_path_inplace` (or the `agents/` copy
  path) covers `agents/*.md` for codex/pi — if it does **not**, add the new files to the
  localized set so the script paths resolve under non-Claude clients.
- Every tool reference is fail-open: a `graph.json`-absent or embeddings-absent project degrades
  to `Grep`/`Read`. No agent gains a hard dependency on the graph or the vector index.

## 7. Testing (TDD — written first, RED before GREEN)

pytest (under `tests/pytest/`):
- `agents/mb-research.md` exists; valid frontmatter; `tools` contains `Bash` and **excludes**
  `Write`/`Edit`.
- `agents/mb-tooling-core.md` has `partial: true`; contains the fail-open sentence and all six
  routing tokens (`code_context`, `graph_neighbors`, `graph_impact`, `graph_tests`,
  `search_code`, `recall`).
- `commands/work.md` §3a prepends both partials (regex/marker assertion); review step + `verify.md`
  inline `tooling-core`.
- `mb-reviewer.md` and `plan-verifier.md` carry the tooling-core fallback note.
- `commands/mb.md` registers `research <query>`.

bats (under `tests/bats/`):
- Fresh install ships `agents/mb-research.md` + `agents/mb-tooling-core.md` for claude/codex/pi.
- Path localization correct under codex/pi (script paths resolve, no stray `~/.claude/...`).

Regression gate: existing suites stay green (baseline bats 744 ok / pytest 1135 passed).

## 8. Migration note

After install, the generic in-repo `mb-research` agent overlaps the user's local
FaberlicApp `~/.claude/skills/mb-research/` skill (both trigger on research questions). The
in-repo agent supersedes it — the user should delete the standalone skill to avoid a
double-trigger. The skill-form install was deliberately **not** chosen, so install will not
overwrite that directory.

## 9. Verification items — RESOLVED (grounded before planning)

1. **Agent path localization** — RESOLVED. Install ships the skill body via **symlinks**
   (`install_symlink $CANONICAL_SKILL_DIR → claude/codex/cursor/pi` aliases), not per-client
   copies. The canonical `~/.claude/skills/memory-bank/scripts/…` path is already used by
   `mb.md` and the current `mb-research` SKILL in the green product. New files follow the same
   convention — **no special localization needed**; §6's "add to localized set" branch is moot.
2. **`work.md` §3a prepend format** — RESOLVED. Implement-step composes
   `<core>\n\n---\n\n<role>\n\n<item>` via `Task(subagent_type="general-purpose")`
   (`commands/work.md` ~L154–166). New prepend inserts `tooling-core` between core and role.
3. **plan-verifier dispatch** — RESOLVED. `/mb verify` is a subcommand **inside
   `commands/mb.md`** (`### verify`, ~L342), dispatching
   `prompt="<contents of …/agents/plan-verifier.md> …"` (~L354). Inline `tooling-core` there.
   `mb-reviewer` is dispatched in `commands/work.md` §3c (review step) — inline there.
   (`commands/verify.md` does not exist; verify lives in `mb.md`.)
