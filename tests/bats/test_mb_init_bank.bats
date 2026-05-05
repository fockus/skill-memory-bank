#!/usr/bin/env bats
# Tests for scripts/mb-init-bank.sh — deterministic locale-aware bank scaffolder.
#
# Contract:
#   Usage: mb-init-bank.sh [--lang=XX] [--mb-root=PATH]
#
#   Effect:
#     - Creates PROJECT/.memory-bank/{plans,plans/done,notes,reports,experiments,codebase}/
#     - Copies canonical lowercase core files from templates/locales/<lang>/.memory-bank/ (never overwrites)
#     - Writes PROJECT/.memory-bank/.mb-config with `lang=<lang>`
#
#   Resolution of <lang> (highest → lowest):
#     1. --lang=XX flag
#     2. MB_LANG env var
#     3. existing .mb-config value
#     4. default → en
#
#   Exits:
#     0 on success, 2 on invalid locale, 3 on missing template bundle.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  INIT="$REPO_ROOT/scripts/mb-init-bank.sh"

  TMPROOT="$(mktemp -d)"
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

@test "mb-init-bank: script exists and is executable" {
  [ -f "$INIT" ]
  [ -x "$INIT" ]
}

# ═══════════════════════════════════════════════════════════════
# EN (default)
# ═══════════════════════════════════════════════════════════════

@test "init: default (no flag) creates EN bank with all 7 canonical core files" {
  run bash "$INIT"
  [ "$status" -eq 0 ]

  for f in status.md roadmap.md checklist.md backlog.md research.md progress.md lessons.md; do
    [ -f "$TMPROOT/.memory-bank/$f" ] || { echo "missing: $f"; return 1; }
  done

  grep -q "^lang=en$" "$TMPROOT/.memory-bank/.mb-config"
  grep -q "^# Project — Plan" "$TMPROOT/.memory-bank/roadmap.md"
  grep -q "<!-- mb-active-plans -->" "$TMPROOT/.memory-bank/roadmap.md"
}

@test "init: creates plans/done, notes, reports, experiments, codebase dirs" {
  bash "$INIT"
  for d in plans plans/done notes reports experiments codebase; do
    [ -d "$TMPROOT/.memory-bank/$d" ] || { echo "missing dir: $d"; return 1; }
  done
}

# ═══════════════════════════════════════════════════════════════
# RU
# ═══════════════════════════════════════════════════════════════

@test "init --lang=ru: writes Russian templates + lang=ru config" {
  run bash "$INIT" --lang=ru
  [ "$status" -eq 0 ]

  [ -f "$TMPROOT/.memory-bank/roadmap.md" ]
  grep -q "^lang=ru$" "$TMPROOT/.memory-bank/.mb-config"

  # Russian bank must have cyrillic in roadmap.md (current focus heading)
  LC_ALL=C grep -q $'\xd0' "$TMPROOT/.memory-bank/roadmap.md" || {
    echo "expected cyrillic bytes in ru/roadmap.md"
    return 1
  }
}

# ═══════════════════════════════════════════════════════════════
# Scaffold locales
# ═══════════════════════════════════════════════════════════════

@test "init --lang=es: writes scaffold + preserves canonical English markers" {
  run bash "$INIT" --lang=es
  [ "$status" -eq 0 ]

  # Markers stay English (script contract)
  grep -q "<!-- mb-active-plans -->" "$TMPROOT/.memory-bank/roadmap.md"
  grep -q "^## Ideas$" "$TMPROOT/.memory-bank/backlog.md"
  grep -q "^## ADR$" "$TMPROOT/.memory-bank/backlog.md"

  # Scaffold banner is visible (reminds the user / contributor of the WIP state)
  grep -q "TODO(i18n-es)" "$TMPROOT/.memory-bank/roadmap.md" || \
    grep -q "TODO(i18n-es)" "$TMPROOT/.memory-bank/status.md"
}

@test "init --lang=zh: writes scaffold + preserves canonical English markers" {
  run bash "$INIT" --lang=zh
  [ "$status" -eq 0 ]

  grep -q "<!-- mb-active-plans -->" "$TMPROOT/.memory-bank/roadmap.md"
  grep -q "^## Ideas$" "$TMPROOT/.memory-bank/backlog.md"
  grep -q "TODO(i18n-zh)" "$TMPROOT/.memory-bank/roadmap.md" || \
    grep -q "TODO(i18n-zh)" "$TMPROOT/.memory-bank/status.md"
}

# ═══════════════════════════════════════════════════════════════
# Safety
# ═══════════════════════════════════════════════════════════════

@test "init: never overwrites existing files" {
  mkdir -p "$TMPROOT/.memory-bank"
  echo "USER CONTENT — do not clobber" > "$TMPROOT/.memory-bank/roadmap.md"

  run bash "$INIT" --lang=en
  [ "$status" -eq 0 ]

  grep -q "USER CONTENT" "$TMPROOT/.memory-bank/roadmap.md"
}

@test "init: rejects invalid locale with exit 2" {
  run bash "$INIT" --lang=fr
  [ "$status" -eq 2 ]
}

@test "init: MB_LANG env picked up when --lang absent" {
  MB_LANG=ru run bash "$INIT"
  [ "$status" -eq 0 ]
  grep -q "^lang=ru$" "$TMPROOT/.memory-bank/.mb-config"
}
