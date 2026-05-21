#!/usr/bin/env bats
# End-to-end cross-agent global-storage smoke (Sprint 2 / Stage 5).
#
# Verifies the storyline once across the resolver-aware machinery:
#   1. global mode → context works without project .memory-bank/
#   2. adapter uninstall preserves external bank data
#   3. local mode remains default (no env, no flags → in-repo bank)
#
# Stays compact on purpose — Sprint 2 already has per-adapter and per-hook
# coverage; this suite only locks the cross-cutting invariants.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SANDBOX_HOME="$(mktemp -d)"
  PROJECT="$(mktemp -d)"
  (cd "$PROJECT" && git init -q && git config user.email t@t && git config user.name t)

  export HOME="$SANDBOX_HOME"
  export MB_SKIP_DEPS_CHECK=1

  command -v python3 >/dev/null || skip "python3 required"
  command -v jq >/dev/null || skip "jq required"
}

teardown() {
  [ -n "${SANDBOX_HOME:-}" ] && [ -d "$SANDBOX_HOME" ] && rm -rf "$SANDBOX_HOME"
  [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && rm -rf "$PROJECT"
}

# Resolve bank path via _lib.sh (matches how hooks/scripts resolve in prod).
resolve_bank_for_agent() {
  local agent="$1" project_root="$2"
  bash -c ". '$REPO_ROOT/scripts/_lib.sh' >/dev/null 2>&1 && \
           mb_registry_lookup '$agent' '$project_root' 2>/dev/null"
}

# ─────────────────────────────────────────────────────────────────
# 1. global storage e2e: context works without project .memory-bank
# ─────────────────────────────────────────────────────────────────

@test "global storage e2e: context works without project .memory-bank" {
  # Global install in sandboxed HOME (claude-code default, no project adapter).
  bash "$REPO_ROOT/install.sh" >/dev/null
  [ -f "$HOME/.claude/RULES.md" ]

  # Init global bank for claude-code from inside the project.
  (cd "$PROJECT" && bash "$REPO_ROOT/scripts/mb-init-bank.sh" \
      --storage=global --agent=claude-code --lang en --project-root "$PROJECT" >/dev/null)

  # Project directory must NOT carry a local .memory-bank/ in global mode.
  [ ! -d "$PROJECT/.memory-bank" ]

  # External bank lives under the agent's config dir.
  bank=$(resolve_bank_for_agent claude-code "$PROJECT")
  [ -n "$bank" ]
  [ -d "$bank" ]
  [ -f "$bank/progress.md" ]
  [[ "$bank" == "$HOME/.claude/memory-bank/projects/"*"/.memory-bank" ]]

  # Resolver-aware hook can write into the external bank when MB_PATH is set.
  payload=$(jq -n --arg cwd "$PROJECT" --arg sid "e2e-ctxworks01" \
    '{hook_event_name:"SessionEnd", cwd:$cwd, session_id:$sid, reason:"clear"}')
  printf '%s' "$payload" | MB_PATH="$bank" MB_AUTO_CAPTURE=auto \
    bash "$REPO_ROOT/hooks/session-end-autosave.sh" >/dev/null
  grep -q "Auto-capture.*e2e-ctxw" "$bank/progress.md"

  # Still no local bank — global mode is sticky.
  [ ! -d "$PROJECT/.memory-bank" ]
}

# ─────────────────────────────────────────────────────────────────
# 2. uninstall preserves external bank data
# ─────────────────────────────────────────────────────────────────

@test "global storage e2e: adapter uninstall preserves external bank data" {
  bash "$REPO_ROOT/install.sh" --clients cursor --project-root "$PROJECT" >/dev/null
  (cd "$PROJECT" && bash "$REPO_ROOT/scripts/mb-init-bank.sh" \
      --storage=global --agent=cursor --lang en --project-root "$PROJECT" >/dev/null)

  bank=$(resolve_bank_for_agent cursor "$PROJECT")
  [ -d "$bank" ]
  echo "marker_payload" > "$bank/progress.md"

  # Adapter is owned content — uninstall should only remove adapter files.
  bash "$REPO_ROOT/adapters/cursor.sh" uninstall "$PROJECT" >/dev/null

  # External bank survives intact.
  [ -d "$bank" ]
  grep -q "marker_payload" "$bank/progress.md"

  # Adapter-owned files gone.
  [ ! -f "$PROJECT/.cursor/.mb-manifest.json" ]
}

# ─────────────────────────────────────────────────────────────────
# 3. local mode remains default
# ─────────────────────────────────────────────────────────────────

@test "global storage e2e: local mode remains the default" {
  bash "$REPO_ROOT/install.sh" >/dev/null

  # No --storage flag, no env → local bank in the project.
  (cd "$PROJECT" && bash "$REPO_ROOT/scripts/mb-init-bank.sh" \
      --lang en --project-root "$PROJECT" >/dev/null)

  [ -d "$PROJECT/.memory-bank" ]
  [ -f "$PROJECT/.memory-bank/progress.md" ]

  # No global registry entry was created (storage_mode=local).
  registry="$HOME/.claude/memory-bank/registry.json"
  if [ -f "$registry" ]; then
    # Registry may exist but must not contain this project.
    ! jq -e --arg p "$PROJECT" '.projects | has($p)' "$registry" >/dev/null
  fi
}

# ─────────────────────────────────────────────────────────────────
# 4. install does not silently create either local or global bank
# ─────────────────────────────────────────────────────────────────

@test "global storage e2e: install alone never creates a Memory Bank" {
  bash "$REPO_ROOT/install.sh" --clients cursor --project-root "$PROJECT" >/dev/null
  [ ! -d "$PROJECT/.memory-bank" ]
  [ ! -d "$HOME/.claude/memory-bank/projects" ]
  [ ! -d "$HOME/.cursor/memory-bank/projects" ]
}
