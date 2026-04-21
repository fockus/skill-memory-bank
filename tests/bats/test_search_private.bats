#!/usr/bin/env bats
# Tests for <private>...</private> handling in mb-search.sh — Stage 3 v2.1.
#
# Contract:
#   - default mode: <private>...</private> is replaced with [REDACTED] in output
#   - --show-private without MB_SHOW_PRIVATE=1 → exit 2, hint in stderr
#   - MB_SHOW_PRIVATE=1 + --show-private → full output
#   - --tag search: tags inside <private> are ignored → not findable through tag

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SEARCH="$REPO_ROOT/scripts/mb-search.sh"

  MB="$(mktemp -d)/.memory-bank"
  mkdir -p "$MB/notes"
  export MB_PATH="$MB"
}

teardown() {
  [ -n "${MB:-}" ] && [ -d "$(dirname "$MB")" ] && rm -rf "$(dirname "$MB")"
}

# Capture stdout+stderr + exit via __EXIT__ sentinel
run_search() {
  local raw
  raw=$(bash "$SEARCH" "$@" "$MB" 2>&1; printf '\n__EXIT__%s' "$?")
  status="${raw##*__EXIT__}"
  output="${raw%$'\n'__EXIT__*}"
}

run_search_env() {
  local env_assign="$1"; shift
  local raw
  raw=$(env $env_assign bash "$SEARCH" "$@" "$MB" 2>&1; printf '\n__EXIT__%s' "$?")
  status="${raw##*__EXIT__}"
  output="${raw%$'\n'__EXIT__*}"
}

# ═══════════════════════════════════════════════════════════════
# REDACTED replacement in default mode
# ═══════════════════════════════════════════════════════════════

@test "search private: default mode redacts inline <private> in output" {
  cat > "$MB/notes/pii.md" <<'EOF'
---
type: note
---

Client <private>SECRET-ABC-123</private> signed the agreement.
EOF

  run_search "SECRET-ABC-123"
  # exit 0 with a result (grep found a match in the raw file)
  [ "$status" -eq 0 ]
  # But the output replaces it with REDACTED
  [[ "$output" != *"SECRET-ABC-123"* ]]
  [[ "$output" == *"REDACTED"* ]]
}

@test "search private: default mode redacts multi-line <private> block" {
  cat > "$MB/notes/multi.md" <<'EOF'
---
type: note
---

Detail:
<private>
SECRET-MULTI-LINE
password=top
</private>
Public part.
EOF

  run_search "SECRET-MULTI"
  # After REDACT → SECRET-MULTI must not be in output
  [[ "$output" != *"SECRET-MULTI-LINE"* ]]
  [[ "$output" != *"password=top"* ]]
}

# ═══════════════════════════════════════════════════════════════
# --show-private double-confirmation
# ═══════════════════════════════════════════════════════════════

@test "search private: --show-private without MB_SHOW_PRIVATE=1 → exit !=0 + hint" {
  cat > "$MB/notes/pii.md" <<'EOF'
---
type: note
---
<private>SECRET-X</private>
EOF

  run_search --show-private "SECRET-X"
  [ "$status" -ne 0 ]
  [[ "$output" == *"MB_SHOW_PRIVATE"* ]]
}

@test "search private: --show-private + MB_SHOW_PRIVATE=1 → full output" {
  cat > "$MB/notes/pii.md" <<'EOF'
---
type: note
---

Full secret: <private>FULL-SECRET-Y</private>.
EOF

  run_search_env "MB_SHOW_PRIVATE=1" --show-private "FULL-SECRET"
  [ "$status" -eq 0 ]
  [[ "$output" == *"FULL-SECRET-Y"* ]]
  # REDACTED should not appear in this mode
  [[ "$output" != *"REDACTED"* ]]
}

# ═══════════════════════════════════════════════════════════════
# --tag search with private content in tags (defensive behavior)
# ═══════════════════════════════════════════════════════════════

@test "search private: --tag does not find a note when the tag is inside <private>" {
  # index.json is generated automatically; a tag inside <private> in frontmatter
  # must be filtered out by the index parser.
  cat > "$MB/notes/pii.md" <<'EOF'
---
type: note
tags: [public-tag]
---

Note with a tag inside a private block: <private>tags: [secret-tag]</private>.
EOF

  run_search --tag "secret-tag"
  # It should not find anything — the tag exists only inside <private>
  [[ "$output" == *"Nothing found"* ]]
}
