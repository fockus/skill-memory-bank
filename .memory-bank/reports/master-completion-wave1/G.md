# Track G — Stage 20 Pi settle-resume gate: DONE_WITH_CONCERNS

Files: adapters/pi_native_settle.mjs (new), adapters/pi_graph_rag_extension.ts (registers it),
adapters/_lib_pi_global.sh (persistence paragraph in the Pi AGENTS.md block; adapters/pi.sh untouched),
adapters/pi_subagent_extension.ts (retry once if transient, then report and stop),
tests/pytest/test_pi_native_settle.py (new, 11 tests), docs/cross-agent-setup.md (gate + retry settings).

Behaviour: agent_before_settle runs hooks/mb-drive-resume-gate.sh as a subprocess (drive decision not
re-implemented); else the newest /mb work run in <bank>/.work-state with phase != done and updated < 6h ago.
Returns hidden custom_message + continue:true. Cap 3 per cycle (reset on agent_settled). outcome != completed,
any exception, corrupt files -> no continue.

TDD: with the module absent: `11 failed`; with it: `11 passed in 15.16s`.
Existing pi_native tests: with PATH set to the nvm node (npm root -g then resolves Pi) and PI_PACKAGE_ROOT:
install/lifecycle/ordinary/session/work/hooks/graph/backends/commands/embeddings/host all pass
(first run under another node, v22.22.3, failed 14 tests in host/lifecycle/ordinary: those fixtures resolve Pi via `npm root -g`; with nvm node on PATH they pass).

Concerns: (Low) event.outcome value set not verified beyond the docs example ("completed"); handler resumes only when outcome is absent or "completed".
(Low) /mb work runs have no session id, so any fresh in-progress run in the bank qualifies (6h freshness bound).
Live check (owner): in a project with an active bank, start Pi with the extension installed, run /mb work <plan> --range N on a 3-step item, or set up a drive run in phase execution with an unmet goal; confirm no "продолжи" is needed and ≤3 hidden resumes (custom_message type mb-settle-resume) appear in the session log. Recommended retry settings are documented only; ~/.pi untouched.

## Fix after orchestrator review (work-run ownership)
The /mb work branch now counts only runs created after this session started: a `session_start` handler snapshots
<bank>/.work-state/*.json per bank; at settle, snapshotted files are ignored (no snapshot -> no work resume, fail open).
Drive branch unchanged. Tests: `test_preexisting_foreign_work_run_does_not_resume` (pre-existing fresh run -> no continue),
`test_work_run_created_during_session_resumes` (file written by a delayed child after session_start -> continue),
finished-run test reworked the same way. Result: `12 passed in 14.42s`.
Caveat: I wrote the tests together with the fix and did not run them red first; the foreign-run test would fail on the previous
logic by construction (it resumed on any fresh run).
