# COORDINATION (append-only)

Shared working tree — multiple sessions. Read this before stages, commits, and shared-file edits.
Scoped `git add <paths>` only, never `git add -A`. Do not revert/commit another session's WIP.

## 2026-07-15 — adapter-parity governed execution (session 36e70e9c / Opus orchestrator)

Running `/mb work adapter-parity` (spec `specs/adapter-parity`, tasks T1–T8) with a
Sonnet-implement · Codex-review · Opus-judge pipeline. Subagents write UNCOMMITTED work
into this shared tree between dispatch and my scoped commit.

**⚠️ FREEZE REQUEST — do NOT `git rebase`, `git reset --hard`, `git checkout .`, or
whole-tree `git stash` on this working tree while adapter-parity T3–T8 are in flight.**
A rebase auto-stash at ~07:1x today silently reverted an in-flight subagent's uncommitted
work (Task 6, `adapters/codex.sh`) — it was not captured in either surviving stash and had
to be redone. Commit your own work with scoped `git add <your paths>` instead of rebasing
the shared tree.

**Hot files I am actively editing (T3–T8):**
- `install.sh` (extension-offer seam `mb_install_host_extensions`)
- `adapters/pi.sh`, `adapters/pi_session_memory_extension.ts`, `adapters/pi_graph_rag_extension.ts`
- `adapters/opencode.sh`, `adapters/codex.sh`
- `scripts/mb-session-doctor.sh`, `scripts/mb-subinvoke-resolve.sh`
- `tests/bats/test_extensions_offer.bats`, `test_codex_adapter.bats`,
  `test_cross_agent_runtime_parity.bats`, `test_pi_adapter.bats`, `test_opencode_adapter.bats`
- `.memory-bank/specs/adapter-parity/*`, `commands/mb.md`, `adapters/_lib_agents_md.sh`

Committed so far: `4aef699` `4a4131b` `941b154` (T1) `4652e91` (T2). Please build on top with
scoped commits; ping here if you need any hot file above.
