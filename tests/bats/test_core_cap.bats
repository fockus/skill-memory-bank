#!/usr/bin/env bats
# mb-core-cap.sh — hard line caps for the two core registries (AGR-043).
#
# Contract:
#   `check` reports status.md / checklist.md line counts against their caps
#   (env → `.mb-config` → 60 / 100) and exits 1 when either is over.
#   `fix` composes mb-status-rotate.sh --apply + mb-checklist-prune.sh --apply
#   and re-checks: 0 = now within caps, 1 = still over (needs actualize
#   --strict), 3 = the prune refused because live plans do not fit (owner
#   decision, AGR-043), 2 = internal error. Nothing is ever deleted: what
#   leaves a core file is in progress.md first.

load 'lib/assert'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-core-cap.sh"
  TMPDIR_T="$(mktemp -d)"
  BANK="$TMPDIR_T/proj/.memory-bank"
  mkdir -p "$BANK/plans"
  printf '# Progress\n' > "$BANK/progress.md"
}

teardown() { [ -n "${TMPDIR_T:-}" ] && rm -rf "$TMPDIR_T"; }

# status.md with N lines of undated content — rotation can never shrink it.
_undated_status() {
  { printf '# Status\n\n## Current phase\n'
    local i
    for i in $(seq 1 "$1"); do printf -- '- undated line %s\n' "$i"; done
  } > "$BANK/status.md"
}

# status.md with 6 dated sections of 15 lines — rotation keeps the newest 3.
_dated_status() {
  { printf '# Status\n\n## Current phase\n- phase line\n\n'
    local d i
    for d in 1 2 3 4 5 6; do
      printf '## ✅ 2026-09-0%s — dated %s\n' "$d" "$d"
      for i in $(seq 1 14); do printf -- '- section %s body %s\n' "$d" "$i"; done
      printf '\n'
    done
  } > "$BANK/status.md"
}

_small_checklist() {
  printf '# Checklist\n\n## ⏳ In flight\n- ⬜ keep this open TODO\n' > "$BANK/checklist.md"
}

# 15 live v2 plan blocks (122 lines) — over the 100 cap with nothing archivable.
_live_plans_checklist() {
  { printf '# Checklist\n\n'
    local i s
    for i in $(seq 1 15); do
      printf '<!-- mb-plan:2026-09-01_fix_p%s.md -->\n## Plan %s — 0/5\n' "$i" "$i"
      for s in 1 2 3 4 5; do printf -- '- ⬜ Stage %s — work %s\n' "$s" "$s"; done
      printf '\n'
    done
  } > "$BANK/checklist.md"
}

@test "core-cap check: under both caps → exit 0 with the count fields" {
  _undated_status 10
  _small_checklist

  run bash "$SCRIPT" check --mb "$BANK"
  [ "$status" -eq 0 ]
  assert_substring "$output" 'status_lines=13 status_cap=60'
  assert_substring "$output" 'checklist_lines=4 checklist_cap=100'
  assert_substring "$output" 'over=none'
}

@test "core-cap check: over the status cap → exit 1, over=status" {
  _undated_status 100
  _small_checklist

  run bash "$SCRIPT" check --mb "$BANK"
  [ "$status" -eq 1 ]
  assert_substring "$output" 'status_lines=103 status_cap=60'
  assert_substring "$output" 'over=status'
  refute_substring "$output" 'over=status,checklist'
}

@test "core-cap check: both over → over=status,checklist and exit 1" {
  _undated_status 100
  _live_plans_checklist

  run bash "$SCRIPT" check --mb "$BANK"
  [ "$status" -eq 1 ]
  assert_substring "$output" 'over=status,checklist'
}

@test "core-cap check: exactly at the cap is within it; one line more is over" {
  # The cap is documented as "hard cap <= N lines", so N is allowed and N+1 is
  # not. Without this case the comparator could be `>=` instead of `>` and every
  # other test would still pass — the boundary is where an off-by-one hides.
  _undated_status 7           # 3 header lines + 7 = 10 lines exactly
  printf 'x\n' > "$BANK/checklist.md"

  MB_STATUS_MAX_LINES=10 MB_CHECKLIST_MAX_LINES=1 run bash "$SCRIPT" check --mb "$BANK"
  [ "$status" -eq 0 ]
  assert_substring "$output" 'status_lines=10 status_cap=10'
  assert_substring "$output" 'over=none'

  MB_STATUS_MAX_LINES=9 MB_CHECKLIST_MAX_LINES=1 run bash "$SCRIPT" check --mb "$BANK"
  [ "$status" -eq 1 ]
  assert_substring "$output" 'over=status'
}

@test "core-cap check: env beats .mb-config beats the 60/100 default" {
  _undated_status 100     # 103 lines
  _small_checklist

  # default → over
  run bash "$SCRIPT" check --mb "$BANK"
  [ "$status" -eq 1 ]
  assert_substring "$output" 'status_cap=60'

  # .mb-config raises the cap → under
  printf 'status_max_lines=200\n' > "$BANK/.mb-config"
  run bash "$SCRIPT" check --mb "$BANK"
  [ "$status" -eq 0 ]
  assert_substring "$output" 'status_cap=200'
  assert_substring "$output" 'over=none'

  # env beats .mb-config → over again
  MB_STATUS_MAX_LINES=10 run bash "$SCRIPT" check --mb "$BANK"
  [ "$status" -eq 1 ]
  assert_substring "$output" 'status_cap=10'
  assert_substring "$output" 'over=status'
}

@test "core-cap check: --json emits the same numbers as machine-readable JSON" {
  _undated_status 100
  _small_checklist

  run bash "$SCRIPT" check --mb "$BANK" --json
  [ "$status" -eq 1 ]
  run bash -c "bash '$SCRIPT' check --mb '$BANK' --json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d[\"status_lines\"], d[\"status_cap\"], \",\".join(d[\"over\"]))'"
  [ "$output" = "103 60 status" ]
}

@test "core-cap check: a missing core file counts as 0 lines, not an error" {
  rm -f "$BANK/status.md" "$BANK/checklist.md"

  run bash "$SCRIPT" check --mb "$BANK"
  [ "$status" -eq 0 ]
  assert_substring "$output" 'status_lines=0'
  assert_substring "$output" 'checklist_lines=0'
  assert_substring "$output" 'over=none'
}

@test "core-cap fix: rotation brings status.md under the cap → exit 0, archive in progress.md" {
  _dated_status            # 99 lines, 6 dated sections
  _small_checklist
  run bash -c "wc -l < '$BANK/status.md'"
  [ "$(echo "$output" | tr -d ' ')" -gt 60 ]

  run bash "$SCRIPT" fix --mb "$BANK"
  [ "$status" -eq 0 ]
  assert_substring "$output" 'over=none'

  run bash -c "wc -l < '$BANK/status.md'"
  [ "$(echo "$output" | tr -d ' ')" -le 60 ]
  # Nothing was deleted: the archived sections are verbatim in progress.md.
  # mb-status-rotate.sh keeps the first three dated sections in FILE order.
  assert_grep -qxF -e '## [status archive] ✅ 2026-09-06 — dated 6' "$BANK/progress.md"
  assert_grep -qxF -e '- section 6 body 14' "$BANK/progress.md"
  refute_grep -qxF -e '- section 6 body 14' "$BANK/status.md"
  # The first three dated sections stayed put.
  assert_grep -qxF -e '## ✅ 2026-09-01 — dated 1' "$BANK/status.md"
  assert_grep -qxF -e '- section 1 body 14' "$BANK/status.md"
}

@test "core-cap fix: still over after rotate+prune → exit 1 and the files keep their content" {
  _undated_status 100
  _small_checklist
  snapshot "$BANK/checklist.md" "$TMPDIR_T/checklist.before"

  run bash "$SCRIPT" fix --mb "$BANK"
  [ "$status" -eq 1 ]
  assert_substring "$output" 'over=status'
  assert_substring "$output" 'actualize --strict'

  # Rotation had nothing to move (all undated) — no line was lost.
  assert_grep -qxF -e '- undated line 100' "$BANK/status.md"
  assert_unchanged "$BANK/checklist.md" "$TMPDIR_T/checklist.before"
}

@test "core-cap fix: the prune's live-plan refusal (exit 3) is passed through, not flattened" {
  _undated_status 10
  _live_plans_checklist
  snapshot "$BANK/checklist.md" "$TMPDIR_T/checklist.before"

  run bash "$SCRIPT" fix --mb "$BANK"
  [ "$status" -eq 3 ]
  assert_substring "$output" 'plans in flight'
  # Live work is never cut to fit the cap.
  assert_unchanged "$BANK/checklist.md" "$TMPDIR_T/checklist.before"
}

@test "core-cap: MB_CORE_CAP=off silences check and fix even when over" {
  _undated_status 100
  _small_checklist
  snapshot "$BANK/status.md" "$TMPDIR_T/status.before"

  MB_CORE_CAP=off run bash "$SCRIPT" check --mb "$BANK"
  [ "$status" -eq 0 ]
  MB_CORE_CAP=off run bash "$SCRIPT" fix --mb "$BANK"
  [ "$status" -eq 0 ]
  assert_unchanged "$BANK/status.md" "$TMPDIR_T/status.before"

  # `.mb-config core_cap=off` is the per-bank form of the same kill-switch.
  printf 'core_cap=off\n' > "$BANK/.mb-config"
  run bash "$SCRIPT" check --mb "$BANK"
  [ "$status" -eq 0 ]
}
