# Graph adoption — master-completion Stage 7 (2026-11-19)

Baseline (2026-11-18, before Stages 2-6): `graph_share` 0.0259 (graph 7 / grep 263) over this machine's transcripts.

After Stages 2-6 (nudge fix, graph_share metric, `## Graph` push into /mb work prompts, tooling block for
judge and reviewer lead/logic, Codex SubagentStart graph line) and Stage 22 (tests through shell entry points):

- `mb-cost-report.py --since 1`: overall `graph_share` 0.0435 (34 graph calls); reviewer 0.0556, research 0.1053,
  judge 0.0 (its runs predate the push block), other 0.0471.
- Demo runs (Stage 13 H1/H2, implementer + reviewer, real items): implementers 5 and 3 graph queries vs 1 grep
  each; reviewers 4 and 3 graph queries.
- The demo found two graph gaps (tests reached through `.sh` entry points; argparse `cmd_*` dispatch without
  incoming edges) — fixed in Stage 22 (0139fcb): `tests scripts/mb_bank_lint_backlog.py` now lists
  test_mb_bank_lint.bats, `who-calls cmd_checkpoint` returns `main`.

Remaining gaps: `with`-statement use (e.g. `bank_lock`) has no incoming edges; Claude Code SubagentStart
graph line unconfirmed (I-293).

7-day window: re-read `python3 scripts/mb-cost-report.py --since 7 --json` on 2026-11-26 and append the
per-role `graph_share` here (target: judge > 0, implementer/reviewer above the 2026-11-19 values).
