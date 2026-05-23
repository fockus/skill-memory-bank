---
type: architecture
topic: graph-rag-lite-code-context
status: done
parallel_safe: false
depends_on:
  - 2026-05-21_feature_global-storage-agent-support.md
linked_specs: []
sprint: Sprint 4
phase_of: context-intelligence
---

# Plan: architecture — graph-rag-lite-code-context

**Baseline commit:** f16e5715854828431fe5820c10d0ad062e4f9892

## Context

**Problem:** Memory Bank already has `.memory-bank/codebase/graph.json` for deterministic structural questions, while Pi now has local `claude-context` semantic search through Ollama + Milvus. Today these are separate mechanisms: agents must manually decide whether to use semantic search, graph `jq`, `rg`, or direct file reads. This does not scale across Pi, Claude Code, Codex, OpenCode, Cursor, Windsurf, Cline, and Kilo because not every agent supports the same extension/plugin/tool API.

**Expected result:** Memory Bank ships an agent-agnostic GraphRAG-lite layer where the canonical capability is a portable CLI/script contract, and richer agents get native wrappers. The system answers code-context questions by combining semantic retrieval, graph expansion, exact reads, and test/impact hints. Pi receives direct extension tools; OpenCode receives plugin wrappers; Claude Code receives slash-command/subagent guidance; Codex and other agents receive `AGENTS.md` instructions plus CLI commands. Core Memory Bank remains usable without `claude-context`: semantic retrieval is optional, graph and `rg` fallback are first-class.

**Core principle:** `code_context` is the default orchestration entry point for ambiguous code-understanding questions. Direct graph tools are used for exact structural questions. Direct `search_code` is used only when the user asks for semantic search or when no structural expansion is needed.

## Requirements by example

| Scenario | User / agent intent | Expected behavior |
|----------|---------------------|-------------------|
| Find unknown implementation | "where is global Pi AGENTS block injection implemented?" | Agent uses `code_context`: semantic search finds candidates, graph expands neighbors/tests, response includes files and verification commands. |
| Exact caller query | "who calls `mb_resolve_path`?" | Agent uses graph query directly, not semantic search, because the target symbol is exact and structural. |
| Impact analysis | "what breaks if we change `mb-codegraph.py` output schema?" | Agent uses graph impact + codebase summaries + tests map; semantic search is optional for docs and similar code. |
| No graph exists | `.memory-bank/codebase/graph.json` missing | Tool fails open with clear suggestion: run `/mb graph --apply`; falls back to `rg/read` when possible. |
| No claude-context available | Pi extension absent, Milvus down, or unsupported agent | `code_context` uses graph + `rg/read` fallback and reports semantic retrieval as unavailable, without blocking normal work. |
| Cross-agent install | User installs Memory Bank for Pi, OpenCode, Codex, Claude Code | Each agent receives the same decision rules and at least CLI access; Pi/OpenCode additionally get native tool/plugin wrappers. |

## Decision matrix: when agents should use what

| Question shape | Preferred entry point | Fallback | Reason |
|---|---|---|---|
| "where is the logic for X?", "find similar implementation", natural-language code search | `code_context` | `search_code` → `rg/read` | Need semantic retrieval first, then structural validation. |
| "who calls/imports/defines X?", "reverse deps", "impact of changing symbol/file" | `graph_neighbors` / `graph_impact` | `rg/read` | Exact structural relationship; vector search adds noise. |
| "what tests cover this file/symbol?" | `graph_tests` | `rg 'file|symbol' tests/` | Test relation should be deterministic and explainable. |
| "summarize architecture/module" | `code_context` with `--include-summaries` | `.memory-bank/codebase/*.md` read | Needs graph + markdown codebase maps. |
| User explicitly says "semantic search" | `search_code` | `code_context --semantic-only` | Respect explicit tool intent. |
| User explicitly says "graph" or "call graph" | graph tool | `jq` documented query | Respect exact structural intent. |

## Architecture decision

1. **Portable core first:** implement graph/context orchestration as scripts under `scripts/` with JSON output. Native agent integrations wrap these scripts instead of duplicating logic.
2. **Optional semantic provider:** Memory Bank does not depend on `claude-context` at install time. It detects available semantic search through environment/config and degrades to graph + text search.
3. **Stable graph contract:** introduce a versioned graph schema adapter and summary generator without breaking existing JSONL consumers.
4. **Agent-specific wrappers:** Pi/OpenCode can expose native tools; Claude Code/OpenCode slash commands can call scripts; Codex/Cursor/Windsurf/Cline/Kilo get prompt rules and project/global adapter files that explain the decision matrix.
5. **Evidence before answer:** every `code_context` response must include which retrieval channels were used, which files/symbols were selected, and which tests/verification commands are relevant.

## Related files

- `scripts/mb-codegraph.py` — current graph builder and JSONL producer.
- `commands/graph.md`, `commands/map.md`, `commands/context.md`, `commands/start.md` — Memory Bank command surface and context guidance.
- `agents/mb-codebase-mapper.md`, `agents/plan-verifier.md` — existing codebase map and verification consumers.
- `adapters/pi.sh`, `adapters/opencode.sh`, `adapters/codex.sh`, `adapters/cursor.sh`, `adapters/windsurf.sh`, `adapters/cline.sh`, `adapters/kilo.sh` — cross-agent install surfaces.
- `rules/RULES.md`, `rules/CLAUDE-GLOBAL.md`, `SKILL.md` — global decision rules that agents actually read.
- `tests/pytest/test_codegraph.py`, `tests/pytest/test_codegraph_ts.py`, `tests/bats/` — existing graph and adapter test patterns.

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: Retrieval decision contract and agent guidance

**What to do:**
- Define the canonical decision matrix for `graph` vs `search_code` vs `code_context` in `rules/RULES.md`, `SKILL.md`, and relevant command docs.
- Add examples for Pi, Claude Code, Codex, OpenCode, and generic AGENTS.md-based agents.
- Specify fail-open behavior when graph or semantic search is unavailable.

**Testing (TDD — tests BEFORE implementation):**
- Add pytest contract tests that parse `rules/RULES.md`, `SKILL.md`, and adapter-generated instruction snippets and assert the decision matrix exists.
- Add tests that fail if docs tell agents to use `search_code` for exact caller/import questions.
- Red command: `pytest -q tests/pytest/test_graph_rag_guidance.py` fails before doc updates.

**DoD (SMART):**
- [ ] By the end of Stage 1, at least 5 concrete examples cover Pi, Claude Code, Codex, OpenCode, and generic agents.
- [ ] Tests assert exact structural questions route to graph tools, ambiguous semantic questions route to `code_context`, and explicit semantic requests route to `search_code`.
- [ ] Guidance explicitly states that `code_context` is the default for ambiguous code-understanding tasks.
- [ ] Failure modes are documented: missing graph, stale graph, missing semantic provider, unavailable native extension.
- [ ] Verification completes in under 30 seconds with the focused pytest file.

**Edge cases:** ambiguous symbol names like `Run`/`Error`, user explicitly asks for `rg`, graph stale after refactor, project without Memory Bank active.

---

<!-- mb-stage:2 -->
### Stage 2: Stable graph query CLI and summary artifacts

**What to do:**
- Add a portable graph query script, for example `scripts/mb-graph-query.py`, with subcommands: `neighbors`, `impact`, `tests`, `explain`, and `summary`.
- Emit machine-readable JSON and concise markdown modes.
- Generate semantic-friendly summaries under `.memory-bank/codebase/` such as `GRAPH_SUMMARY.md`, `IMPACT_MAP.md`, and `TEST_LINKS.md` without requiring `claude-context`.
- Keep compatibility with existing `graph.json` JSONL schema while preparing a schema-version field for future graph v2 records.

**Testing (TDD — tests BEFORE implementation):**
- Add fixture-driven pytest tests for graph JSONL input and expected query JSON output.
- Add edge-case tests for duplicate function names, file paths with spaces, missing graph file, corrupt JSONL line, and generic symbols.
- Add integration smoke test that runs summary generation on a tiny fixture project.

**DoD (SMART):**
- [ ] CLI supports all five subcommands with `--json` output and stable exit codes: `0` success, `1` no match, `2` invalid input, `3` missing graph.
- [ ] `summary` produces markdown with symbol/file relationships suitable for indexing by semantic tools.
- [ ] Existing `/mb graph --apply` output remains backward-compatible.
- [ ] Tests cover at least 12 graph-query scenarios and run without network or Docker.
- [ ] `ruff check` passes for new Python files; no new dependency is added.

**Edge cases:** graph absent, graph generated without tree-sitter, stale nodes for moved files, cyclic imports, tests outside `tests/` directory.

---

<!-- mb-stage:3 -->
### Stage 3: `code_context` orchestration contract

**What to do:**
- Add a portable `scripts/mb-code-context.py` orchestrator that combines semantic candidates, graph expansion, exact file reads, codebase summaries, and test hints.
- Define provider interface for semantic retrieval so Pi can call existing `claude-context` tools while other agents can supply no-op, CLI, or future provider implementations.
- Output an evidence pack with: retrieval channels used, candidate files, symbols, graph neighbors, tests, confidence notes, and recommended next reads.
- Ensure the orchestrator never requires Milvus/Ollama to answer with graph-only context.

**Testing (TDD — tests BEFORE implementation):**
- Contract tests for provider interface: fake semantic provider, unavailable provider, and graph-only fallback.
- Integration tests using fixture graph + fixture source files to prove `code_context` expands semantic hits to callers/imports/tests.
- Tests assert no secrets or `.env` contents are included in returned evidence.

**DoD (SMART):**
- [ ] `mb-code-context.py --query <text> --project-root <path> --json` returns a deterministic evidence pack schema.
- [ ] Semantic provider failure is visible in `warnings[]` and does not fail the whole command when graph/text fallback is possible.
- [ ] Evidence pack includes at most 10 primary files and at most 20 graph facts by default to control prompt size.
- [ ] Exact structural queries can bypass semantic retrieval when `--mode graph` is selected.
- [ ] Focused pytest + static checks complete locally in under 60 seconds.

**Edge cases:** huge repositories, no tests found, binary/generated files, protected `.env`, multiple matching symbols, stale semantic index.

---

<!-- mb-stage:4 -->
### Stage 4: Cross-agent native wrappers and verification matrix

**What to do:**
- Add Pi extension generation/install support for native tools: `graph_neighbors`, `graph_impact`, `graph_tests`, and `code_context`, each delegating to portable scripts.
- Add OpenCode plugin wrappers with the same tool names where supported.
- Update Claude Code, Codex, Cursor, Windsurf, Cline, and Kilo adapter instructions so agents know the decision matrix and can call portable CLI commands even without native tools.
- Add docs for indexing `.memory-bank/codebase/*.md` with semantic tools when available, while keeping raw `graph.json` queried structurally.

**Testing (TDD — tests BEFORE implementation):**
- Adapter contract tests assert generated Pi/OpenCode/Codex/AGENTS.md surfaces contain the same tool names and decision rules.
- Smoke tests for Pi/OpenCode wrapper scripts run against fixture graph without requiring a live LLM.
- Existing adapter install/uninstall tests remain green and manifest ownership stays idempotent.

**DoD (SMART):**
- [ ] Pi native wrapper tools are installed under `~/.pi/agent/extensions/` or project `.pi/extensions/` through managed Memory Bank adapter flow.
- [ ] OpenCode plugin exposes equivalent wrapper behavior or documented CLI fallback if native API limits apply.
- [ ] Codex and generic AGENTS.md users receive copy-paste-ready commands for `mb-graph-query.py` and `mb-code-context.py`.
- [ ] Cross-agent docs clearly separate universal CLI contract from optional native integrations.
- [ ] Verification matrix includes focused pytest, bats adapter tests, shellcheck, and at least one end-to-end fixture workflow.

**Edge cases:** agent plugin API missing, native wrapper disabled, multiple agents sharing AGENTS.md, old adapter manifests, user has no `claude-context` setup.

---

## Verification plan

Focused checks after each stage:

```bash
pytest -q tests/pytest/test_graph_rag_guidance.py
pytest -q tests/pytest/test_graph_query.py
pytest -q tests/pytest/test_code_context.py
bats tests/bats/test_graph_rag_adapters.bats
```

Broad checks before completion:

```bash
pytest -q tests/pytest/test_codegraph.py tests/pytest/test_codegraph_ts.py tests/pytest/test_runtime_contract.py
bats tests/e2e/test_install_uninstall.bats --filter 'Pi AGENTS.md|OpenCode|Codex'
shellcheck scripts/*.sh adapters/*.sh hooks/*.sh
ruff check scripts/mb-graph-query.py scripts/mb-code-context.py tests/pytest/test_graph_query.py tests/pytest/test_code_context.py
```

Completion requires `/mb verify` before `/mb done` because this plan changes cross-agent behavior and Memory Bank rules.

## Non-goals

- Do not make `claude-context`, Milvus, Ollama, Docker, or Colima mandatory for Memory Bank installation.
- Do not replace `rg` for exact text search.
- Do not claim full GraphRAG with typed semantic edges or type inference; this is GraphRAG-lite based on code graph expansion plus optional semantic retrieval.
- Do not index raw `graph.json` as the primary semantic artifact; index generated markdown summaries instead.
- Do not add a daemon, REST API, or long-running service to Memory Bank core.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Prompt/tool confusion between `search_code` and `code_context` | Contract-tested decision matrix in rules, SKILL, and adapter instructions. |
| Native wrappers diverge across agents | Portable CLI is source of truth; wrappers are thin delegators. |
| Graph false positives for generic function names | Evidence pack marks generic/low-confidence matches and caps graph expansion. |
| Semantic provider unavailable | Fail-open graph/text fallback with visible warning. |
| Checklist hard cap pressure | Keep this plan to four stages and compact checklist entries. |
