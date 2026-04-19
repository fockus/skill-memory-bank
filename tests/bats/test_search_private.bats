#!/usr/bin/env bats
# Tests for <private>...</private> handling в mb-search.sh — Stage 3 v2.1.
#
# Контракт:
#   - default mode: <private>...</private> заменяется на [REDACTED] в output
#   - --show-private без MB_SHOW_PRIVATE=1 → exit 2, hint в stderr
#   - MB_SHOW_PRIVATE=1 + --show-private → полный output
#   - --tag поиск: теги внутри <private> игнорируются → not findable через tag

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
# REDACTED replacement в default mode
# ═══════════════════════════════════════════════════════════════

@test "search private: default mode redacts inline <private> in output" {
  cat > "$MB/notes/pii.md" <<'EOF'
---
type: note
---

Клиент <private>SECRET-ABC-123</private> подписал договор.
EOF

  run_search "SECRET-ABC-123"
  # exit 0 с результатом (grep нашёл совпадение в raw file)
  [ "$status" -eq 0 ]
  # Но в output заменено на REDACTED
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
  # После REDACT → SECRET-MULTI не должно быть в output
  [[ "$output" != *"SECRET-MULTI-LINE"* ]]
  [[ "$output" != *"password=top"* ]]
}

# ═══════════════════════════════════════════════════════════════
# --show-private double-confirmation
# ═══════════════════════════════════════════════════════════════

@test "search private: --show-private без MB_SHOW_PRIVATE=1 → exit !=0 + hint" {
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

Полный секрет: <private>FULL-SECRET-Y</private>.
EOF

  run_search_env "MB_SHOW_PRIVATE=1" --show-private "FULL-SECRET"
  [ "$status" -eq 0 ]
  [[ "$output" == *"FULL-SECRET-Y"* ]]
  # REDACTED не должно быть в этом режиме
  [[ "$output" != *"REDACTED"* ]]
}

# ═══════════════════════════════════════════════════════════════
# --tag search с private-содержимым в tags (защитная логика)
# ═══════════════════════════════════════════════════════════════

@test "search private: --tag не находит note по тегу если тег внутри <private>" {
  # index.json сгенерируется автоматически; тег внутри <private> в frontmatter
  # должен быть отфильтрован парсером index.
  cat > "$MB/notes/pii.md" <<'EOF'
---
type: note
tags: [public-tag]
---

Note с тегом в приватном блоке: <private>tags: [secret-tag]</private>.
EOF

  run_search --tag "secret-tag"
  # Не должно найти — тег только в <private>
  [[ "$output" == *"Ничего не найдено"* ]]
}
