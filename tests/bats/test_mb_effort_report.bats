#!/usr/bin/env bats
# Tests for scripts/mb-effort-report.sh — per-task effort metrics from Claude Code
# transcripts (+ subagent transcripts) and an optional git range
# (proportional-effort Sprint 2, Stage 4).
#
# Fixture transcripts (tests/bats/fixtures/effort_report):
#   s1.jsonl — msg_A split over two entries (usage repeated → counted once),
#              msg_B dispatches an Agent, msg_C runs a targeted pytest,
#              one malformed line; s1/subagents/agent-a1.jsonl runs `bats tests/bats`,
#              writes 3 test cases (Write + Edit delta) and touches one doc
#              (a `.memory-bank/` edit is not a doc).
#   s2.jsonl — two plain assistant messages 45 s apart, a third after a 2 h idle gap
#              (wall clock counts it, active time does not); its Bash calls hold one
#              full and one targeted test run plus `pgrep pytest` and a heredoc that
#              only mention a runner (not runs).

load lib/assert

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  RUN="$REPO_ROOT/scripts/mb-effort-report.sh"
  FX="$REPO_ROOT/tests/bats/fixtures/effort_report"
  command -v jq >/dev/null || skip "jq required"
}

teardown() {
  if [ -n "${GIT_REPO:-}" ]; then rm -rf "$GIT_REPO"; fi
}

summary_of() {
  printf '%s\n' "$1" | jq -r "$2"' | "in=\(.input_tokens) out=\(.output_tokens) cw=\(.cache_creation_tokens) cr=\(.cache_read_tokens) total=\(.total_tokens) dur=\(.duration_min) active=\(.active_min) turns=\(.turns) tools=\(.tool_calls) disp=\(.dispatches) subs=\(.subagents) tests=\(.test_runs) full=\(.full_suite_runs) tcases=\(.test_cases_written) docs=\(.docs_touched)|"'
}

@test "effort-report: session sums dedupe split messages and include subagent transcripts" {
  run "$RUN" --json "$FX/s1.jsonl"
  [ "$status" -eq 0 ]
  assert_substring "$(summary_of "$output" '.sessions[0]')" \
    "in=16 out=62 cw=160 cr=300 total=538 dur=4.5 active=4.5 turns=4 tools=9 disp=1 subs=1 tests=3 full=2 tcases=3 docs=1|"
}

@test "effort-report: total sums every session" {
  run "$RUN" --json "$FX/s1.jsonl" "$FX/s2.jsonl"
  [ "$status" -eq 0 ]
  assert_substring "$(summary_of "$output" '.sessions[1]')" \
    "in=100 out=75 cw=0 cr=0 total=175 dur=120.75 active=0.75 turns=3 tools=4 disp=0 subs=0 tests=2 full=1 tcases=0 docs=0|"
  assert_substring "$(summary_of "$output" '.total')" \
    "in=116 out=137 cw=160 cr=300 total=713 dur=125.25 active=5.25 turns=7 tools=13 disp=1 subs=1 tests=5 full=3 tcases=3 docs=1|"
  assert_substring "$output" '"git": null'
}

@test "effort-report: human table has a row per session and a TOTAL row" {
  run "$RUN" "$FX/s1.jsonl" "$FX/s2.jsonl"
  [ "$status" -eq 0 ]
  assert_substring "$output" "s1"
  assert_substring "$output" "s2"
  assert_substring "$output" "TOTAL"
  assert_substring "$output" "713"
  refute_substring "$output" "Traceback"
}

@test "effort-report: missing transcript is a usage error" {
  run "$RUN" "$FX/nope.jsonl"
  [ "$status" -eq 2 ]
  assert_substring "$output" "nope.jsonl"
}

@test "effort-report: git range counts tests, docs and code lines" {
  command -v git >/dev/null || skip "git required"
  GIT_REPO="$(mktemp -d)"
  git -C "$GIT_REPO" init -q
  git -C "$GIT_REPO" config user.email t@t.t
  git -C "$GIT_REPO" config user.name t
  mkdir -p "$GIT_REPO/src" "$GIT_REPO/tests/bats"
  printf 'x = 1\n' >"$GIT_REPO/src/old.py"
  printf '# Proj\n' >"$GIT_REPO/README.md"
  printf '@test "old" {\n  true\n}\n' >"$GIT_REPO/tests/bats/x.bats"
  git -C "$GIT_REPO" add -A
  git -C "$GIT_REPO" commit -qm base
  git -C "$GIT_REPO" tag base

  mkdir -p "$GIT_REPO/docs" "$GIT_REPO/.memory-bank/notes"
  printf 'def test_a():\n    assert 1\ndef test_b():\n    assert 1\n' >"$GIT_REPO/tests/test_new.py"
  printf '@test "new" {\n  true\n}\n' >>"$GIT_REPO/tests/bats/x.bats"
  printf 'a = 1\nb = 2\nc = 3\nd = 4\n' >"$GIT_REPO/src/app.py"
  printf 'x = 2\n' >"$GIT_REPO/src/old.py"
  printf '# Guide\n\ntext\n' >"$GIT_REPO/docs/guide.md"
  printf '# Project\n' >"$GIT_REPO/README.md"
  printf '# note\ndef test_ignored():\n' >"$GIT_REPO/.memory-bank/notes/n.md"
  git -C "$GIT_REPO" add -A
  git -C "$GIT_REPO" commit -qm work

  run "$RUN" --json --repo "$GIT_REPO" --since base --until HEAD "$FX/s2.jsonl"
  [ "$status" -eq 0 ]
  assert_substring "$(printf '%s\n' "$output" | jq -r '.git | "code=\(.code_lines_changed) tfiles=\(.test_files_added) tcases=\(.test_cases_added) dnew=\(.docs_added) dchg=\(.docs_changed) dlines=\(.docs_lines_changed) rc=\(.readme_changelog_lines)|"')" \
    "code=13 tfiles=1 tcases=3 dnew=1 dchg=1 dlines=5 rc=2|"

  run "$RUN" --repo "$GIT_REPO" --since base "$FX/s2.jsonl"
  [ "$status" -eq 0 ]
  assert_substring "$output" "base..HEAD"
  assert_substring "$output" "tests +1 files / +3 cases"
}

@test "effort-report: --until without --since is a usage error" {
  run "$RUN" --until HEAD "$FX/s2.jsonl"
  [ "$status" -eq 2 ]
  assert_substring "$output" "--since"
}
