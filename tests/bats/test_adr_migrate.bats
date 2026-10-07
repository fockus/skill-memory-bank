#!/usr/bin/env bats
# Tests for scripts/mb-adr-migrate.sh — move ADRs from backlog.md into adr.md (AGR-062).
#
# Contract:
#   Usage: mb-adr-migrate.sh [--dry-run|--apply] [mb_path]   (default --dry-run)
#   - Every `### ADR-NNN …` block (until the next `### ADR-`, `### `/`## ` heading
#     or EOF) and every `- ADR-NNN: …` line leaves backlog.md and lands in adr.md
#     verbatim, sorted by ID.
#   - A `## ADR` / `## Architectural decisions` section left empty is dropped.
#   - --apply keeps backlog.md.bak; re-running is a no-op; --dry-run writes nothing.

load lib/assert

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  MIG="$REPO_ROOT/scripts/mb-adr-migrate.sh"
  TMPROOT="$(mktemp -d)"
  BANK="$TMPROOT/.memory-bank"
  mkdir -p "$BANK"

  cat > "$BANK/backlog.md" <<'MD'
# Backlog

## Ideas

### I-001 — first idea [HIGH, NEW, 2026-01-01]

**Problem:** see решение ADR-002.

### ADR-002 — middle decision [2026-01-02]

**Context:** c2.
**Options:**
- A: x

### I-002 — second idea [LOW, NEW, 2026-01-03]

**Problem:** p2.

## ADR

- ADR-003: one-line decision — context [2026-01-04]

### ADR-001 — end decision [2026-01-01]

**Context:** c1.

**Consequences:** q1.
MD

  # Exact adr.md: header, then each record verbatim (trailing blank lines
  # trimmed), one blank line between records, sorted by ID.
  cat > "$TMPROOT/expected_adr" <<'MD'
# Architecture Decision Records

### ADR-001 — end decision [2026-01-01]

**Context:** c1.

**Consequences:** q1.

### ADR-002 — middle decision [2026-01-02]

**Context:** c2.
**Options:**
- A: x

- ADR-003: one-line decision — context [2026-01-04]
MD
}

teardown() {
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

@test "adr-migrate: --apply moves every ADR out of backlog.md" {
  run bash "$MIG" --apply "$BANK"
  [ "$status" -eq 0 ]

  [ "$(grep -c '^### ADR-' "$BANK/backlog.md")" -eq 0 ]
  run grep -c '^- ADR-' "$BANK/backlog.md"
  [ "$output" = "0" ]
  run grep -qE '^## ADR' "$BANK/backlog.md"
  [ "$status" -eq 1 ]
  # Ideas and in-prose references stay.
  grep -q '^### I-001 — first idea' "$BANK/backlog.md"
  grep -q '^### I-002 — second idea' "$BANK/backlog.md"
  grep -q 'решение ADR-002' "$BANK/backlog.md"
  [ -f "$BANK/backlog.md.bak" ]
}

@test "adr-migrate: adr.md holds the blocks verbatim, sorted by ID" {
  bash "$MIG" --apply "$BANK"

  [ "$(head -1 "$BANK/adr.md")" = "# Architecture Decision Records" ]
  diff "$TMPROOT/expected_adr" "$BANK/adr.md"
}

@test "adr-migrate: no byte of the backlog is lost" {
  before=$(wc -c < "$BANK/backlog.md")
  bash "$MIG" --apply "$BANK"
  # Every non-blank backlog line is now in exactly one of the two files
  # (only the emptied `## ADR` heading is dropped).
  diff <(grep -v '^$' "$BANK/backlog.md.bak" | grep -vxF '## ADR' | sort) \
       <(cat "$BANK/backlog.md" "$BANK/adr.md" | grep -v '^$' | grep -vxF '# Architecture Decision Records' | sort)
  [ "$before" -eq "$(wc -c < "$BANK/backlog.md.bak")" ]
}

@test "adr-migrate: second --apply is a no-op" {
  bash "$MIG" --apply "$BANK"
  a1=$(cksum < "$BANK/adr.md"); b1=$(cksum < "$BANK/backlog.md")
  run bash "$MIG" --apply "$BANK"
  [ "$status" -eq 0 ]
  assert_substring "$output" "nothing to migrate"
  [ "$(cksum < "$BANK/adr.md")" = "$a1" ]
  [ "$(cksum < "$BANK/backlog.md")" = "$b1" ]
}

@test "adr-migrate: default --dry-run writes nothing and lists the ADRs" {
  b1=$(cksum < "$BANK/backlog.md")
  run bash "$MIG" "$BANK"
  [ "$status" -eq 0 ]
  assert_substring "$output" "ADR-001"
  assert_substring "$output" "ADR-003"
  [ ! -e "$BANK/adr.md" ]
  [ ! -e "$BANK/backlog.md.bak" ]
  [ "$(cksum < "$BANK/backlog.md")" = "$b1" ]
}

@test "adr-migrate: existing adr.md records are kept and merged by ID" {
  printf '# Architecture Decision Records\n\n### ADR-004 — newer [2026-02-01] · status: accepted\n\n**Context:** n.\n' > "$BANK/adr.md"
  bash "$MIG" --apply "$BANK"
  run grep -oE '^(### |- )ADR-[0-9]+' "$BANK/adr.md"
  [ "$output" = "$(printf '### ADR-001\n### ADR-002\n- ADR-003\n### ADR-004')" ]
  grep -q '^\*\*Context:\*\* n\.$' "$BANK/adr.md"
}

@test "adr-migrate: ID present in both files → refuses, writes nothing" {
  printf '# Architecture Decision Records\n\n### ADR-002 — clash [2026-02-01] · status: accepted\n' > "$BANK/adr.md"
  b1=$(cksum < "$BANK/backlog.md")
  run bash "$MIG" --apply "$BANK"
  [ "$status" -ne 0 ]
  assert_substring "$output" "ADR-002"
  [ "$(cksum < "$BANK/backlog.md")" = "$b1" ]
}

@test "adr-migrate: emptied '## Architectural decisions (ADR)' under a --- divider is dropped" {
  printf '# Backlog\n\n## Ideas\n\n### I-001 — idea [LOW, NEW, 2026-01-01]\n\n---\n\n## Architectural decisions (ADR)\n\n- ADR-001: d — c [2026-01-01]\n' > "$BANK/backlog.md"
  bash "$MIG" --apply "$BANK"
  [ "$(cat "$BANK/backlog.md")" = "$(printf '# Backlog\n\n## Ideas\n\n### I-001 — idea [LOW, NEW, 2026-01-01]')" ]
  [ "$(tail -c 1 "$BANK/backlog.md" | od -An -c | tr -d ' ')" = '\n' ]
}
