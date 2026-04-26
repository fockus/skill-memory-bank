#!/usr/bin/env bats
# Stage 6 — `mb-idea.sh` must treat the title as a literal string when checking
# for duplicates, not as a grep ERE pattern. Otherwise titles that contain
# regex metachars (`.*`, `[`, `]`, `(`, `)`, `+`, `?`, `{`, `}`, `^`, `$`, `\`)
# either give false-positive duplicate matches or break grep entirely.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  IDEA="$REPO_ROOT/scripts/mb-idea.sh"
  TMP="$(mktemp -d)"
  MB="$TMP/.memory-bank"
  mkdir -p "$MB"
  cat > "$MB/backlog.md" <<'EOF'
# Backlog

## Ideas

### I-001 — first real idea [MED, NEW, 2026-01-01]
First.

### I-002 — second real idea [MED, NEW, 2026-01-02]
Second.

## ADRs
EOF
}

teardown() {
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

@test "mb-idea: title with regex metachar (.*) is not treated as pattern" {
  run bash "$IDEA" ".* matches everything" MED "$MB"
  [ "$status" -eq 0 ]
  [[ "$output" =~ I-003 ]]

  run bash "$IDEA" ".* matches everything" MED "$MB"
  [ "$status" -eq 0 ]
  [[ "$output" =~ I-003 ]]
  [[ "$output" =~ already\ present|DUPLICATE|duplicate ]] || [[ "$(grep -c "I-003 — \.\* matches everything" "$MB/backlog.md")" = "1" ]]
}

@test "mb-idea: title with square brackets does not break grep parsing" {
  run bash "$IDEA" "[bug] login flow" MED "$MB"
  [ "$status" -eq 0 ]
  [[ "$output" =~ I-003 ]]
  ! grep -q "Invalid regular expression" <<<"$output"
  ! grep -q "bracket expression" <<<"$output"
  grep -q "I-003 — \[bug\] login flow" "$MB/backlog.md"
}

@test "mb-idea: regex-like title does not falsely match unrelated entries" {
  # Use a title that, as a regex, would match multiple I-NNN lines: ".*real.*"
  # Should be added as a NEW entry (no false dedup), not ignored.
  run bash "$IDEA" ".*real.*" MED "$MB"
  [ "$status" -eq 0 ]
  [[ "$output" =~ I-003 ]]
  grep -q '^### I-003 — \.\*real\.\* ' "$MB/backlog.md"
}
