# Orchestrator console — `<bank>/orchestrator-console.md`

A short file (≤40 lines) the orchestrator keeps while it drives background agents or `/mb team` tracks. Template: `templates/orchestrator-console.md`. Sections: open questions to the user; running agents/tracks (id, what, status); awaited events and the next step; fresh user decisions not yet recorded as AGR (normally empty — each decision goes to `mb-agree.sh add` immediately).

Rules: update at every milestone (dispatch, agent return, user decision, commit). After compaction or at session start read it first, before any action. It is working state, not memory: durable facts go to `progress.md` / AGR / plans.

**After compaction or at session start, before any action:** (1) read the console; (2) the tail of `mb-agree.sh list` (last ~15) or the Active Agreements block; (3) `mb-coord.sh active --mb <bank>`; (4) `mb-team.sh status` if a team is open. The SessionStart hook already injects the console (capped by `MB_CONSOLE_MAX_BYTES`, default 4000).

Behavior: update the state file (console / AGR) first, then answer the user. At a natural boundary (wave finished, tracks committed, before a build) offer a manual `/compact` and say what to keep.

Automation: `mb-team.sh track set` writes one line per track under `## Tracks (auto: mb-team.sh track set)` (built-in `console` lock of `mb-lock.sh`); `mb-console.sh check` fails above 40 lines (`MB_CONSOLE_MAX_LINES`) and says to move history to `progress.md`; in an orchestrator session the `mb-team-guard.py` Stop hook reminds once per change when the console is older than team.json or the board.
