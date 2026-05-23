# Code Review Report
Date: 2026-05-21 07:20
Files reviewed: 24
Lines changed: +2831 / -17

## Remediation status

2026-05-21 follow-up: all Critical and Serious findings listed below were remediated in code/tests except the process note that `/mb verify` still needs to be run as the final Memory Bank closeout step. Verification after remediation: full pytest `707 passed`, bats `70 ok`, ruff clean, shellcheck clean, Pi extension smoke-load exit `0`.

## Critical

1. `scripts/mb-graph-query.py:99` — `edge_is_incoming()` classifies outgoing file edges as incoming because `src_file in target_files` is included in the incoming predicate. Repro: querying `neighbors --file src/a.py` for `src/a.py:a -> b` returns the same edge in both `incoming` and `outgoing`. This corrupts `neighbors`, `impact`, and `code_context` evidence for file-level questions.
   - Recommendation: remove `or src_file in target_files` from `edge_is_incoming()` and add an exact regression test asserting file outgoing edges do not appear in incoming.

2. `scripts/mb-rules-check.sh:77` — the required `mb-rules-enforcer` deterministic step cannot run on this macOS environment because the script uses Bash 4 nameref syntax (`local -n`) while `/usr/bin/env bash` resolves to Bash 3.2. The review command exits with `local: -n: invalid option`, so `/mb verify` / plan closeout is blocked.
   - Recommendation: either make `split_csv()` Bash 3.2-compatible, or explicitly require/provision Bash 4+ in installer/deps and tests. Until fixed, do not claim `/mb verify` can pass on default macOS.

## Serious

1. `adapters/pi.sh:136` / `adapters/pi.sh:189` — generated Pi graph tools call `execFileAsync()` and parse stdout only on exit 0. `mb-graph-query.py` intentionally returns non-zero for `no_match` and `missing_graph` with a JSON payload, but the wrapper will throw before returning that payload. This violates the documented fail-open behavior.
   - Recommendation: catch `ExecFileException`, parse `stdout` when present, and return a structured warning/error payload instead of surfacing a tool failure.

2. `adapters/pi.sh:168` / `scripts/mb-code-context.py:55` — Pi `code_context` wrapper never calls the installed semantic search bridge and the orchestrator only accepts semantic candidates from a JSON file. The implemented Pi native path is therefore graph/text-only by default, while the plan promises semantic + graph orchestration for Pi.
   - Recommendation: either integrate Pi `search_code`/claude-context candidates into `code_context`, or downgrade the plan/docs to state that semantic candidates are currently caller-supplied only.

3. `rules/RULES.md:46` — docs advertise `code_context --semantic-only`, but `scripts/mb-code-context.py:262` only supports `--mode auto|graph|semantic`; there is no `--semantic-only` flag. This is a copy-paste command contract bug.
   - Recommendation: add `--semantic-only` as an alias or change the docs to the real CLI syntax (`--mode semantic`) and define whether semantic mode should bypass graph/text.

4. `scripts/mb-code-context.py:17` / `scripts/mb-code-context.py:35` — protected file filtering excludes only the exact basename `.env`. Files such as `.env.local`, `.env.production`, `.envrc`, or `secrets.env` can still be returned as recommended reads if they match query tokens. The current tests cover only `.env`.
   - Recommendation: use a protected pattern set (`.env`, `.env.*`, `*.env`, `.envrc`, common credential names) and add regression tests proving protected files never appear in candidates or recommendations.

5. `.memory-bank/checklist.md:13`, `.memory-bank/checklist.md:114`, `.memory-bank/status.md:5` — Memory Bank state is internally inconsistent: Sprint 4 is still listed as a pending next-planned item / queued in status, while its stages are marked complete and the plan is `implemented_pending_verify`.
   - Recommendation: sync roadmap/status/checklist to one state, e.g. “implemented, pending verify”, and avoid leaving the top-level Sprint 4 checkbox as `⬜` once all stage items are `✅`.

## Notes

- `tests/bats/test_graph_rag_adapters.bats` checks generated Pi extension contents by `grep`, but does not execute wrapper error paths. Add a smoke test that invokes the generated tool helper or an extracted wrapper function against a missing graph and a no-match graph.
- KISS/YAGNI: no major over-abstraction found. The portable-script-first approach is appropriate, but the generated Pi heredoc is now substantial; keep future logic in scripts and wrappers thin.
- Existing `commands/mb.md` contains historical `TODO` / `...` examples; they appear pre-existing/documentation examples, not new production placeholders.

## Tests

- Unit / contract: ✅ `50 passed, 14 skipped` via focused/broad pytest selection.
- Integration: ✅ `37 ok` adapter bats.
- E2E: ⚠️ limited — Pi extension load smoke exited 0, but native wrapper tool behavior was not exercised.
- Rules enforcer: ❌ blocked — `scripts/mb-rules-check.sh` fails on Bash 3.2 (`local -n`).
- Uncovered modules / paths: Pi wrapper non-zero handling, `.env.*` protected file variants, exact incoming/outgoing file-edge semantics.

## Plan alignment

- Implemented: GraphRAG-lite Stage 1 guidance, Stage 2 graph query CLI, Stage 3 `code_context` evidence pack, Stage 4 Pi wrapper + OpenCode/Codex/AGENTS.md fallback guidance.
- Not implemented / incomplete: Pi semantic retrieval integration; OpenCode native wrappers are documented as fallback rather than implemented; `/mb verify` is not yet runnable because the rules enforcer fails in this environment.
- Outside the plan / sequencing risk: Sprint 4 was implemented while roadmap/checklist still place it after Sprint 1–3 and its plan declares `depends_on: 2026-05-21_feature_global-storage-agent-support.md`.

## Summary

The core GraphRAG-lite direction is sound and well covered by contract tests, but there are merge-blocking correctness and verification issues: graph incoming/outgoing semantics are wrong, and the required rules-enforcer step fails on default macOS Bash. Revise before merge; after fixes, add runtime tests for Pi wrapper fail-open behavior and protected-file variants.
