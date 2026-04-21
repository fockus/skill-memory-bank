#!/usr/bin/env bats
# Tests for RESEARCH.md ↔ experiments/ drift check in scripts/mb-drift.sh.
#
# Stage 5 of plans/2026-04-21_refactor_agents-quality.md adds a new checker
# `check_research_experiments`:
#   For every H-NNN in RESEARCH.md whose status is ✅ Confirmed or ❌ Refuted,
#   there must be a matching file at experiments/EXP-NNN.md. Gaps = drift.
#
# Contract:
#   - Status value in the 3rd column of the hypothesis row: "✅ Confirmed"
#     or "❌ Refuted" → requires experiments/EXP-<NNN>.md (3-digit, padded).
#   - "⬜ Not tested" / "🔬 Running" / "—" → NO requirement (ok).
#   - Missing EXP file → drift_check_research_experiments=warn + per-H stderr
#     line naming the missing file.
#   - No RESEARCH.md → drift_check_research_experiments=skip.
#   - No experiments/ dir but Confirmed hypotheses exist → same as missing
#     EXP files (warn).

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  DRIFT="$REPO_ROOT/scripts/mb-drift.sh"

  TMPROOT="$(mktemp -d)"
  MB="$TMPROOT/.memory-bank"
  mkdir -p "$MB/experiments" "$MB/plans/done" "$MB/notes"

  # Minimal files so the other checkers do not short-circuit.
  : > "$MB/STATUS.md"
  : > "$MB/plan.md"
  : > "$MB/checklist.md"
  : > "$MB/BACKLOG.md"
  : > "$MB/progress.md"
}

teardown() {
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

@test "research: H-001 Confirmed + missing EXP-001 → warn" {
  cat > "$MB/RESEARCH.md" <<'EOF'
# Hypotheses

| ID    | Hypothesis      | Status       | Experiment | Result | Conclusion |
| ----- | --------------- | ------------ | ---------- | ------ | ---------- |
| H-001 | Cache is faster | ✅ Confirmed | —          | —      | —          |
EOF
  run bash "$DRIFT" "$TMPROOT"
  # Look for the new key in stdout.
  [[ "$output" == *"drift_check_research_experiments=warn"* ]]
}

@test "research: H-001 Refuted + missing EXP-001 → warn" {
  cat > "$MB/RESEARCH.md" <<'EOF'
# Hypotheses

| ID    | Hypothesis      | Status     | Experiment | Result | Conclusion |
| ----- | --------------- | ---------- | ---------- | ------ | ---------- |
| H-001 | Cache is faster | ❌ Refuted | —          | —      | —          |
EOF
  run bash "$DRIFT" "$TMPROOT"
  [[ "$output" == *"drift_check_research_experiments=warn"* ]]
}

@test "research: H-001 Confirmed + existing EXP-001.md → ok" {
  cat > "$MB/RESEARCH.md" <<'EOF'
| ID    | Hypothesis      | Status       | Experiment | Result | Conclusion |
| ----- | --------------- | ------------ | ---------- | ------ | ---------- |
| H-001 | Cache is faster | ✅ Confirmed | EXP-001    | +15%   | ship       |
EOF
  cat > "$MB/experiments/EXP-001.md" <<'EOF'
# EXP-001: Cache speedup
## Hypothesis
H-001.
## Conclusions
- Confirmed.
EOF
  run bash "$DRIFT" "$TMPROOT"
  [[ "$output" == *"drift_check_research_experiments=ok"* ]]
}

@test "research: all hypotheses Not tested → ok (no requirement)" {
  cat > "$MB/RESEARCH.md" <<'EOF'
| ID    | Hypothesis | Status         | Experiment | Result | Conclusion |
| ----- | ---------- | -------------- | ---------- | ------ | ---------- |
| H-001 | Foo        | ⬜ Not tested   | —          | —      | —          |
| H-002 | Bar        | 🔬 Running     | —          | —      | —          |
EOF
  run bash "$DRIFT" "$TMPROOT"
  [[ "$output" == *"drift_check_research_experiments=ok"* ]]
}

@test "research: mixed — one Confirmed missing EXP, one Confirmed with EXP → warn" {
  cat > "$MB/RESEARCH.md" <<'EOF'
| ID    | Hypothesis | Status       | Experiment | Result | Conclusion |
| ----- | ---------- | ------------ | ---------- | ------ | ---------- |
| H-001 | Foo        | ✅ Confirmed | EXP-001    | —      | —          |
| H-002 | Bar        | ✅ Confirmed | —          | —      | —          |
EOF
  cat > "$MB/experiments/EXP-001.md" <<'EOF'
# EXP-001
EOF
  run bash "$DRIFT" "$TMPROOT"
  [[ "$output" == *"drift_check_research_experiments=warn"* ]]
}

@test "research: no RESEARCH.md at all → skip (not warn)" {
  # Remove the research file (setup doesn't create it by default).
  run bash "$DRIFT" "$TMPROOT"
  [[ "$output" == *"drift_check_research_experiments=skip"* ]] \
    || [[ "$output" == *"drift_check_research_experiments=ok"* ]]
}

@test "research: drift_warnings counter incremented on gap" {
  cat > "$MB/RESEARCH.md" <<'EOF'
| ID    | Hypothesis | Status       | Experiment | Result | Conclusion |
| ----- | ---------- | ------------ | ---------- | ------ | ---------- |
| H-042 | Foo        | ✅ Confirmed | —          | —      | —          |
EOF
  run bash "$DRIFT" "$TMPROOT"
  # Total drift_warnings line should be > 0 when research gap exists.
  local warnings
  warnings="$(echo "$output" | awk -F= '$1=="drift_warnings"{print $2; exit}')"
  [ -n "$warnings" ]
  [ "$warnings" -gt 0 ]
}
