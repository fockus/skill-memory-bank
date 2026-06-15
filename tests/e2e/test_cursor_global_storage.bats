#!/usr/bin/env bats
# Cursor global storage smoke — sessionStart resolves external bank via registry.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SANDBOX_HOME="$(mktemp -d)"
  PROJECT="$(mktemp -d)"
  (cd "$PROJECT" && git init -q && git config user.email t@t && git config user.name t)

  export HOME="$SANDBOX_HOME"
  export MB_SKIP_DEPS_CHECK=1

  command -v jq >/dev/null || skip "jq required"
}

teardown() {
  [ -n "${SANDBOX_HOME:-}" ] && [ -d "$SANDBOX_HOME" ] && rm -rf "$SANDBOX_HOME"
  [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && rm -rf "$PROJECT"
}

resolve_bank_for_agent() {
  local agent="$1" project_root="$2"
  bash -c ". '$REPO_ROOT/scripts/_lib.sh' >/dev/null 2>&1 && \
           mb_registry_lookup '$agent' '$project_root' 2>/dev/null"
}

@test "cursor global storage: sessionStart injects context from registry bank" {
  bash "$REPO_ROOT/install.sh" --clients cursor --project-root "$PROJECT" >/dev/null
  (cd "$PROJECT" && bash "$REPO_ROOT/scripts/mb-init-bank.sh" \
      --storage=global --agent=cursor --lang en --project-root "$PROJECT" >/dev/null)

  bank=$(resolve_bank_for_agent cursor "$PROJECT")
  [ -n "$bank" ]
  [ -d "$bank" ]
  [ ! -d "$PROJECT/.memory-bank" ]

  echo "# Status\nCursor global smoke" > "$bank/status.md"
  echo "- [ ] cursor-global-task" > "$bank/checklist.md"

  payload=$(jq -n --arg ws "$PROJECT" '{workspace_roots: [$ws]}')
  out=$(printf '%s' "$payload" | env MB_AGENT=cursor bash "$REPO_ROOT/hooks/mb-session-start-context.sh")
  echo "$out" | jq -e '.additional_context | contains("[MEMORY BANK: ACTIVE]")' >/dev/null
  echo "$out" | jq -e '.additional_context | contains("cursor-global-task")' >/dev/null
}

@test "cursor global storage: sessionEnd auto-capture appends to registry bank progress.md" {
  bash "$REPO_ROOT/install.sh" --clients cursor --project-root "$PROJECT" >/dev/null
  (cd "$PROJECT" && bash "$REPO_ROOT/scripts/mb-init-bank.sh" \
      --storage=global --agent=cursor --lang en --project-root "$PROJECT" >/dev/null)

  bank=$(resolve_bank_for_agent cursor "$PROJECT")
  [ -n "$bank" ]
  [ -d "$bank" ]
  [ -f "$bank/progress.md" ]
  [ ! -d "$PROJECT/.memory-bank" ]

  # SessionEnd with no .session-lock ⇒ auto-capture path. The stub must land in the
  # external registry bank (resolved via MB_AGENT), not a stray local .memory-bank/.
  sid="deadbeefcafe1234"
  payload=$(jq -n --arg cwd "$PROJECT" --arg sid "$sid" '{cwd: $cwd, session_id: $sid}')
  run env MB_AGENT=cursor bash "$REPO_ROOT/hooks/session-end-autosave.sh" <<<"$payload"
  [ "$status" -eq 0 ]

  grep -q "Auto-capture.*deadbeef" "$bank/progress.md"
  [ ! -d "$PROJECT/.memory-bank" ]

  # Idempotent: a second SessionEnd for the same session adds no duplicate stub.
  run env MB_AGENT=cursor bash "$REPO_ROOT/hooks/session-end-autosave.sh" <<<"$payload"
  [ "$status" -eq 0 ]
  [ "$(grep -c "Auto-capture.*deadbeef" "$bank/progress.md")" -eq 1 ]
}
