#!/usr/bin/env bats
# Freshness of the managed project blocks (plan 2026-10-07_fix_upgrade-safe-install,
# Stage 2; I-251): every managed unit in the project CLAUDE.md / AGENTS.md / per-host
# rule files carries an `mb-stamp:` line (skill VERSION + checksum of the render
# inputs). The session-start hook compares it with the current stamp: stale → one
# hint line naming `mb-rules.sh sync --scope=project`; MB_AUTO_REFRESH=on → refresh in
# place. No bank → nothing changes. Temp HOME + temp project only.

load lib/assert

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-rules.sh"
  HOOK="$REPO_ROOT/hooks/mb-session-start.sh"
  command -v jq >/dev/null || skip "jq required"
  TMPROOT="$(mktemp -d)"
  export HOME="$TMPROOT/home"
  PROJECT="$TMPROOT/project"
  mkdir -p "$HOME" "$PROJECT/.memory-bank"
  unset MB_PATH MB_AGENT MB_AUTO_REFRESH MB_LANGUAGE MB_COMMENTS_LANGUAGE || true
  printf '# My project\n\nOwn text.\n' > "$PROJECT/CLAUDE.md"
  # An AGENTS.md as an old skill version left it: unstamped MB block, user text after.
  cat > "$PROJECT/AGENTS.md" <<'EOF'
<!-- memory-bank:start -->
<!-- memory-bank-skill-version: 5.3.1 -->
# Memory Bank — Project Rules

Old fat block.
<!-- memory-bank:end -->

# User notes
EOF
}

teardown() { [ -n "${TMPROOT:-}" ] && rm -rf "$TMPROOT"; }

hook() { run bash -c "cd '$PROJECT' && CLAUDE_PROJECT_DIR='$PROJECT' bash '$HOOK'"; }
ctx() { printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext // empty'; }
sync_project() { run bash "$SCRIPT" sync --scope=project --project="$PROJECT"; [ "$status" -eq 0 ]; }

@test "freshness: unstamped block → one hint line naming the refresh command" {
  hook
  [ "$status" -eq 0 ]
  local c
  c="$(ctx)"
  assert_substring "$c" "bash '$REPO_ROOT/scripts/mb-rules.sh' sync --scope=project"
  assert_substring "$c" 'AGENTS.md'
  [ "$(printf '%s\n' "$c" | grep -c 'sync --scope=project')" -eq 1 ]
  assert_substring "$(printf '%s' "$output" | jq -r '.systemMessage')" 'sync --scope=project'
}

@test "freshness: after sync every managed unit is stamped and the hook is silent" {
  sync_project
  assert_grep -qF 'mb-stamp: ' "$PROJECT/CLAUDE.md"
  [ "$(grep -c 'mb-stamp: ' "$PROJECT/AGENTS.md")" -eq 2 ]
  # Old fat block replaced, user text kept.
  refute_grep -qF 'Old fat block.' "$PROJECT/AGENTS.md"
  assert_grep -qF '# User notes' "$PROJECT/AGENTS.md"
  assert_grep -qF 'Own text.' "$PROJECT/CLAUDE.md"
  hook
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
}

@test "freshness: user rules change → the delta block is stale → hint" {
  sync_project
  mkdir -p "$HOME/.claude/memory-bank"
  printf '%s\n' '{"quality": {"testing_trophy": "off"}}' > "$HOME/.claude/memory-bank/rules-profile.json"
  hook
  assert_substring "$(ctx)" 'sync --scope=project'
  assert_substring "$(ctx)" 'CLAUDE.md'
}

@test "freshness: MB_AUTO_REFRESH=on refreshes in place; a second run is byte-identical" {
  run bash -c "cd '$PROJECT' && MB_AUTO_REFRESH=on CLAUDE_PROJECT_DIR='$PROJECT' bash '$HOOK'"
  [ "$status" -eq 0 ]
  refute_substring "$output" 'sync --scope=project'
  assert_grep -qF 'mb-stamp: ' "$PROJECT/AGENTS.md"
  snapshot "$PROJECT/AGENTS.md" "$TMPROOT/a1"
  snapshot "$PROJECT/CLAUDE.md" "$TMPROOT/c1"
  run bash -c "cd '$PROJECT' && MB_AUTO_REFRESH=on CLAUDE_PROJECT_DIR='$PROJECT' bash '$HOOK'"
  [ "$output" = "{}" ]
  assert_unchanged "$PROJECT/AGENTS.md" "$TMPROOT/a1"
  assert_unchanged "$PROJECT/CLAUDE.md" "$TMPROOT/c1"
  sync_project
  assert_unchanged "$PROJECT/AGENTS.md" "$TMPROOT/a1"
  assert_unchanged "$PROJECT/CLAUDE.md" "$TMPROOT/c1"
}

@test "freshness: no bank → silent, files untouched" {
  rm -rf "$PROJECT/.memory-bank"
  snapshot "$PROJECT/AGENTS.md" "$TMPROOT/a0"
  run bash -c "cd '$PROJECT' && MB_AUTO_REFRESH=on CLAUDE_PROJECT_DIR='$PROJECT' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
  assert_unchanged "$PROJECT/AGENTS.md" "$TMPROOT/a0"
}

@test "freshness: old rule files get a fresh body, frontmatter and language kept; repeat is byte-identical" {
  mkdir -p "$PROJECT/.windsurf/rules" "$HOME/.claude"
  printf '%s\n' '{"preferred_language": "ru", "language_rule": "Русский — ответы; комментарии в коде — English."}' \
    > "$HOME/.claude/memory-bank-config.json"
  WS="$PROJECT/.windsurf/rules/memory-bank.md"
  printf -- '---\ntrigger: always_on\n---\n\n# Memory Bank — Project Rules\n\nOld body.\n' > "$WS"
  hook
  assert_substring "$(ctx)" '.windsurf/rules/memory-bank.md'
  sync_project
  [ "$(sed -n 2p "$WS")" = 'trigger: always_on' ]
  refute_grep -qF 'Old body.' "$WS"
  assert_grep -qF 'TDD: new logic' "$WS"
  assert_grep -qF 'Русский — ответы' "$WS"
  assert_grep -qF 'Русский — ответы' "$PROJECT/AGENTS.md"
  snapshot "$WS" "$TMPROOT/ws1"
  sync_project
  assert_unchanged "$WS" "$TMPROOT/ws1"
  hook
  [ "$output" = "{}" ]
}

@test "freshness: Cursor session-start context carries the same hint" {
  run bash -c "printf '{\"workspace_roots\":[\"$PROJECT\"]}' | bash '$REPO_ROOT/hooks/mb-session-start-context.sh'"
  [ "$status" -eq 0 ]
  assert_substring "$(printf '%s' "$output" | jq -r '.additional_context')" 'sync --scope=project'
}

@test "freshness: the check adds <= 100 ms (best of 3)" {
  local best=999 t
  for _ in 1 2 3; do
    t="$(bash -c 'TIMEFORMAT=%R; { time bash -c ". \"$1/adapters/_lib_agents_md.sh\"; mb_project_stale_files \"$2\" >/dev/null"; } 2>&1' _ "$REPO_ROOT" "$PROJECT")"
    t="${t/./}"; t="$((10#$t))"
    [ "$t" -lt "$best" ] && best="$t"
  done
  echo "check: ${best} ms" >&2
  [ "$best" -le 100 ]
}

@test "freshness: the stamp lives in _lib_project_stamp.sh, reached through _lib_agents_md.sh" {
  local lib="$REPO_ROOT/adapters/_lib_project_stamp.sh"
  assert_grep -q '^mb_project_stamp()' "$lib"
  assert_grep -q '^mb_project_stale_files()' "$lib"
  assert_grep -q '^mb_project_blocks_hint()' "$lib"
  refute_grep -q '^mb_project_stamp()\|^mb_project_stale_files()\|^mb_project_blocks_hint()' \
    "$REPO_ROOT/adapters/_lib_agents_md.sh"
  run bash -c '. "$1/adapters/_lib_agents_md.sh" && mb_project_stamp "$2"' _ "$REPO_ROOT" "$PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^mb-stamp:\ [^\ ]+-[0-9a-f]{8}$ ]]
}

# sync is a skill-owned writer: a host rule file it rewrites stays ours for the next
# adapter install (no *.pre-mb-backup.*), while a real user edit is still backed up.
install_hosts() {
  local a
  for a in cursor windsurf cline kilo; do
    run bash "$REPO_ROOT/adapters/$a.sh" install "$PROJECT"
    [ "$status" -eq 0 ]
  done
}
host_rule_files() {
  printf '%s\n' "$PROJECT/.cursor/rules/memory-bank.mdc" "$PROJECT/.windsurf/rules/memory-bank.md" \
    "$PROJECT/.clinerules/memory-bank.md" "$PROJECT/.kilocode/rules/memory-bank.md"
}
setup_hosts() {
  PYTHONUSERBASE="$(/usr/bin/python3 -m site --user-base)"
  export PYTHONUSERBASE
  (cd "$PROJECT" && git init -q)
  install_hosts
  # Install happened "long ago": edits from here on are strictly newer than the manifests.
  find "$PROJECT" -exec touch -t 202001010000 {} +
}

@test "freshness: sync-rewritten host rule files stay ours — re-install makes no rule-file backup" {
  setup_hosts
  sync_project
  assert_substring "$output" 'refreshed'
  install_hosts
  run bash -c "find '$PROJECT' -name '*memory-bank.md*.pre-mb-backup.*'"
  [ -z "$output" ]
}

@test "freshness: a user edit after sync is still backed up by the next install" {
  setup_hosts
  sync_project
  local f
  while IFS= read -r f; do printf 'USER_EDIT_MARKER\n' >> "$f"; done < <(host_rule_files)
  install_hosts
  run bash -c "grep -l USER_EDIT_MARKER '$PROJECT/.cursor/rules/'*.pre-mb-backup.* '$PROJECT/.clinerules/'*.pre-mb-backup.*"
  [ "$status" -eq 0 ]
  assert_substring "$output" 'memory-bank.mdc.pre-mb-backup.'
  assert_substring "$output" 'memory-bank.md.pre-mb-backup.'
}

@test "freshness: a user edit before sync is not laundered by sync — still backed up" {
  setup_hosts
  # Frontmatter: outside the body sync replaces, so the edit survives sync.
  local mdc="$PROJECT/.cursor/rules/memory-bank.mdc"
  awk 'NR == 2 { print "user_key: USER_EDIT_MARKER" } 1' "$mdc" > "$mdc.tmp" && mv "$mdc.tmp" "$mdc"
  sync_project
  install_hosts
  run bash -c "grep -l USER_EDIT_MARKER '$PROJECT/.cursor/rules/'*.pre-mb-backup.*"
  [ "$status" -eq 0 ]
}
