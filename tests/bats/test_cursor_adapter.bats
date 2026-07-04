#!/usr/bin/env bats
# Tests for adapters/cursor.sh — Cursor IDE cross-agent adapter.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  ADAPTER="$REPO_ROOT/adapters/cursor.sh"
  PROJECT="$(mktemp -d)"
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

@test "cursor: install creates expected directory structure" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ -d "$PROJECT/.cursor" ]
  [ -d "$PROJECT/.cursor/rules" ]
  [ ! -d "$PROJECT/.cursor/hooks" ]
}

@test "cursor: install wires hooks.json to skill bundle paths" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local hjson="$PROJECT/.cursor/hooks.json"
  grep -q 'memory-bank/hooks/session-end-autosave.sh' "$hjson"
  grep -q 'MB_AGENT=cursor' "$hjson"
  [ ! -f "$PROJECT/.cursor/hooks/session-end-autosave.sh" ]
}

@test "cursor: install removes legacy hook copies on reinstall" {
  run_adapter install "$PROJECT"
  mkdir -p "$PROJECT/.cursor/hooks"
  echo legacy > "$PROJECT/.cursor/hooks/mb-plan-sync-post-write.sh"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ ! -f "$PROJECT/.cursor/hooks/mb-plan-sync-post-write.sh" ]
}

@test "cursor: install creates valid hooks.json with CC-compat events" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local hjson="$PROJECT/.cursor/hooks.json"
  jq . "$hjson" >/dev/null
  jq -e '.hooks.sessionEnd' "$hjson" >/dev/null
  jq -e '.hooks.preCompact' "$hjson" >/dev/null
  jq -e '.hooks.beforeShellExecution' "$hjson" >/dev/null
}

@test "cursor: install references all ten hook scripts in hooks.json" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local hjson="$PROJECT/.cursor/hooks.json"
  local hooks=(session-end-autosave.sh mb-pre-compact.sh block-dangerous.sh mb-protected-paths-guard.sh mb-ears-pre-write.sh mb-context-slim-pre-agent.sh mb-sprint-context-guard.sh file-change-log.sh mb-plan-sync-post-write.sh mb-session-start-context.sh)
  local h
  for h in "${hooks[@]}"; do
    grep -q "memory-bank/hooks/$h" "$hjson"
  done
}

@test "cursor: install has exactly ten _mb_owned entries" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local count
  count=$(jq '[.hooks[][] | select(._mb_owned == true)] | length' "$PROJECT/.cursor/hooks.json")
  [ "$count" -eq 10 ]
}

@test "cursor: uninstall removes all our files" {
  run_adapter install "$PROJECT"
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  [ ! -f "$PROJECT/.cursor/rules/memory-bank.mdc" ]
  [ ! -f "$PROJECT/.cursor/.mb-manifest.json" ]
}

@test "cursor: adapter hooks.json supports global storage via MB_AGENT" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  grep -q 'MB_AGENT=cursor' "$PROJECT/.cursor/hooks.json"
  grep -q 'MB_SKILLS_ROOT=' "$PROJECT/.cursor/hooks.json"
}

# ═══════════════════════════════════════════════════════════════
# H-2: run_texttool must honor ${MB_PYTHON:-python3} (pipx isolated venv)
# ═══════════════════════════════════════════════════════════════

@test "cursor: run_texttool honors MB_PYTHON (not bare python3)" {
  command -v python3 >/dev/null || skip "python3 required"
  local home stub marker real_py
  home="$(mktemp -d)"
  stub="$(mktemp -d)"
  marker="$stub/mb_python_called"
  real_py="$(command -v python3)"
  # Recording interpreter: notes it was called, then delegates to the real python
  # (so _texttools still resolves and install-global completes).
  cat > "$stub/mb-python" <<EOF
#!/usr/bin/env bash
echo called >> "$marker"
exec "$real_py" "\$@"
EOF
  chmod +x "$stub/mb-python"
  run env HOME="$home" MB_PYTHON="$stub/mb-python" MB_LANGUAGE=en \
    bash "$ADAPTER" install-global </dev/null
  # run_texttool (via localize) must have used MB_PYTHON, not a bare python3.
  [ -f "$marker" ]
  rm -rf "$home" "$stub"
}

@test "cursor: no bare 'python3 -m memory_bank_skill' in any adapter" {
  # Grep-invariant: every python entry point must go through ${MB_PYTHON:-python3}
  # so pipx/pip isolated installs (bare system python3 can't import the package)
  # do not abort under set -euo pipefail.
  ! grep -rnE '(^|[^-])python3 -m memory_bank_skill' "$REPO_ROOT"/adapters/*.sh
}

# ═══════════════════════════════════════════════════════════════
# H-2 tail: install-global must record the locale in its manifest, so the
# install.sh idempotency guard can detect a language switch at the same skill
# version (en → ru) and re-localize instead of skipping. Without a recorded
# `lang`, the version-only guard leaves stale English rules after `--language ru`.
# ═══════════════════════════════════════════════════════════════

@test "cursor: global manifest records the install locale (for the language-aware guard)" {
  command -v jq >/dev/null || skip "jq required"
  local home
  home="$(mktemp -d)"
  run env HOME="$home" MB_LANGUAGE=ru bash "$ADAPTER" install-global </dev/null
  [ "$status" -eq 0 ]
  jq -e '.lang == "ru"' "$home/.cursor/.mb-manifest.json" >/dev/null
  rm -rf "$home"
}

@test "cursor: reinstall removes legacy mb-compact-reminder.sh copy left by old install" {
  # Simulate an old install that left a physical copy of the renamed hook.
  run_adapter install "$PROJECT"
  mkdir -p "$PROJECT/.cursor/hooks"
  echo '#!/usr/bin/env bash' > "$PROJECT/.cursor/hooks/mb-compact-reminder.sh"
  chmod +x "$PROJECT/.cursor/hooks/mb-compact-reminder.sh"
  # Reinstall must clean up the stale legacy copy.
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ ! -f "$PROJECT/.cursor/hooks/mb-compact-reminder.sh" ]
}
