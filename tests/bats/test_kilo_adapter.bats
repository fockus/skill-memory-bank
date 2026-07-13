#!/usr/bin/env bats
# Tests for adapters/kilo.sh — Kilo Code cross-agent adapter.
#
# Contract:
#   adapters/kilo.sh install [PROJECT_ROOT]
#   adapters/kilo.sh uninstall [PROJECT_ROOT]
#
# Generates:
#   <project>/.kilocode/rules/memory-bank.md  — rules (.kilocode/rules/ is Kilo standard)
#   <project>/.git/hooks/post-commit + pre-commit — via git-hooks-fallback (native
#     hooks API not available in Kilo — FR #5827 open)
#   <project>/.kilocode/.mb-manifest.json — ownership tracking
#
# Kilo is the only target client without first-class hooks (2026-04-20 research).
# Adapter mandates git-hooks-fallback for lifecycle events.

setup() {
  # Hermetic env: the capture hooks read their mode from the ambient shell. A dev
  # with MB_AUTO_CAPTURE=off exported turns the capture assertions into false reds.
  unset MB_AUTO_CAPTURE MB_SESSION_CAPTURE MB_PATH
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  ADAPTER="$REPO_ROOT/adapters/kilo.sh"
  PROJECT="$(mktemp -d)"
  (cd "$PROJECT" && git init -q && git config user.email t@t && git config user.name t)
  mkdir -p "$PROJECT/.memory-bank"
  echo '# Progress' > "$PROJECT/.memory-bank/progress.md"
  command -v jq >/dev/null || skip "jq required"
}

teardown() {
  [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && rm -rf "$PROJECT"
}

run_adapter() {
  local raw
  raw=$(bash "$ADAPTER" "$@" 2>&1; printf '\n__EXIT__%s' "$?")
  status="${raw##*__EXIT__}"
  output="${raw%$'\n'__EXIT__*}"
}

# ═══════════════════════════════════════════════════════════════
# Install
# ═══════════════════════════════════════════════════════════════

@test "kilo: install creates .kilocode/rules/memory-bank.md" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/.kilocode/rules/memory-bank.md" ]
  grep -q "Memory Bank" "$PROJECT/.kilocode/rules/memory-bank.md"
}

@test "kilo: install installs git-hooks-fallback (post-commit + pre-commit)" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ -x "$PROJECT/.git/hooks/post-commit" ]
  [ -x "$PROJECT/.git/hooks/pre-commit" ]
  grep -q "memory-bank: managed hook" "$PROJECT/.git/hooks/post-commit"
}

@test "kilo: install writes manifest with adapter=kilo" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local m="$PROJECT/.kilocode/.mb-manifest.json"
  [ -f "$m" ]
  jq -e '.schema_version == 1' "$m" >/dev/null
  jq -e '.adapter == "kilo"' "$m" >/dev/null
  jq -e '.files | length > 0' "$m" >/dev/null
  jq -e '.git_hooks_installed == true' "$m" >/dev/null
}

@test "kilo: install fails fast if not a git repo (git-hooks mandatory)" {
  local nongit
  nongit="$(mktemp -d)"
  mkdir -p "$nongit/.memory-bank"
  run_adapter install "$nongit"
  [ "$status" -ne 0 ]
  rm -rf "$nongit"
}

@test "kilo: install is idempotent — 2x run works cleanly" {
  run_adapter install "$PROJECT"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/.kilocode/rules/memory-bank.md" ]
  [ -x "$PROJECT/.git/hooks/post-commit" ]
}

@test "kilo: post-commit fires auto-capture (end-to-end integration)" {
  run_adapter install "$PROJECT"
  (cd "$PROJECT" && echo x > a.txt && git add a.txt && git commit -q -m "first")
  grep -q "Auto-capture" "$PROJECT/.memory-bank/progress.md"
}

# ═══════════════════════════════════════════════════════════════
# Uninstall
# ═══════════════════════════════════════════════════════════════

@test "kilo: uninstall removes rules file and git hooks" {
  run_adapter install "$PROJECT"
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  [ ! -f "$PROJECT/.kilocode/rules/memory-bank.md" ]
  [ ! -f "$PROJECT/.kilocode/.mb-manifest.json" ]
  # Our git hooks gone
  if [ -f "$PROJECT/.git/hooks/post-commit" ]; then
    ! grep -q "memory-bank: managed hook" "$PROJECT/.git/hooks/post-commit"
  fi
}

@test "kilo: uninstall without prior install is no-op" {
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
}

@test "kilo: uninstall preserves user-owned .kilocode/rules/ if other files present" {
  run_adapter install "$PROJECT"
  # User adds their own rule file
  echo "custom rule" > "$PROJECT/.kilocode/rules/user-custom.md"
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/.kilocode/rules/user-custom.md" ]
  [ ! -f "$PROJECT/.kilocode/rules/memory-bank.md" ]
}

# ═══════════════════════════════════════════════════════════════
# Global storage support (Stage 3 — rules mention resolver)
# ═══════════════════════════════════════════════════════════════

@test "kilo: rules file mentions global storage or resolver for bank path" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local rules="$PROJECT/.kilocode/rules/memory-bank.md"
  [ -f "$rules" ]
  # Kilo has no native hooks (uses git-hooks-fallback); rules doc must at least
  # mention that the bank path is resolved (local OR global) so users searching
  # this file understand the full picture
  grep -qi "MB_PATH\|global storage\|resolver\|resolved\|local OR global\|local or global" "$rules"
}

@test "kilo: install bakes MB_AGENT=kilo into the closure pre-commit (registry determinism)" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  # kilo.sh must install git-hooks-fallback with MB_AGENT=kilo so the generated
  # closure hook resolves the KILO registry (not the claude-code default) for a
  # global bank. Without it, a red Kilo global flow commits freely.
  grep -q 'MB_AGENT:=kilo' "$PROJECT/.git/hooks/pre-commit"
}

# ═══════════════════════════════════════════════════════════════
# A9 (H-7): git worktree detection (.git is a file, not a dir)
# ═══════════════════════════════════════════════════════════════

@test "kilo: install detects git repo in a linked worktree (.git is a file)" {
  wt="${PROJECT}-wt"
  (cd "$PROJECT" && git commit -q -m init --allow-empty && git worktree add -q "$wt" 2>/dev/null)
  mkdir -p "$wt/.memory-bank"; echo '# Progress' > "$wt/.memory-bank/progress.md"
  [ -f "$wt/.git" ]
  run_adapter install "$wt"
  [ "$status" -eq 0 ]
  [ -f "$wt/.kilocode/rules/memory-bank.md" ]
  rm -rf "$wt"; (cd "$PROJECT" && git worktree prune 2>/dev/null || true)
}

@test "kilo: install rejects a nested non-root subdir of an enclosing repo" {
  mkdir -p "$PROJECT/packages/sub/.memory-bank"
  echo '# Progress' > "$PROJECT/packages/sub/.memory-bank/progress.md"
  run_adapter install "$PROJECT/packages/sub"
  [ "$status" -ne 0 ]
}
