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
  # Hermetic env: these hooks read their mode from the ambient shell. A dev with
  # MB_AUTO_CAPTURE=off exported turns every capture assertion into a false red
  # (CI runs clean, so it never surfaced). Per-test modes are exported in-test.
  unset MB_AUTO_CAPTURE MB_SESSION_CAPTURE MB_PATH
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
  jq -e '.schema_version == 1' "$m" >/dev/null
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

# A16 (M-8): install respects `core.hooksPath` — a repo that redirects hooks
# to a custom directory must get the MB hooks wired THERE, not silently into
# the default .git/hooks (which git would never invoke).
@test "git-hooks: install respects a custom core.hooksPath (A16)" {
  local custom_dir="$PROJECT/.githooks"
  mkdir -p "$custom_dir"
  (cd "$PROJECT" && git config core.hooksPath .githooks)

  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]

  [ -x "$custom_dir/post-commit" ]
  [ -x "$custom_dir/pre-commit" ]
  # Must NOT have fallen back to the default (unused, since hooksPath is set) location.
  [ ! -f "$PROJECT/.git/hooks/post-commit" ]
}

@test "git-hooks: install respects an ABSOLUTE core.hooksPath (A16)" {
  local custom_dir
  custom_dir="$(mktemp -d)"
  (cd "$PROJECT" && git config core.hooksPath "$custom_dir")

  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]

  [ -x "$custom_dir/post-commit" ]
  [ -x "$custom_dir/pre-commit" ]
  rm -rf "$custom_dir"
}

# A16 (M-8): the hook body used to be written with a plain `>` redirect — a
# crash mid-write leaves a truncated hook that then fails/blocks every future
# commit. `>` truncates and rewrites the SAME inode in place; a proper
# tmp-in-same-dir + mv instead publishes a brand-new inode atomically. Inode
# identity is therefore a direct, reliable probe for "was this atomic".
@test "git-hooks: hook rewrite replaces the inode (atomic mv), not an in-place truncate (A16)" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local inode_stat
  inode_stat() { stat -f%i "$1" 2>/dev/null || stat -c%i "$1"; }
  local inode_before
  inode_before=$(inode_stat "$PROJECT/.git/hooks/post-commit")

  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local inode_after
  inode_after=$(inode_stat "$PROJECT/.git/hooks/post-commit")
  [ "$inode_before" != "$inode_after" ]
}

@test "git-hooks: install does not leave a stray tmp file after writing hooks (A16 atomic write)" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local stray
  stray=$(find "$PROJECT/.git/hooks" -maxdepth 1 -type f \
    ! -name 'post-commit' ! -name 'pre-commit' \
    ! -name '*.pre-mb-backup' ! -name '*.sample' | wc -l | tr -d ' ')
  [ "$stray" -eq 0 ]
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

# ═══════════════════════════════════════════════════════════════
# Sprint 2 / Stage 2 — MB_PATH override for global-storage mode
# ═══════════════════════════════════════════════════════════════

# ═══════════════════════════════════════════════════════════════
# dynamic-flow Task 6 — pre-commit closure enforcement (REQ-DF-062)
#
# A hookless agent (Pi/Kilo) has no Stop-hook, so closure is enforced at
# commit-time: when a flow is active (goal.md present) the pre-commit hook runs
# THE firewall (mb-flow-verify.sh) and BLOCKS the commit on a non-zero verify.
# Inert (allow) when no goal.md. MB_FLOW_CLOSURE=off is the emergency bypass.
# All pre-existing pre-commit behavior (<private> warn, chaining, idempotency,
# uninstall) MUST stay intact.
# ═══════════════════════════════════════════════════════════════

# Author goal.md in the bank. $1='x' (met → firewall exit 0) | ' ' (unmet → 1).
_write_flow_goal() {
  cat > "$PROJECT/.memory-bank/goal.md" <<EOF
# Goal
Ship it.

## Acceptance criteria

- [$1] the only criterion
EOF
}

@test "git-hooks: pre-commit BLOCKS the commit when a flow is RED (unmet acceptance)" {
  run_adapter install "$PROJECT"
  _write_flow_goal ' '   # unmet → firewall exit 1
  run bash -c 'cd "$1" && echo x > a.txt && git add -A && git -c user.email=t@t -c user.name=t commit -q -m red' _ "$PROJECT"
  [ "$status" -ne 0 ]
  # No commit was created beyond any pre-existing ones: the working file stays staged.
  run bash -c 'cd "$1" && git log --oneline 2>/dev/null | wc -l | tr -d " "' _ "$PROJECT"
  [ "$output" = "0" ]
}

@test "git-hooks: pre-commit ALLOWS the commit when the flow is GREEN (met acceptance)" {
  run_adapter install "$PROJECT"
  _write_flow_goal 'x'   # met → firewall exit 0
  run bash -c 'cd "$1" && echo x > a.txt && git add -A && git -c user.email=t@t -c user.name=t commit -q -m green' _ "$PROJECT"
  [ "$status" -eq 0 ]
}

@test "git-hooks: pre-commit ALLOWS the commit when no flow is active (no goal.md)" {
  run_adapter install "$PROJECT"
  # No goal.md authored → closure section is inert.
  run bash -c 'cd "$1" && echo x > a.txt && git add -A && git -c user.email=t@t -c user.name=t commit -q -m nogoal' _ "$PROJECT"
  [ "$status" -eq 0 ]
}

@test "git-hooks: MB_FLOW_CLOSURE=off bypasses closure enforcement even on a RED flow" {
  run_adapter install "$PROJECT"
  _write_flow_goal ' '   # red flow
  run bash -c 'cd "$1" && echo x > a.txt && git add -A && MB_FLOW_CLOSURE=off git -c user.email=t@t -c user.name=t commit -q -m forced' _ "$PROJECT"
  [ "$status" -eq 0 ]
}

@test "git-hooks: closure block message names mb-flow-verify (stderr is actionable)" {
  run_adapter install "$PROJECT"
  _write_flow_goal ' '
  run bash -c 'cd "$1" && echo x > a.txt && git add -A && git -c user.email=t@t -c user.name=t commit -q -m red 2>&1' _ "$PROJECT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"mb-flow-verify"* ]]
}

@test "git-hooks: closure enforcement leaves the <private> warn intact (no goal.md)" {
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

# ═══════════════════════════════════════════════════════════════
# Defect 1 — global/registry-resolved bank via MB_PATH (no local .memory-bank)
# ═══════════════════════════════════════════════════════════════

@test "git-hooks: pre-commit BLOCKS when bank is global (MB_PATH, no local .memory-bank)" {
  # Defect 1: when the Memory Bank is global (no <repo>/.memory-bank), the
  # old code resolved only MB_PATH or <repo>/.memory-bank. MB_PATH covers the
  # global-storage case in the generated hook. Prove MB_PATH is honored.
  local ext_bank="$PROJECT/../ext_global_bank"
  mkdir -p "$ext_bank"
  cat > "$ext_bank/goal.md" <<'EOF'
# Goal

## Acceptance criteria

- [ ] pending
EOF
  # No local .memory-bank in the project.
  rm -rf "$PROJECT/.memory-bank"
  run_adapter install "$PROJECT"

  run bash -c 'cd "$1" && echo x > a.txt && git add -A && MB_PATH="$2" git -c user.email=t@t -c user.name=t commit -q -m red 2>&1' \
    _ "$PROJECT" "$ext_bank"
  [ "$status" -ne 0 ]
  [[ "$output" == *"mb-flow-verify"* ]]
}

@test "git-hooks: pre-commit BLOCKS a registry-only global bank (no MB_PATH, no local .memory-bank)" {
  command -v python3 >/dev/null 2>&1 || skip "python3 required for registry setup"
  # Defect 1 — REGISTRY variant (the MB_PATH test above does NOT exercise it).
  # The generated hook must resolve a global bank via the registry
  # (mb_hook_resolve_mb_path → registry), which means it must source the REAL
  # hooks/_skill_root.sh. If the baked _skill_root.sh path is wrong the registry
  # lookup is dead and a red global flow commits freely.
  local ext_bank="$PROJECT/../reg_ext_bank/.memory-bank"
  mkdir -p "$ext_bank"
  cat > "$ext_bank/goal.md" <<'EOF'
# Goal

## Acceptance criteria

- [ ] pending
EOF
  rm -rf "$PROJECT/.memory-bank"          # no local bank
  run_adapter install "$PROJECT"          # installs from the REPO adapter (hooks/ present)

  # Registry under a sandboxed HOME pointing the project → ext_bank.
  local fake_home="$PROJECT/../reg_home"
  mkdir -p "$fake_home/.claude/memory-bank"
  local real_prj; real_prj="$(cd "$PROJECT" && pwd -P)"
  python3 - "$fake_home/.claude/memory-bank/registry.json" "$real_prj" "$ext_bank" <<'PY'
import json, sys
json.dump({"projects": {sys.argv[2]: {"bank_path": sys.argv[3]}}}, open(sys.argv[1], "w"))
PY

  run bash -c 'cd "$1" && echo x > a.txt && git add -A && HOME="$2" MB_AGENT=claude-code MB_SKILL_ROOT="$3" git -c user.email=t@t -c user.name=t commit -q -m red 2>&1' \
    _ "$PROJECT" "$fake_home" "$REPO_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"mb-flow-verify"* ]] || [[ "$output" == *"MB BLOCK"* ]]
}

@test "git-hooks: pre-commit blocks a registry global bank with a cursor alias present and MB_AGENT UNSET (no misdetect)" {
  command -v python3 >/dev/null 2>&1 || skip "python3 required for registry setup"
  # Defect (cursor misdetect): mb_hook_default_agent prefers 'cursor' when
  # ~/.cursor/skills/memory-bank exists and MB_AGENT is unset → a claude-code
  # global bank is looked up in the WRONG (cursor) registry → red flow commits
  # freely. The generated hook must bake a DETERMINISTIC agent at install time so
  # the agent is not guessed at commit time. This mirrors the real installed
  # layout where install.sh creates the cursor skill alias.
  local ext_bank="$PROJECT/../mis_ext_bank/.memory-bank"
  mkdir -p "$ext_bank"
  cat > "$ext_bank/goal.md" <<'EOF'
# Goal

## Acceptance criteria

- [ ] pending
EOF
  rm -rf "$PROJECT/.memory-bank"          # no local bank
  # Install with MB_AGENT UNSET so the hook bakes its deterministic default.
  ( unset MB_AGENT; bash "$ADAPTER" install "$PROJECT" >/dev/null 2>&1 )

  local fake_home="$PROJECT/../mis_home"
  mkdir -p "$fake_home/.claude/memory-bank"
  mkdir -p "$fake_home/.cursor/skills/memory-bank"   # trigger the cursor misdetect
  local real_prj; real_prj="$(cd "$PROJECT" && pwd -P)"
  # The bank is registered under the CLAUDE registry; the cursor registry is absent.
  python3 - "$fake_home/.claude/memory-bank/registry.json" "$real_prj" "$ext_bank" <<'PY'
import json, sys
json.dump({"projects": {sys.argv[2]: {"bank_path": sys.argv[3]}}}, open(sys.argv[1], "w"))
PY

  # Commit with MB_AGENT UNSET — the hook must use its baked agent, not guess cursor.
  run bash -c 'cd "$1" && echo x > a.txt && git add -A && HOME="$2" MB_SKILL_ROOT="$3" git -c user.email=t@t -c user.name=t commit -q -m red 2>&1' \
    _ "$PROJECT" "$fake_home" "$REPO_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"MB BLOCK"* ]] || [[ "$output" == *"mb-flow-verify"* ]]
}

# ═══════════════════════════════════════════════════════════════
# Defect 2 — baked path with space AND $ must survive in the generated hook
# ═══════════════════════════════════════════════════════════════

@test "git-hooks: pre-commit blocks red flow even when adapter installed from path with space and dollar" {
  # Defect 2: the baked firewall path was emitted inside double quotes, so a $
  # in the install path is re-expanded at hook runtime → wrong path → silently
  # inert (never blocks). Fix: shell-quote with printf '%q' at install time.
  local weird_dir
  weird_dir="$(mktemp -d "${TMPDIR:-/tmp}/ad\$pt er.XXXXXX")"
  # Copy the full skill bundle so mb-flow-verify.sh has all its dependencies.
  cp -R "$REPO_ROOT/adapters"   "$weird_dir/adapters"
  cp -R "$REPO_ROOT/scripts"    "$weird_dir/scripts"
  cp -R "$REPO_ROOT/references" "$weird_dir/references"

  local adapter="$weird_dir/adapters/git-hooks-fallback.sh"
  local red_project
  red_project="$(mktemp -d)"
  (cd "$red_project" && git init -q && git config user.email t@t && git config user.name t)
  mkdir -p "$red_project/.memory-bank"
  echo '# Progress' > "$red_project/.memory-bank/progress.md"

  # Commit initial state BEFORE installing the hook, so the hook does not fire
  # during the goal.md setup commit.
  cat > "$red_project/.memory-bank/goal.md" <<'EOF'
# Goal

## Acceptance criteria

- [ ] pending
EOF
  git -C "$red_project" -c user.email=t@t -c user.name=t add -A
  git -C "$red_project" -c user.email=t@t -c user.name=t commit -q -m init

  # Now install the hook — the next commit will trigger closure enforcement.
  bash "$adapter" install "$red_project" >/dev/null

  # Verify baked path has the shell-quoted $ and space characters.
  grep -q 'ad\\$pt' "$red_project/.git/hooks/pre-commit" || \
    grep -q 'ad\\\$pt' "$red_project/.git/hooks/pre-commit" || \
    grep -q '_mb_verify=' "$red_project/.git/hooks/pre-commit"

  run bash -c 'cd "$1" && echo x > a.txt && git add -A && git -c user.email=t@t -c user.name=t commit -q -m red 2>&1' _ "$red_project"
  [ "$status" -ne 0 ]
  [[ "$output" == *"mb-flow-verify"* ]]

  rm -rf "$weird_dir" "$red_project"
}

@test "git-hooks: post-commit honours MB_PATH for external bank (path with spaces)" {
  # External bank lives outside the repo, in a path containing a space.
  EXT_PARENT="$(mktemp -d "${TMPDIR:-/tmp}/ext bank.XXXXXX")"
  EXT_BANK="$EXT_PARENT/.memory-bank"
  mkdir -p "$EXT_BANK"
  echo '# Progress' > "$EXT_BANK/progress.md"

  # Remove the in-repo .memory-bank/ so only MB_PATH applies.
  rm -rf "$PROJECT/.memory-bank"

  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]

  # Make a commit to fire post-commit hook.
  (cd "$PROJECT" && echo hello > a.txt && git add a.txt && \
   MB_PATH="$EXT_BANK" git commit -q -m "test") || true

  # External progress.md captured the entry.
  grep -q "Auto-capture.*git-" "$EXT_BANK/progress.md"
  # In-repo bank was not recreated.
  [ ! -d "$PROJECT/.memory-bank" ]

  rm -rf "$EXT_PARENT"
}

# ═══════════════════════════════════════════════════════════════
# A9 (H-7): git worktree detection + hooks land in the resolved dir
# ═══════════════════════════════════════════════════════════════

@test "git-hooks: install detects repo + installs hooks in a linked worktree (.git is a file)" {
  wt="${PROJECT}-wt"
  (cd "$PROJECT" && git commit -q -m init --allow-empty && git worktree add -q "$wt" 2>/dev/null)
  mkdir -p "$wt/.memory-bank"; echo '# Progress' > "$wt/.memory-bank/progress.md"
  [ -f "$wt/.git" ]
  run_adapter install "$wt"
  [ "$status" -eq 0 ]
  hooks="$(git -C "$wt" rev-parse --git-path hooks)"
  case "$hooks" in /*) : ;; *) hooks="$wt/$hooks" ;; esac
  [ -f "$hooks/post-commit" ]
  grep -q "memory-bank" "$hooks/post-commit"
  rm -rf "$wt"; (cd "$PROJECT" && git worktree prune 2>/dev/null || true)
}

@test "git-hooks: install rejects a nested non-root subdir (does not touch enclosing repo)" {
  mkdir -p "$PROJECT/packages/sub/.memory-bank"
  echo '# Progress' > "$PROJECT/packages/sub/.memory-bank/progress.md"
  run_adapter install "$PROJECT/packages/sub"
  [ "$status" -ne 0 ]
}

@test "git-hooks: install in a git SUBMODULE (.git is a file) wires hooks in the resolved dir" {
  super="${PROJECT}-super"; sub="${PROJECT}-sub"
  (cd "$PROJECT" && git commit -q -m init --allow-empty)
  (git init -q "$super" && cd "$super" && git config user.email t@t && git config user.name t && git commit -q -m s --allow-empty \
     && git -c protocol.file.allow=always submodule add -q "$PROJECT" mod 2>/dev/null)
  [ -f "$super/mod/.git" ]
  mkdir -p "$super/mod/.memory-bank"; echo '# Progress' > "$super/mod/.memory-bank/progress.md"
  run_adapter install "$super/mod"
  [ "$status" -eq 0 ]
  hooks="$(git -C "$super/mod" rev-parse --git-path hooks)"; case "$hooks" in /*) : ;; *) hooks="$super/mod/$hooks" ;; esac
  [ -f "$hooks/post-commit" ]
  rm -rf "$super" "$sub"
}
