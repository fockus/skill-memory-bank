# Proportional effort — baseline on real tasks (Sprint 2 Stage 4)

Plan: `plans/2026-10-07_fix_proportional-effortsprint2-execution-economy.md` § Stage 4. Agreement AGR-072:
measure on real tasks, not on a synthetic benchmark. Tool: `scripts/mb-effort-report.sh`. It only reads
transcripts and runs `git diff`; nothing is sent over the network.

The "Before" rows are three recent, finished coding tasks from the owner's other projects, all run with Memory Bank
active and before the proportional-effort changes (Sprint 1 tiers, Sprint 2 targeted tests and tone) landed.
Work on this repo itself is excluded. Tier = estimate under the Sprint 1 definitions
(`plans/2026-10-07_fix_proportional-effortsprint1-routing-rules.md`).

## How to read the metrics

- **Tokens.** Sum of assistant `message.usage` over the session plus its subagent transcripts
  (`<session>/subagents/*.jsonl`). Claude Code writes one API message as several entries that repeat the same usage,
  so usage is counted once per `message.id`. Total = input + output + cache-write + cache-read. Cache-read dominates
  (≈93–97%), so output tokens are listed separately as the better proxy for work done.
- **Duration.** Wall = first→last timestamp. Active = the sum of gaps of 10 minutes or less, so idle nights in a resumed
  session do not count. Compare tasks by active time.
- **Test runs / full suite.** Bash calls with a test runner in command position (`pytest`, `bats`, `go test`,
  `mb-test-run.sh`, …). A run counts as full suite when it names no file, `::`, `-k`, `--files` or `--changed-since`.
- **Tests added / docs.** Measured from the transcript: test cases in `Write` content plus the `Edit` new−old delta,
  and distinct `*.md` paths edited or written outside `.memory-bank/`. The git columns are filled only where the
  task's repo is a local git checkout. Tasks 1–2 shipped to a non-git VCS, so their git columns are n/a.
- **Preset / cost tier.** The `/mb work` workflow and cost tier in effect (`plans/2026-10-07_feature_pipeline-presets-cost-tiers.md`).
  Before rows: the configured default then was `execution` (harness `pipelines/harness-balanced.yaml`; techflow had
  no project pipeline at `c9b36cb`, so the skill's shipped default applied), i.e. verify after every item; cost tiers did not exist (—).
  Whether a session actually invoked `/mb work` was not checked.

## Before

| # | Project · session | Task (one line) | Tier | Preset / cost tier | Tokens total (output) | Wall / active min | Turns · tool calls · subagent dispatches | Test runs (full suite) | Tests added | Docs touched | Git range: code lines · test cases · docs new/changed | Overwork judgement |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | harness · `17a987de` | Apply PR review comments to a document-generator skill (bug fixes) | small | `execution` (before presets) / — | 7.11M (81.6k) | 60 / 38 | 70 · 96 · 1 | 5 (1) | 3 | 2 | n/a (non-git VCS) | Low: fixes and targeted tests were in proportion. Most of the overhead came from a review pass the owner asked for. |
| 2 | harness · `a4670e89` | Diagnose an empty-slides bug in a deck-generator skill, then prepare a fix PR and a tracker issue | small | `execution` (before presets) / — | 38.98M (357.7k) | 125 / 100 | 262 · 352 · 4 | 0 (0) | 0 | 4 | n/a (non-git VCS) | Medium: 4 subagents and 352 tool calls for a one-file fix, spent on scenario checks and write-ups. No test was added for the regression. |
| 3 | techflow · `7a45c813` + `0540314e` (one task resumed after the context ran out) | Adapt the universal contract-check YAML workflow for one client: engine copy, prompt, eval cases, L3 run | standard (grew to large) | `execution` (before presets) / — | 273.81M (1.09M) | 11 921 / 893 | 1 086 · 1 401 · 3 | 24 (17) | 54 | 15 | `c9b36cb..5b7e4f3`: ±13 400 · +59 cases (+4 files) · 2 new / 11 changed docs (539 lines, 369 README/CHANGELOG) | High: 17 of 24 test runs were the full suite, repeated after each change, and 15 docs were touched. This is the pattern Sprint 2 targets. |

**Totals before (3 tasks):** 319.9M tokens (1.53M output), 1 031 active min, 29 test runs (18 full suite),
57 tests added, 21 docs touched.

Caveat: the ±13 400 code lines in task 3 include data/config files committed in the same range. Read that figure
as the size of the range, not as hand-written code.

## After

Fill this in after rollout, using 3 comparable real tasks (same projects; tiers small / small / standard where
possible). Quality gate from the plan DoD: no new bugs in these tasks within a week, checked against backlog/issues.

| # | Project · session | Task (one line) | Tier | Preset / cost tier | Tokens total (output) | Wall / active min | Turns · tool calls · subagent dispatches | Test runs (full suite) | Tests added | Docs touched | Git range: code lines · test cases · docs new/changed | Bugs within a week | Overwork judgement |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | | | | | | | | | | | | | |
| 2 | | | | | | | | | | | | | |
| 3 | | | | | | | | | | | | | |

## Reproduce

```bash
P=~/.claude/projects
scripts/mb-effort-report.sh "$P/-Users-anton-one-Apps-harness/17a987de-f9a1-4370-a5cf-afd05d9e21d8.jsonl"
scripts/mb-effort-report.sh "$P/-Users-anton-one-Apps-harness/a4670e89-897a-4790-9675-ca0cf6611be2.jsonl"
scripts/mb-effort-report.sh --repo ~/Apps/techflow --since c9b36cb --until 5b7e4f3 \
  "$P/-Users-anton-one-Apps-techflow/7a45c813-d5ee-4794-b774-5b1e50a12c90.jsonl" \
  "$P/-Users-anton-one-Apps-techflow/0540314e-a3a0-4710-a92d-fa04d8bdfa8b.jsonl"
# add --json for machine-readable output; "After" rows use the same command on the new sessions
```
