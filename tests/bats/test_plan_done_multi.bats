#!/usr/bin/env bats
# Tests for v3.1 multi-active-plan support in scripts/mb-plan-done.sh.
#
# Contract (v3.1):
#   - Removes entry from <!-- mb-active-plans --> blocks in BOTH roadmap.md + status.md.
#   - Other active plans' entries remain untouched.
#   - Prepends entry to <!-- mb-recent-done --> block in status.md.
#   - Trims mb-recent-done to MB_RECENT_DONE_LIMIT (default 10).
#   - REMOVES the plan's Stage-sections from checklist.md entirely (not just tick).
#   - If the plan has a matching idea in backlog.md (via `Plan: plans/<basename>`),
#     the idea status flips `PLANNED → DONE` and gets `**Outcome:** <placeholder>`.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SYNC="$REPO_ROOT/scripts/mb-plan-sync.sh"
  DONE="$REPO_ROOT/scripts/mb-plan-done.sh"

  TMPROOT="$(mktemp -d)"
  TMPBANK="$TMPROOT/.memory-bank"
  mkdir -p "$TMPBANK/plans/done"

  PLAN_A="$TMPBANK/plans/2026-04-20_feature_a.md"
  cat > "$PLAN_A" <<'EOF'
# Plan: feature — a

## Stages

<!-- mb-stage:1 -->
### Stage 1: do-a-1

content
EOF

  PLAN_B="$TMPBANK/plans/2026-04-21_refactor_b.md"
  cat > "$PLAN_B" <<'EOF'
# Plan: refactor — b

## Stages

<!-- mb-stage:1 -->
### Stage 1: do-b-1

content
EOF

  cat > "$TMPBANK/checklist.md" <<'EOF'
# Project — Checklist
EOF

  cat > "$TMPBANK/roadmap.md" <<'EOF'
# Project — Plan

## Active plans

<!-- mb-active-plans -->
<!-- /mb-active-plans -->
EOF

  cat > "$TMPBANK/status.md" <<'EOF'
# Project — Status

## Active plans

<!-- mb-active-plans -->
<!-- /mb-active-plans -->

## Recently done (last 10)

<!-- mb-recent-done -->
<!-- /mb-recent-done -->
EOF

  cat > "$TMPBANK/backlog.md" <<'EOF'
# Backlog

## Ideas

### I-001 — idea for feature a [HIGH, PLANNED, 2026-04-20]

**Problem:** feature a

**Plan:** [plans/2026-04-20_feature_a.md](plans/2026-04-20_feature_a.md)

## ADR
EOF

  # Prep state: sync both plans
  bash "$SYNC" "$PLAN_A" "$TMPBANK" 2>/dev/null || true
  bash "$SYNC" "$PLAN_B" "$TMPBANK" 2>/dev/null || true
}

teardown() {
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

# ═══════════════════════════════════════════════════════════════
# Active-plans block manipulation
# ═══════════════════════════════════════════════════════════════

@test "done-multi: removes only closed plan entry from roadmap.md active-plans" {
  bash "$DONE" "$PLAN_A" "$TMPBANK"

  # A should be gone from roadmap.md active block, B should remain
  awk '
    /<!-- mb-active-plans -->/ { inside=1; next }
    /<!-- \/mb-active-plans -->/ { inside=0; next }
    inside { print }
  ' "$TMPBANK/roadmap.md" > /tmp/mb-after.txt

  ! grep -q "2026-04-20_feature_a.md" /tmp/mb-after.txt
  grep -q "2026-04-21_refactor_b.md" /tmp/mb-after.txt
  rm -f /tmp/mb-after.txt
}

@test "done-multi: same removal in status.md active-plans" {
  bash "$DONE" "$PLAN_A" "$TMPBANK"

  awk '
    /<!-- mb-active-plans -->/ { inside=1; next }
    /<!-- \/mb-active-plans -->/ { inside=0; next }
    inside { print }
  ' "$TMPBANK/status.md" > /tmp/mb-after.txt

  ! grep -q "2026-04-20_feature_a.md" /tmp/mb-after.txt
  grep -q "2026-04-21_refactor_b.md" /tmp/mb-after.txt
  rm -f /tmp/mb-after.txt
}

# ═══════════════════════════════════════════════════════════════
# Recently-done prepend + trim
# ═══════════════════════════════════════════════════════════════

@test "done-multi: prepends closed plan to mb-recent-done in status.md" {
  bash "$DONE" "$PLAN_A" "$TMPBANK"

  awk '
    /<!-- mb-recent-done -->/ { inside=1; next }
    /<!-- \/mb-recent-done -->/ { inside=0; next }
    inside { print }
  ' "$TMPBANK/status.md" > /tmp/mb-recent.txt

  grep -q "2026-04-20_feature_a.md" /tmp/mb-recent.txt
  grep -qE '\[(done|closed)\]|plans/done/' /tmp/mb-recent.txt || grep -q 'plans/done/2026-04-20_feature_a' /tmp/mb-recent.txt
  rm -f /tmp/mb-recent.txt
}

@test "done-multi: recent-done keeps newest-first order" {
  bash "$DONE" "$PLAN_A" "$TMPBANK"
  bash "$DONE" "$PLAN_B" "$TMPBANK"

  awk '
    /<!-- mb-recent-done -->/ { inside=1; next }
    /<!-- \/mb-recent-done -->/ { inside=0; next }
    inside && /refactor_b|feature_a/ { print }
  ' "$TMPBANK/status.md" > /tmp/mb-recent.txt

  # refactor_b closed LAST, so it must appear BEFORE feature_a
  first=$(head -1 /tmp/mb-recent.txt)
  [[ "$first" == *"refactor_b"* ]]
  rm -f /tmp/mb-recent.txt
}

@test "done-multi: recent-done trims to MB_RECENT_DONE_LIMIT (default 10)" {
  # Seed 11 pre-existing entries + close one more
  python3 - "$TMPBANK/status.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text()
seed = "\n".join(
    f"- 2026-04-{10+i:02d} — [plans/done/seed-{i}.md](plans/done/seed-{i}.md)"
    for i in range(11)
)
text = text.replace("<!-- mb-recent-done -->\n",
                    f"<!-- mb-recent-done -->\n{seed}\n")
p.write_text(text)
PY

  bash "$DONE" "$PLAN_A" "$TMPBANK"

  count=$(awk '
    /<!-- mb-recent-done -->/ { inside=1; next }
    /<!-- \/mb-recent-done -->/ { inside=0; next }
    inside && /^- / { n++ }
    END { print n+0 }
  ' "$TMPBANK/status.md")

  [ "$count" -le 10 ]
}

@test "done-multi: recent-done trims to MB_RECENT_DONE_LIMIT env override" {
  # Seed 6 entries, limit to 3, close one → expect 3
  python3 - "$TMPBANK/status.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text()
seed = "\n".join(
    f"- 2026-04-{10+i:02d} — [plans/done/seed-{i}.md](plans/done/seed-{i}.md)"
    for i in range(6)
)
text = text.replace("<!-- mb-recent-done -->\n",
                    f"<!-- mb-recent-done -->\n{seed}\n")
p.write_text(text)
PY

  MB_RECENT_DONE_LIMIT=3 bash "$DONE" "$PLAN_A" "$TMPBANK"

  count=$(awk '
    /<!-- mb-recent-done -->/ { inside=1; next }
    /<!-- \/mb-recent-done -->/ { inside=0; next }
    inside && /^- / { n++ }
    END { print n+0 }
  ' "$TMPBANK/status.md")

  [ "$count" -le 3 ]
}

# ═══════════════════════════════════════════════════════════════
# Checklist section REMOVAL (not just tick)
# ═══════════════════════════════════════════════════════════════

@test "done-multi: removes plan's Stage sections from checklist (v3.1 behavior)" {
  # Stage-1 added to checklist by sync — verify then done should REMOVE it
  grep -q "^## Stage 1:" "$TMPBANK/checklist.md" || grep -q "do-a-1" "$TMPBANK/checklist.md"

  bash "$DONE" "$PLAN_A" "$TMPBANK"

  # After done — "do-a-1" must NOT appear in checklist anymore
  ! grep -q "do-a-1" "$TMPBANK/checklist.md"
}

@test "done-multi: preserves OTHER plan's sections in checklist" {
  bash "$DONE" "$PLAN_A" "$TMPBANK"
  # B's section must remain (plan B still active)
  grep -q "do-b-1" "$TMPBANK/checklist.md"
}

# ═══════════════════════════════════════════════════════════════
# backlog.md idea auto-transition
# ═══════════════════════════════════════════════════════════════

@test "done-multi: flips idea status PLANNED → DONE in backlog.md" {
  bash "$DONE" "$PLAN_A" "$TMPBANK"

  ! grep -q 'I-001 — idea for feature a \[HIGH, PLANNED' "$TMPBANK/backlog.md"
  grep -qE 'I-001 — idea for feature a \[HIGH, DONE' "$TMPBANK/backlog.md"
}

@test "done-multi: adds Outcome placeholder for auto-closed idea" {
  bash "$DONE" "$PLAN_A" "$TMPBANK"
  grep -q '\*\*Outcome:\*\*' "$TMPBANK/backlog.md"
}

@test "done-multi: moves plan file to plans/done/ (regression)" {
  bash "$DONE" "$PLAN_A" "$TMPBANK"
  [ -f "$TMPBANK/plans/done/2026-04-20_feature_a.md" ]
  [ ! -f "$PLAN_A" ]
}
