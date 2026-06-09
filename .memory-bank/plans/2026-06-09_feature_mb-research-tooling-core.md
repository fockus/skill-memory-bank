---
type: feature
topic: mb-research-tooling-core
status: planned
depends_on: []
parallel_safe: false
linked_specs: [specs/mb-research-tooling-core]
---

# Plan: feature — mb-research-tooling-core

**Baseline commit:** 3bafe7bba59d4feac1b00499ea245cb1aed73b8b

## Context

**Problem:** `mb-research` lives outside the skill as a standalone, FaberlicApp-tuned skill
(`~/.claude/skills/mb-research/SKILL.md`); it is not part of the agent roster and not shipped by
`install.sh`. Separately, the optional graph/recall/semantic retrieval tools are only advertised in
the shared-format `AGENTS.md` (`_lib_agents_md.sh` → `## GraphRAG-lite routing`) — they never reach
the Claude sub-agent prompts composed by `/mb work` (engineering-core + role delta). So MB
implementers, the reviewer, and the plan-verifier fall back to blind `grep` even when a graph or
semantic index exists.

**Expected result:**
1. `agents/mb-research.md` — a first-class, portable MB research agent (no Write/Edit) + `/mb research <query>` entrypoint.
2. `agents/mb-tooling-core.md` — a shared `partial: true` block teaching the six retrieval tools (`code_context`, `graph_neighbors`, `graph_impact`, `graph_tests`, `search_code`, `recall`), prepended alongside engineering-core; reviewer + plan-verifier reference it.
3. Fail-open throughout: no agent gains a hard dependency on the graph or the vector index.

**Related files:**
- Design spec: [specs/mb-research-tooling-core/design.md](../specs/mb-research-tooling-core/design.md)
- Source to port: `~/.claude/skills/mb-research/SKILL.md` (de-FaberlicApp before landing)
- `agents/mb-engineering-core.md` (prepend pattern to mirror) · `agents/mb-reviewer.md` · `agents/plan-verifier.md`
- `commands/work.md` (§3a implement prepend ~L154-166, §3c review dispatch) · `commands/mb.md` (`### verify` ~L342-354, command table)
- `adapters/_lib_agents_md.sh` (`## GraphRAG-lite routing` — vocabulary SSoT) · `install.sh` (symlink install, `AGENT_COUNT` ~L254-259) · `SKILL.md` (agent roster)
- Lessons applied: **L40** orphan-agents on port (verify `name:`/paths/no residue) · **L18** tests assert real strings, not "should" · **L64** install-test `$HOME` isolation + `_protect_repo_install_manifest` autouse fixture

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: `mb-tooling-core` shared partial (single injection point)

**What to do:**
- Create `agents/mb-tooling-core.md` with `partial: true` frontmatter (`name: mb-tooling-core`, description marking it as a prepended partial — "Do not dispatch directly", mirroring engineering-core's header style).
- Body = one section **"Code-understanding tools (graph-first, fail-open)"**: a 6-row table mapping intent → token → canonical command:
  - `code_context` → `scripts/mb-code-context.py` (fuzzy "where is the logic for X")
  - `graph_neighbors` → `scripts/mb-graph-query.py neighbors` (who calls / imports / defines)
  - `graph_impact` → `scripts/mb-graph-query.py impact` (reverse-deps / blast-radius)
  - `graph_tests` → `scripts/mb-graph-query.py tests` (which tests cover X)
  - `search_code` → `scripts/mb-semantic-search.py` (concept; BM25 default, `--backend embeddings` opt-in)
  - `recall` → `/mb recall <query>` (decisions / "why")
- Close with the verbatim fail-open sentence + "these indexes are optional; if absent or stale, fall back to `Grep`/`Glob`/`Read` — never block."

**Testing (TDD — tests BEFORE implementation):**
- New `tests/pytest/test_tooling_core.py` (RED before GREEN; assert literal strings per L18):
  - file exists at `agents/mb-tooling-core.md`; frontmatter parses; `partial: true` present.
  - all 6 routing tokens present as exact substrings.
  - all 4 canonical script paths present (`mb-code-context.py`, `mb-graph-query.py`, `mb-semantic-search.py`, `/mb recall`).
  - fail-open sentence present (substring `must not block work`).
  - "Do not dispatch directly" marker present (not a standalone agent).

**DoD (SMART):**
- [x] `agents/mb-tooling-core.md` exists, `partial: true`, ≤ 80 lines (KISS — one section only). *(27 lines)*
- [x] ≥ 6 pytest cases in `test_tooling_core.py` assert tokens + paths + fail-open; all green (`pytest tests/pytest/test_tooling_core.py -q` → 7 passed).
- [x] RED→GREEN shown: 7 failed (file absent) → 7 passed after creating the partial.
- [x] markdown/lint clean; doc-only (only the new partial + new test touched). Reviewer APPROVED (minor×1, non-blocking), severity-gate PASS, plan-verifier PASS.

**Code rules:** KISS (single section), DRY (one SSoT for tool vocabulary, reused from `_lib_agents_md.sh`), no placeholders.

---

<!-- mb-stage:2 -->
### Stage 2: Wire `tooling-core` into dispatch points + specialist fallback notes

**What to do:**
- `commands/work.md` §3a: prepend composition becomes `engineering-core` → `---` → `tooling-core` → `---` → role delta → item body (engineering-core stays FIRST so "stricter wins" primacy is preserved).
- `commands/work.md` §3c (review step): inline `tooling-core` into the `mb-reviewer` dispatch prompt.
- `commands/mb.md` `### verify`: inline `tooling-core` into the `plan-verifier` dispatch prompt.
- `agents/mb-reviewer.md` + `agents/plan-verifier.md`: add standalone fallback note — "If no tooling-core block is present above, read `agents/mb-tooling-core.md` first." (mirror the engineering-core note already in role files).

**Testing (TDD — tests BEFORE implementation):**
- New `tests/pytest/test_tooling_core_wiring.py` (assert literal references per L18):
  - `commands/work.md` §3a template references BOTH `mb-engineering-core.md` AND `mb-tooling-core.md`, with engineering-core appearing first.
  - `commands/work.md` review step references `mb-tooling-core.md`.
  - `commands/mb.md` verify section references `mb-tooling-core.md`.
  - `agents/mb-reviewer.md` AND `agents/plan-verifier.md` each contain the `mb-tooling-core.md` fallback note.

**DoD (SMART):**
- [x] 4 surfaces updated (work.md §3a + §3c, mb.md ### verify, reviewer + verifier fallback notes); each asserted by a passing grep-based pytest.
- [x] prepend order verified core → tooling-core → role (test asserts index ordering; empirically eng-core@8125 < tooling-core@8315).
- [x] `pytest tests/pytest/test_tooling_core_wiring.py -q` → 6 passed (RED 0/6 → GREEN 6/6).
- [x] existing work.md/mb.md guards still pass (doc_counts + mb_work_agents + phase3_sprint2 = 58 passed). Reviewer APPROVED (0/0/0), gate PASS, plan-verifier PASS.

**Code rules:** DRY (reference the one partial; never duplicate the tool text into each file), KISS.

---

<!-- mb-stage:3 -->
### Stage 3: `mb-research` agent — generalized, de-FaberlicApp'd port

**What to do:**
- Create `agents/mb-research.md` from the standalone SKILL, generalized: frontmatter `name: mb-research`, `tools: Bash, Read, Grep, Glob` (NO `Write`/`Edit`), `model: sonnet`, `color`.
- Strip every "FaberlicApp" reference and project-specific example (L40); keep portable: routing table (graph-first → source), "When NOT to use", "Optional-source availability" (graceful degradation per source — context7/`gh`/graph/index all optional), execution patterns (narrow → single; broad → fan-out parallel subagents), anti-hallucination output discipline (`file:line` citations).
- Use the shared tool vocabulary + canonical script paths (consistency with Stage 1 partial).

**Testing (TDD — tests BEFORE implementation):**
- New `tests/pytest/test_mb_research_agent.py` (RED first):
  - file exists; YAML frontmatter parses; `name: mb-research`.
  - `tools` includes `Bash`, `Read`, `Grep`, `Glob`; **excludes** `Write` and `Edit` (assert absence — research-not-write contract).
  - body contains routing tokens / script paths (`graph_impact`, `search_code`, `recall`, `mb-graph-query.py`).
  - **zero** occurrences of `FaberlicApp` (L40 orphan-agent guard); no non-portable hardcoded project path.
  - portability clause present ("must still work in a repo with no Memory Bank" / fail-open).
  - anti-hallucination discipline present (`file:line`).

**DoD (SMART):**
- [x] `agents/mb-research.md` present, valid frontmatter, `name: mb-research`, `tools` excludes Write/Edit (89 lines).
- [x] `grep -ci faberlic agents/mb-research.md` == 0; no hardcoded non-portable path (asserted).
- [x] 8 pytest cases in `test_mb_research_agent.py` (RED 0/8 → GREEN 8/8); listed in SKILL.md ## Agents (doc-counts green).
- [x] file ≤ ~120 lines (89). Reviewer APPROVED (0/0/0), gate PASS, plan-verifier PASS (full suite 1156 passed).

**Code rules:** L40 (verify name/paths/integration on port), KISS, portability, no placeholders.

---

<!-- mb-stage:4 -->
### Stage 4: `/mb research` entrypoint

**What to do:**
- `commands/mb.md`: add a `research <query>` row to the command table AND a `### research` section that dispatches the `mb-research` agent via `Task` (narrow question → single dispatch; broad/multi-area → fan-out parallel subagents), with a one-line fail-open note. Follow the existing `### <cmd>` dispatch-section pattern in `mb.md`.

**Testing (TDD — tests BEFORE implementation):**
- New `tests/pytest/test_mb_research_command.py`:
  - `commands/mb.md` command table contains a `research` row.
  - `### research` section exists and references dispatching `agents/mb-research.md` via `Task`.
  - section mentions fan-out for broad sweeps.

**DoD (SMART):**
- [x] `/mb research` registered (table row + `### research` section) — asserted by passing grep pytest (L18).
- [x] section literally references `mb-research.md` and `Task` dispatch.
- [x] `pytest tests/pytest/test_mb_research_command.py -q` → 5 passed (RED 0/5 → GREEN 5/5).
- [x] section style consistent with sibling `### verify`/`### map` sections. Reviewer APPROVED (0/0/0), gate PASS, plan-verifier PASS (full suite 1161).

**Code rules:** consistency with existing `mb.md` command sections, KISS.

---

<!-- mb-stage:5 -->
### Stage 5: Roster, install & cross-agent surfaces

**What to do:**
- `SKILL.md`: add `mb-research` to the agent roster/list; note the `mb-tooling-core` partial.
- `install.sh`: the `agents/*.md` glob ships both new files automatically — verify `AGENT_COUNT` reflects +2 and update the descriptive agent-listing message (~L259) if it enumerates agent names.
- `adapters/_lib_agents_md.sh`: if its `AGENTS.md` section enumerates agents, add `mb-research`; confirm the `GraphRAG-lite routing` vocabulary already matches the partial (it does — no behavioural change otherwise).

**Testing (TDD — tests BEFORE implementation):**
- New `tests/bats/test_install_ships_research_tooling.bats` (sandbox `$HOME` per L64):
  - fresh install places `agents/mb-research.md` + `agents/mb-tooling-core.md` under the resolved Claude skill alias; codex/pi resolve via symlink.
  - `AGENT_COUNT` / install summary reflects the new total.
- pytest (reuse `_protect_repo_install_manifest` autouse fixture, L64): `SKILL.md` roster lists `mb-research`.

**DoD (SMART):**
- [ ] install ships both new files (bats green for claude alias; codex/pi symlink-resolved).
- [ ] `SKILL.md` roster lists `mb-research` (asserted).
- [ ] no install-manifest flake — `_protect_repo_install_manifest` honored; 2× consecutive bats runs stable (L64).
- [ ] `bats tests/bats/test_install_ships_research_tooling.bats` green (output pasted).

**Code rules:** L64 (test isolation), L18 (assert real strings), KISS.

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Prepend order regresses engineering-core primacy ("stricter wins") | M | Stage 2 test asserts core appears before tooling-core; primacy note retained |
| Port leaves FaberlicApp residue / wrong `name:` (orphan-agent, L40) | M | Stage 3 test asserts 0× `FaberlicApp` + correct `name:` + portable paths |
| Symlink install → codex/pi path resolution differs | L | Follow the existing `mb.md` canonical-path convention (already green in product); Stage 5 bats covers install validity |
| install test flake from shared `.installed-manifest.json` (L64) | M | Reuse `_protect_repo_install_manifest` autouse fixture; run bats 2× for stability |
| Double-trigger with user's local FaberlicApp `mb-research` skill | L | Migration note (spec §8) — user deletes standalone skill; out-of-scope cleanup |
| `tooling-core` bloats every dev-agent prompt | L | ≤ 80 lines, single section, KISS; fail-open keeps it advisory |

## Gate (plan success criterion)

Full suite green with **no regression** from baseline (bats 744 ok / pytest 1135 passed) PLUS all
new tests, AND all of:
- `agents/mb-research.md` present — valid frontmatter, `name: mb-research`, `tools` excludes Write/Edit, 0× `FaberlicApp`.
- `agents/mb-tooling-core.md` present — `partial: true`, 6 tokens + 4 paths + fail-open sentence.
- `tooling-core` prepended in `commands/work.md` §3a (after engineering-core) and inlined for `mb-reviewer` (work.md §3c) + `plan-verifier` (mb.md `### verify`); both specialist files carry the fallback note.
- `/mb research` registered in `commands/mb.md` (table row + `### research` section dispatching the agent).
- `install.sh` ships both new files for claude/codex/pi; `SKILL.md` roster updated.
- Existing `tests/pytest/test_rules_cover_intelligence_layer.py` (and the wider guard suite) still green.
