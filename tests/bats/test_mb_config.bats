#!/usr/bin/env bats
# Tests for scripts/mb-config.sh — locale resolver + auto-detect + writeback.
#
# Contract:
#   Usage:
#     mb-config get <key>              — print resolved value to stdout
#     mb-config set <key> <value>      — persist to $MB_ROOT/.memory-bank/.mb-config
#     mb-config detect-lang            — heuristic scan of existing bank (stdout: detected code)
#
#   Keys:
#     lang  ∈ {en, ru, es, zh}
#
#   Resolution order (highest → lowest):
#     1. MB_LANG  env var        (session override)
#     2. $MB_ROOT/.memory-bank/.mb-config  (`lang=XX`)
#     3. auto-detect from existing bank content
#     4. default → `en`
#
#   `get lang` with only #3 hitting must WRITE BACK the detected locale to
#   .mb-config so the next run is deterministic (no re-scan).
#
#   Rejection:
#     - unknown key → exit 2
#     - invalid locale code → exit 2

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  CFG="$REPO_ROOT/scripts/mb-config.sh"

  TMPROOT="$(mktemp -d)"
  TMPBANK="$TMPROOT/.memory-bank"
  mkdir -p "$TMPBANK"

  export MB_ROOT="$TMPROOT"
  unset MB_LANG
}

teardown() {
  unset MB_LANG MB_ROOT
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

# ═══════════════════════════════════════════════════════════════
# Smoke
# ═══════════════════════════════════════════════════════════════

@test "mb-config: script exists and is executable" {
  [ -f "$CFG" ]
  [ -x "$CFG" ]
}

@test "mb-config: --help prints usage" {
  run bash "$CFG" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"mb-config"* ]]
}

# ═══════════════════════════════════════════════════════════════
# Resolution order
# ═══════════════════════════════════════════════════════════════

@test "get lang: default is 'en' when no config, no env, no bank content" {
  run bash "$CFG" get lang
  [ "$status" -eq 0 ]
  [ "$output" = "en" ]
}

@test "get lang: MB_LANG env overrides config file" {
  echo "lang=ru" > "$TMPBANK/.mb-config"
  MB_LANG=es run bash "$CFG" get lang
  [ "$status" -eq 0 ]
  [ "$output" = "es" ]
}

@test "get lang: config file beats auto-detect and default" {
  echo "lang=zh" > "$TMPBANK/.mb-config"
  run bash "$CFG" get lang
  [ "$status" -eq 0 ]
  [ "$output" = "zh" ]
}

# ═══════════════════════════════════════════════════════════════
# Auto-detect + writeback
# ═══════════════════════════════════════════════════════════════

@test "get lang: auto-detects ru from cyrillic roadmap.md section" {
  cat > "$TMPBANK/roadmap.md" <<'EOF'
# Проект — План

## Текущий фокус

Инициализация проекта.

## Активные планы

<!-- mb-active-plans -->
<!-- /mb-active-plans -->
EOF

  run bash "$CFG" get lang
  [ "$status" -eq 0 ]
  [ "$output" = "ru" ]
}

@test "get lang: writes back detected locale so next run is deterministic" {
  cat > "$TMPBANK/status.md" <<'EOF'
# Проект — Статус

**Текущая фаза:** —
EOF
  [ ! -f "$TMPBANK/.mb-config" ]

  run bash "$CFG" get lang
  [ "$status" -eq 0 ]
  [ "$output" = "ru" ]
  [ -f "$TMPBANK/.mb-config" ]
  grep -q "lang=ru" "$TMPBANK/.mb-config"
}

@test "get lang: returns 'en' for bank with only ASCII markers" {
  cat > "$TMPBANK/roadmap.md" <<'EOF'
# Project — Plan

## Current focus

Initial setup.

## Active plans

<!-- mb-active-plans -->
<!-- /mb-active-plans -->
EOF

  run bash "$CFG" get lang
  [ "$status" -eq 0 ]
  [ "$output" = "en" ]
}

# ═══════════════════════════════════════════════════════════════
# set
# ═══════════════════════════════════════════════════════════════

@test "set lang: writes .mb-config and round-trips via get" {
  run bash "$CFG" set lang ru
  [ "$status" -eq 0 ]
  [ -f "$TMPBANK/.mb-config" ]
  grep -q "lang=ru" "$TMPBANK/.mb-config"

  run bash "$CFG" get lang
  [ "$status" -eq 0 ]
  [ "$output" = "ru" ]
}

@test "set lang: idempotent — second identical set is no-op" {
  bash "$CFG" set lang ru
  local first
  first="$(cat "$TMPBANK/.mb-config")"
  run bash "$CFG" set lang ru
  [ "$status" -eq 0 ]
  [ "$(cat "$TMPBANK/.mb-config")" = "$first" ]
}

@test "set lang: overwrites previous value (ru → zh)" {
  echo "lang=ru" > "$TMPBANK/.mb-config"
  run bash "$CFG" set lang zh
  [ "$status" -eq 0 ]
  grep -q "lang=zh" "$TMPBANK/.mb-config"
  ! grep -q "lang=ru" "$TMPBANK/.mb-config"
}

# ═══════════════════════════════════════════════════════════════
# Validation
# ═══════════════════════════════════════════════════════════════

@test "set lang: rejects unknown locale with exit 2" {
  run bash "$CFG" set lang fr
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid"* ]] || [[ "$output" == *"unknown"* ]]
  [ ! -f "$TMPBANK/.mb-config" ]
}

@test "get: rejects unknown key with exit 2" {
  run bash "$CFG" get bogus
  [ "$status" -eq 2 ]
}

@test "get lang: MB_LANG with invalid code still exits 2 (explicit opt-in must be correct)" {
  MB_LANG=fr run bash "$CFG" get lang
  [ "$status" -eq 2 ]
}
