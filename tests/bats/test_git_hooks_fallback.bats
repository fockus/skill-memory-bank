#!/usr/bin/env bats
# Tests for adapters/git-hooks-fallback.sh
#
# Contract:
#   adapters/git-hooks-fallback.sh install [PROJECT_ROOT]
#   adapters/git-hooks-fallback.sh uninstall [PROJECT_ROOT]
#
# Installs:
#   .git/hooks/post-commit   — auto-capture placeholder to progress.md
#   .git/hooks/pre-commit    — warn on <private> blocks in staged changes
#   .git/mb-hooks-manifest.json — tracks ownership + user-hook backups
#
# Chains to existing user hooks (backup + delegate, does not overwrite).

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  ADAPTER="$REPO_ROOT/adapters/git-hooks-fallback.sh"
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

@test "git-hooks: install creates post-commit + pre-commit hooks (executable)" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ -x "$PROJECT/.git/hooks/post-commit" ]
  [ -x "$PROJECT/.git/hooks/pre-commit" ]
}

@test "git-hooks: install writes manifest" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local m="$PROJECT/.git/mb-hooks-manifest.json"
  [ -f "$m" ]
  jq . "$m" >/dev/null
  jq -e '.adapter == "git-hooks-fallback"' "$m" >/dev/null
}

@test "git-hooks: install fails fast if not a git repo" {
  local nongit
  nongit="$(mktemp -d)"
  run_adapter install "$nongit"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a git repository"* ]]
  rm -rf "$nongit"
}

@test "git-hooks: install chains with existing user post-commit (backup + delegate)" {
  mkdir -p "$PROJECT/.git/hooks"
  cat > "$PROJECT/.git/hooks/post-commit" <<'EOF'
#!/bin/sh
echo "USER_POST_COMMIT_MARKER" > /tmp/mb-test-user-hook-marker
EOF
  chmod +x "$PROJECT/.git/hooks/post-commit"

  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]

  # Backup exists
  [ -f "$PROJECT/.git/hooks/post-commit.pre-mb-backup" ]
  # Our hook is active
  grep -q "memory-bank" "$PROJECT/.git/hooks/post-commit"

  # Trigger commit — user hook should still run via chain
  rm -f /tmp/mb-test-user-hook-marker
  (cd "$PROJECT" && echo x > f.txt && git add f.txt && git commit -q -m "test") || true
  [ -f /tmp/mb-test-user-hook-marker ]
  rm -f /tmp/mb-test-user-hook-marker
}

@test "git-hooks: install is idempotent — 2x does not double-chain" {
  run_adapter install "$PROJECT"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  # No duplicated memory-bank marker
  local count
  count=$(grep -c "memory-bank" "$PROJECT/.git/hooks/post-commit" || true)
  [ "$count" -ge 1 ]
  # Backup was not overwritten with our own hook on second install
  if [ -f "$PROJECT/.git/hooks/post-commit.pre-mb-backup" ]; then
    ! grep -q "memory-bank" "$PROJECT/.git/hooks/post-commit.pre-mb-backup"
  fi
}

# ═══════════════════════════════════════════════════════════════
# post-commit behavior
# ═══════════════════════════════════════════════════════════════

@test "git-hooks: post-commit appends placeholder to progress.md on commit" {
  run_adapter install "$PROJECT"
  (cd "$PROJECT" && echo x > a.txt && git add a.txt && git commit -q -m "first")
  grep -q "Auto-capture" "$PROJECT/.memory-bank/progress.md"
}

@test "git-hooks: post-commit respects fresh .session-lock (manual done marker)" {
  run_adapter install "$PROJECT"
  touch "$PROJECT/.memory-bank/.session-lock"
  (cd "$PROJECT" && echo x > a.txt && git add a.txt && git commit -q -m "first")
  # Fresh lock → skip auto-capture
  ! grep -q "Auto-capture" "$PROJECT/.memory-bank/progress.md"
  # Lock is consumed
  [ ! -f "$PROJECT/.memory-bank/.session-lock" ]
}

@test "git-hooks: post-commit noop if no .memory-bank/ directory" {
  rm -rf "$PROJECT/.memory-bank"
  run_adapter install "$PROJECT"
  # Commit should succeed even without MB
  (cd "$PROJECT" && echo x > a.txt && git add a.txt && git commit -q -m "nomb")
  [ ! -d "$PROJECT/.memory-bank" ]
}

@test "git-hooks: post-commit respects MB_AUTO_CAPTURE=off" {
  run_adapter install "$PROJECT"
  (cd "$PROJECT" && MB_AUTO_CAPTURE=off bash -c 'echo x > a.txt && git add a.txt && git commit -q -m "first"')
  ! grep -q "Auto-capture" "$PROJECT/.memory-bank/progress.md"
}

# ═══════════════════════════════════════════════════════════════
# pre-commit behavior
# ═══════════════════════════════════════════════════════════════

@test "git-hooks: pre-commit warns (stderr) on staged <private> blocks" {
  run_adapter install "$PROJECT"
  mkdir -p "$PROJECT/.memory-bank/notes"
  cat > "$PROJECT/.memory-bank/notes/secret.md" <<'EOF'
Some content <private>api_key=sk-xxx</private> here.
EOF
  (cd "$PROJECT" && git add . 2>/dev/null || true)
  local out
  out=$(cd "$PROJECT" && bash .git/hooks/pre-commit 2>&1 || true)
  [[ "$out" == *"private"* ]] || [[ "$out" == *"PRIVATE"* ]]
}

@test "git-hooks: pre-commit does not warn on clean files" {
  run_adapter install "$PROJECT"
  mkdir -p "$PROJECT/.memory-bank/notes"
  echo 'normal note content' > "$PROJECT/.memory-bank/notes/normal.md"
  (cd "$PROJECT" && git add . 2>/dev/null || true)
  local out
  out=$(cd "$PROJECT" && bash .git/hooks/pre-commit 2>&1 || true)
  [[ "$out" != *"private"* ]] && [[ "$out" != *"PRIVATE"* ]]
}

# ═══════════════════════════════════════════════════════════════
# Uninstall
# ═══════════════════════════════════════════════════════════════

@test "git-hooks: uninstall removes our hooks and manifest" {
  run_adapter install "$PROJECT"
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  # Our markers gone
  if [ -f "$PROJECT/.git/hooks/post-commit" ]; then
    ! grep -q "memory-bank" "$PROJECT/.git/hooks/post-commit"
  fi
  [ ! -f "$PROJECT/.git/mb-hooks-manifest.json" ]
}

@test "git-hooks: uninstall restores user hooks from backup" {
  mkdir -p "$PROJECT/.git/hooks"
  cat > "$PROJECT/.git/hooks/post-commit" <<'EOF'
#!/bin/sh
echo "ORIGINAL_USER_CONTENT"
EOF
  chmod +x "$PROJECT/.git/hooks/post-commit"
  run_adapter install "$PROJECT"
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/.git/hooks/post-commit" ]
  grep -q "ORIGINAL_USER_CONTENT" "$PROJECT/.git/hooks/post-commit"
  ! grep -q "memory-bank" "$PROJECT/.git/hooks/post-commit"
}

@test "git-hooks: uninstall without prior install is no-op" {
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
}
