#!/usr/bin/env bats

# Direct tests for adapters/_lib_agents_md.sh shared ownership logic.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="$REPO_ROOT/adapters/_lib_agents_md.sh"
  PROJECT="$(mktemp -d)"
  SKILL_DIR="$(mktemp -d)"
  mkdir -p "$SKILL_DIR/rules"
  cat > "$SKILL_DIR/rules/RULES.md" <<'EOF'
# Global Rules

1. **Language**: English — responses and code comments. Technical terms may remain in English.
EOF
  command -v jq >/dev/null || skip "jq required"
  # shellcheck source=/dev/null
  source "$LIB"
}

teardown() {
  [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && rm -rf "$PROJECT"
  [ -n "${SKILL_DIR:-}" ] && [ -d "$SKILL_DIR" ] && rm -rf "$SKILL_DIR"
}

@test "agents-md: first install creates AGENTS.md and owners file" {
  run agents_md_install "$PROJECT" "codex" "$SKILL_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
  [ -f "$PROJECT/AGENTS.md" ]
  [ -f "$PROJECT/.mb-agents-owners.json" ]
  jq -e '.owners == ["codex"]' "$PROJECT/.mb-agents-owners.json" >/dev/null
}

@test "agents-md: second owner reuses one shared section and updates refcount" {
  agents_md_install "$PROJECT" "codex" "$SKILL_DIR" >/dev/null
  run agents_md_install "$PROJECT" "opencode" "$SKILL_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
  [ "$(grep -c 'memory-bank:start' "$PROJECT/AGENTS.md")" -eq 1 ]
  jq -e '.owners | contains(["codex","opencode"])' "$PROJECT/.mb-agents-owners.json" >/dev/null
}

@test "agents-md: uninstall decrements owners then removes section on last owner" {
  agents_md_install "$PROJECT" "codex" "$SKILL_DIR" >/dev/null
  agents_md_install "$PROJECT" "opencode" "$SKILL_DIR" >/dev/null

  run agents_md_uninstall "$PROJECT" "codex"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/AGENTS.md" ]
  jq -e '.owners == ["opencode"]' "$PROJECT/.mb-agents-owners.json" >/dev/null

  run agents_md_uninstall "$PROJECT" "opencode"
  [ "$status" -eq 0 ]
  [ ! -f "$PROJECT/AGENTS.md" ]
  [ ! -f "$PROJECT/.mb-agents-owners.json" ]
}

@test "agents-md: owners file write leaves valid json and no temp leftovers" {
  _owners_write "$PROJECT" '{"owners":["cursor"],"initial_had_user_content":false}'
  jq -e '.owners == ["cursor"]' "$PROJECT/.mb-agents-owners.json" >/dev/null
  local tmp_count
  tmp_count=$(find "$PROJECT" -maxdepth 1 -name '.mb-agents-owners.json.*.tmp' | wc -l | tr -d ' ')
  [ "$tmp_count" -eq 0 ]
}

@test "agents-md: section documents the Pi no-commit false-done closure limitation (DF Task 6)" {
  # REQ-DF-062 DoD-3: the emitted block must warn that a hookless agent's (Pi)
  # no-commit false-done is only detectable after the fact via the git-hooks
  # fallback at commit-time. Distinct from Task 7's firewall-loop rule.
  agents_md_install "$PROJECT" "pi" "$SKILL_DIR" >/dev/null
  local body
  body="$(cat "$PROJECT/AGENTS.md")"
  # Names the limitation: a hookless/Pi agent + no-commit false-done.
  [[ "$body" == *"no-commit"* ]] || [[ "$body" == *"no commit"* ]]
  [[ "$body" == *"false-done"* ]] || [[ "$body" == *"false done"* ]]
  # The detection channel is the commit-time git-hooks fallback.
  [[ "$body" == *"commit-time"* ]] || [[ "$body" == *"git-hooks"* ]]
}

@test "agents-md: uninstall preserves user content when MB section was appended" {
  cat > "$PROJECT/AGENTS.md" <<'EOF'
# User content

Keep me.
EOF

  agents_md_install "$PROJECT" "pi" "$SKILL_DIR" >/dev/null
  run agents_md_uninstall "$PROJECT" "pi"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/AGENTS.md" ]
  grep -q '^# User content$' "$PROJECT/AGENTS.md"
  ! grep -q 'memory-bank:start' "$PROJECT/AGENTS.md"
}

@test "agents-md: section carries the dynamic-flow firewall-loop rule (DF Task 7)" {
  # REQ-DF-070 + REQ-DF-060: when a flow is active (goal.md exists) completion is
  # gated by the firewall EXIT CODE, never self-certified by the model. The
  # contract must instruct the agent to LOOP — do not finish until
  # mb-flow-verify.sh exits 0; on a red exit, repair and re-run. Distinct from
  # Task 6's hookless no-commit-false-done limitation note.
  agents_md_install "$PROJECT" "codex" "$SKILL_DIR" >/dev/null
  local body
  body="$(cat "$PROJECT/AGENTS.md")"
  # Flow-active predicate + the firewall named explicitly.
  [[ "$body" == *"goal.md"* ]]
  [[ "$body" == *"mb-flow-verify.sh"* ]]
  # Completion gated on a green (exit 0) firewall result.
  [[ "$body" == *"exit 0"* ]] || [[ "$body" == *"exits 0"* ]]
  # Repair-and-rerun loop on a red exit.
  [[ "$body" == *"re-run"* ]] || [[ "$body" == *"rerun"* ]] || [[ "$body" == *"re-running"* ]]
  # No self-certification — the exit code, not the model, decides done.
  [[ "$body" == *"self-certif"* ]] || [[ "$body" == *"self-assess"* ]] || [[ "$body" == *"do not"* ]]
}

@test "agents-md: dynamic-flow contract references only shipped scripts (no vapor, DF Task 7)" {
  # DoD-2: the emitted block must document only scripts that actually ship in the
  # skill. Scan the whole MB section for every scripts|hooks|adapters/<name>.(sh|py)
  # path it cites and assert each exists in the real repo. Guards against citing a
  # phantom like mb-flow.sh / mb-flow-goal.sh.
  agents_md_install "$PROJECT" "codex" "$SKILL_DIR" >/dev/null
  local section refs p
  section="$(awk '/memory-bank:start/{f=1} f{print} /memory-bank:end/{f=0}' "$PROJECT/AGENTS.md")"
  refs="$(printf '%s\n' "$section" | grep -oE '(scripts|hooks|adapters)/[A-Za-z0-9._-]+\.(sh|py)' | sort -u)"
  [ -n "$refs" ]   # sanity: the contract cites at least one concrete script
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    if [ ! -f "$REPO_ROOT/$p" ]; then
      echo "VAPOR: contract references non-shipped script: $p" >&2
      return 1
    fi
  done <<< "$refs"
}
