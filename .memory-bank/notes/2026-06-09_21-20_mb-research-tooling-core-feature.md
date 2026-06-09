---
type: feature
tags: [agents, research, tooling-core, work-engine]
related_features: [mb-research-tooling-core]
sprint: null
importance: medium
source: manual
created: 2026-06-09
---

# mb-research-tooling-core feature
Date: 2026-06-09 21:20

## What was done
- Shipped 5-stage feature `mb-research-tooling-core` via `/mb work --auto`; every stage cleared mb-reviewer APPROVED + severity-gate PASS + plan-verifier PASS, plan-wide Gate MET.
- Added `agents/mb-tooling-core.md` — a `partial: true` shared block teaching the 6 graph-first retrieval tools (`code_context`/`graph_neighbors`/`graph_impact`/`graph_tests`/`search_code`/`recall`) with a fail-open doctrine.
- Wired tooling-core into the work engine: `commands/work.md` §3a prepend (engineering-core→tooling-core→role), §3c review dispatch, and `commands/mb.md ### verify`; added standalone fallback notes to `mb-reviewer` + `plan-verifier`.
- Ported the standalone FaberlicApp `mb-research` skill into a portable first-class agent `agents/mb-research.md` (tools Bash/Read/Grep/Glob, no Write/Edit; 0× FaberlicApp residue) and registered `/mb research <query>`.
- Guarded install/cross-agent surfaces with `tests/bats/test_install_ships_research_tooling.bats`. Final: pytest 1161/0, bats 688/0.

## New knowledge
- A new `agents/*.md` (even a non-dispatchable `partial`) MUST be added to SKILL.md `## Agents` in the SAME change — `test_doc_counts` treats roster drift as a hard failure (see lessons.md). Same for install.sh `AGENT_COUNT` (dynamic glob).
- Retrieval tools must be taught at the prompt layer, not just in the shared `AGENTS.md`: prepend a `partial` so the composed `/mb work` sub-agent prompts (implementer, reviewer, verifier) actually see the graph-first routing — otherwise they fall back to blind `grep` even when a graph/index exists.
- Always re-establish the real RED baseline before trusting a plan's inherited "N passed" figure: the true baseline here was pytest 1134/1, not the assumed 1135/0; two pre-existing defects were silently masking a red.
- Research-vs-write contract: a research agent ships with `tools: Bash, Read, Grep, Glob` and explicitly excludes `Write`/`Edit`; tests assert the absence, not just the presence.
