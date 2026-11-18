# Track E - dynamic-flow T13 (Pi/OpenCode sub-invoke)
STATUS: DONE_WITH_CONCERNS

Red (before): bats tests/bats/test_subinvoke_pi_opencode.bats -> tests 1,2,3,6 not ok (no `subinvoke` verb; unresolvable agent died exit 2).
Green (after): bats of test_subinvoke_pi_opencode + test_mb_fanout + test_mb_subinvoke_resolve + test_subinvoke_resolve -> 91 ok, 0 not ok.

Changes: adapters/pi.sh (pi_subinvoke_cmd + `subinvoke` verb), adapters/opencode.sh (opencode_subinvoke_cmd + verb), both delegating to mb-subinvoke-resolve.sh with MB_SUBINVOKE_CMD env-u'd (codex pattern). scripts/mb-fanout.sh: unresolvable -> stderr WARN, claude-code template, branches run one at a time (SEQUENTIAL). test_mb_fanout.bats: old exit-2 test updated to the new contract. New tests/bats/test_subinvoke_pi_opencode.bats (6 tests, stub pi/opencode/claude). tasks.md T13 DoD ticked. mb-subinvoke-resolve.sh unchanged (already had pi/opencode).

Concerns (Low): shellcheck on mb-fanout.sh clean; pi.sh/opencode.sh show only pre-existing SC2034/SC2016 findings on lines not touched. Native preference (REQ-DF-083) is realised as: resolver emits the native headless CLI (`pi -p`, `opencode run`); a host wanting a native parallel feature sets MB_SUBINVOKE_CMD; no new dispatcher. Sequential fallback uses the claude-code template (portable default); if claude is absent branches fail -> exit 2 as before.
