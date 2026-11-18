# /mb research — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `research <query>` — Graph-first multi-source research — codebase / memory / library / prior-art / web; dispatches the `mb-research` agent and returns `file:line`-grounded findings (narrow → single dispatch; broad → fan-out parallel subagents). Fail-open: graph/index optional, degrades to Grep/Read

### research <query>

Graph-first, multi-source research over **this** codebase, project memory, library docs, GitHub
prior-art, and the open web. Routes each question to the right index first (MB code graph → semantic
search → `/mb recall` → context7 → `gh` → web), then drills into source, and returns conclusions
grounded in `file:line` or a cited source — never blind grep guessing. Dispatch the `mb-research`
agent (it researches; it never writes code):

```
Agent(
  subagent_type="mb-research",
  description="mb-research: <query>",
  prompt="Question: <the remainder of $ARGUMENTS after `research`>

Context: <current work / what is already known>"
)
```

**Execution model:**

- **Narrow question** (one symbol / concept / library) → a **single dispatch** of the agent above;
  it runs the one routed command, drills into source, and reports with `file:line` / source citations.
- **Broad or multi-area sweep** → instruct the agent to **fan-out parallel subagents** (one Task per
  area), each handed its slice of the question + the routing table, then synthesize. This replaces the
  plain `general-purpose` multi-grep sweep.

**Fail-open:** the MB code graph / semantic index / context7 / `gh` are all optional — when an index
is stale or absent, `mb-research` degrades to plain `Grep` / `Glob` / `Read` (+ web) and still works
in a repo with no Memory Bank. Never block on a missing index.

Show the agent's findings (with their citations) to the user.
