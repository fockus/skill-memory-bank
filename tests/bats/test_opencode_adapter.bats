#!/usr/bin/env bats
# Tests for adapters/opencode.sh — OpenCode cross-agent adapter.
#
# Contract:
#   adapters/opencode.sh install [PROJECT_ROOT]
#   adapters/opencode.sh uninstall [PROJECT_ROOT]
#
# Generates:
#   <project>/AGENTS.md                     — shared format (uses markers)
#   <project>/opencode.json                  — plugin registration
#   <project>/.opencode/plugins/memory-bank.js — TypeScript plugin (compiled JS)
#   <project>/.opencode/.mb-manifest.json    — ownership tracking
#
# OpenCode plugins: TS/JS modules with hooks object.
# Key events: session.created/idle/deleted, tool.execute.before/after,
#             experimental.session.compacting (PreCompact equivalent).

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  ADAPTER="$REPO_ROOT/adapters/opencode.sh"
  PROJECT="$(mktemp -d)"
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

@test "opencode: install creates AGENTS.md with memory-bank markers" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/AGENTS.md" ]
  grep -q "<!-- memory-bank:start -->" "$PROJECT/AGENTS.md"
  grep -q "<!-- memory-bank:end -->" "$PROJECT/AGENTS.md"
}

@test "opencode: install creates opencode.json with plugin registration" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/opencode.json" ]
  jq . "$PROJECT/opencode.json" >/dev/null
  jq -e '.plugin | length > 0' "$PROJECT/opencode.json" >/dev/null
}

@test "opencode: install creates plugin JS file with hooks export" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local plugin="$PROJECT/.opencode/plugins/memory-bank.js"
  [ -f "$plugin" ]
  # Plugin must reference key events
  grep -q "session.idle\|session.deleted" "$plugin"
  grep -q "experimental.session.compacting\|tool.execute.before" "$plugin"
}

@test "opencode: install writes manifest" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local m="$PROJECT/.opencode/.mb-manifest.json"
  [ -f "$m" ]
  jq -e '.adapter == "opencode"' "$m" >/dev/null
  jq -e '.agents_md_owned == true' "$m" >/dev/null
}

@test "opencode: install idempotent — 2x run no duplicates" {
  run_adapter install "$PROJECT"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  # Exactly one start/end marker in AGENTS.md
  local start_count end_count
  start_count=$(grep -c "memory-bank:start" "$PROJECT/AGENTS.md")
  end_count=$(grep -c "memory-bank:end" "$PROJECT/AGENTS.md")
  [ "$start_count" -eq 1 ]
  [ "$end_count" -eq 1 ]
}

@test "opencode: install preserves existing AGENTS.md user content" {
  cat > "$PROJECT/AGENTS.md" <<'EOF'
# User's AGENTS.md

Custom user instructions here.
EOF
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  # User content preserved
  grep -q "Custom user instructions" "$PROJECT/AGENTS.md"
  # Our section added
  grep -q "memory-bank:start" "$PROJECT/AGENTS.md"
  # Manifest tracks that we did NOT own the file
  jq -e '.agents_md_owned == false' "$PROJECT/.opencode/.mb-manifest.json" >/dev/null
}

@test "opencode: install merges with existing opencode.json" {
  cat > "$PROJECT/opencode.json" <<'EOF'
{
  "plugin": ["./user/my-plugin.js"],
  "theme": "dark"
}
EOF
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  # User entries preserved
  jq -e '.theme == "dark"' "$PROJECT/opencode.json" >/dev/null
  jq -e '.plugin | map(.) | index("./user/my-plugin.js")' "$PROJECT/opencode.json" >/dev/null
  # Our plugin added
  jq -e '.plugin | length >= 2' "$PROJECT/opencode.json" >/dev/null
}

# ═══════════════════════════════════════════════════════════════
# Uninstall
# ═══════════════════════════════════════════════════════════════

@test "opencode: uninstall removes plugin file and manifest" {
  run_adapter install "$PROJECT"
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  [ ! -f "$PROJECT/.opencode/plugins/memory-bank.js" ]
  [ ! -f "$PROJECT/.opencode/.mb-manifest.json" ]
}

@test "opencode: uninstall deletes AGENTS.md if we created it (sole owner)" {
  run_adapter install "$PROJECT"
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  [ ! -f "$PROJECT/AGENTS.md" ]
}

@test "opencode: uninstall preserves AGENTS.md user content, removes our section" {
  cat > "$PROJECT/AGENTS.md" <<'EOF'
# User's AGENTS.md

Custom user instructions here.
EOF
  run_adapter install "$PROJECT"
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/AGENTS.md" ]
  grep -q "Custom user instructions" "$PROJECT/AGENTS.md"
  ! grep -q "memory-bank:start" "$PROJECT/AGENTS.md"
}

@test "opencode: uninstall removes our plugin from opencode.json, preserves user entries" {
  cat > "$PROJECT/opencode.json" <<'EOF'
{
  "plugin": ["./user/my-plugin.js"],
  "theme": "dark"
}
EOF
  run_adapter install "$PROJECT"
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/opencode.json" ]
  jq -e '.theme == "dark"' "$PROJECT/opencode.json" >/dev/null
  jq -e '.plugin | map(.) | index("./user/my-plugin.js")' "$PROJECT/opencode.json" >/dev/null
  # Our plugin reference gone
  ! jq -e '.plugin | map(.) | any(contains("memory-bank"))' "$PROJECT/opencode.json" >/dev/null
}

@test "opencode: uninstall no-op if never installed" {
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
}
