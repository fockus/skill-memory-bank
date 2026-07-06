#!/usr/bin/env bats
# Tests for adapters/codex.sh — OpenAI Codex CLI adapter.
#
# Contract:
#   adapters/codex.sh install [PROJECT_ROOT]
#   adapters/codex.sh uninstall [PROJECT_ROOT]
#
# Generates:
#   <project>/AGENTS.md            — shared format (refcount via lib)
#   <project>/.codex/config.toml   — project-level settings
#   <project>/.codex/hooks.json    — experimental hooks (off by default)
#   <project>/.codex/.mb-manifest.json
#
# Codex hooks API: experimental, userpromptsubmit currently stable, lifecycle under dev.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  ADAPTER="$REPO_ROOT/adapters/codex.sh"
  OC_ADAPTER="$REPO_ROOT/adapters/opencode.sh"
  PROJECT="$(mktemp -d)"
  mkdir -p "$PROJECT/.memory-bank"
  echo '# Progress' > "$PROJECT/.memory-bank/progress.md"
  command -v jq >/dev/null || skip "jq required"
  # The adapter DECLARATION must be a stable Codex contract, independent of any
  # inherited operator override — neutralise it so the clean tests are truly clean.
  unset MB_SUBINVOKE_CMD MB_SUBINVOKE_MODEL 2>/dev/null || true
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

@test "codex: install creates AGENTS.md with memory-bank section" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/AGENTS.md" ]
  grep -q "memory-bank:start" "$PROJECT/AGENTS.md"
}

@test "codex: install creates .codex/config.toml with project settings" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/.codex/config.toml" ]
  grep -q "project_doc_max_bytes" "$PROJECT/.codex/config.toml"
}

# ═══════════════════════════════════════════════════════════════
# B5 (F-5): Codex had NO session capture at all — not even the git-hooks
# fallback pi.sh already has. Mirror pi.sh's wiring (install_agents_md_mode)
# so Codex users get post-commit auto-capture + pre-commit <private> warnings
# in a git repo. Wiring only — the hook BODIES live in git-hooks-fallback.sh.
# ═══════════════════════════════════════════════════════════════

@test "codex: install adds git-hooks-fallback session capture in a git repo (B5)" {
  (cd "$PROJECT" && git init -q && git config user.email t@t && git config user.name t)
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ -x "$PROJECT/.git/hooks/post-commit" ]
  grep -q "memory-bank: managed hook" "$PROJECT/.git/hooks/post-commit"
  jq -e '.git_hooks_installed == true' "$PROJECT/.codex/.mb-manifest.json" >/dev/null
}

@test "codex: install skips git-hooks-fallback outside a git repo, no crash (B5)" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ ! -d "$PROJECT/.git" ]
  jq -e '.git_hooks_installed == false' "$PROJECT/.codex/.mb-manifest.json" >/dev/null
}

@test "codex: uninstall removes the git-hooks-fallback capture it installed (B5)" {
  (cd "$PROJECT" && git init -q && git config user.email t@t && git config user.name t)
  run_adapter install "$PROJECT"
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  if [ -f "$PROJECT/.git/hooks/post-commit" ]; then
    run grep -q "memory-bank: managed hook" "$PROJECT/.git/hooks/post-commit"
    [ "$status" -ne 0 ]
  fi
}

@test "codex: install detects git in a worktree (.git is a file, not a dir) (B5)" {
  local main_repo
  main_repo="$(mktemp -d)"
  (cd "$main_repo" && git init -q && git config user.email t@t && git config user.name t \
    && git commit -q --allow-empty -m init \
    && git worktree add -q "$PROJECT/wt" -b mb-b5-wt >/dev/null 2>&1)
  run_adapter install "$PROJECT/wt"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/wt/.git" ]   # worktree marker: a FILE, not a directory
  jq -e '.git_hooks_installed == true' "$PROJECT/wt/.codex/.mb-manifest.json" >/dev/null
  rm -rf "$main_repo"
}

@test "codex: install creates .codex/hooks.json with userpromptsubmit event" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/.codex/hooks.json" ]
  jq . "$PROJECT/.codex/hooks.json" >/dev/null
  jq -e '.hooks.userpromptsubmit // .hooks."user-prompt-submit"' "$PROJECT/.codex/hooks.json" >/dev/null
}

@test "codex: install writes manifest with adapter=codex" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local m="$PROJECT/.codex/.mb-manifest.json"
  [ -f "$m" ]
  jq -e '.schema_version == 1' "$m" >/dev/null
  jq -e '.adapter == "codex"' "$m" >/dev/null
}

@test "codex: install idempotent — 2x run no section duplicates" {
  run_adapter install "$PROJECT"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local count
  count=$(grep -c "memory-bank:start" "$PROJECT/AGENTS.md")
  [ "$count" -eq 1 ]
}

@test "codex: uninstall removes our files and section" {
  run_adapter install "$PROJECT"
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  [ ! -f "$PROJECT/.codex/config.toml" ]
  [ ! -f "$PROJECT/.codex/hooks.json" ]
  [ ! -f "$PROJECT/.codex/.mb-manifest.json" ]
  [ ! -f "$PROJECT/AGENTS.md" ]
}

@test "codex: uninstall no-op if never installed" {
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════════
# Coexistence with OpenCode (shared AGENTS.md refcount)
# ═══════════════════════════════════════════════════════════════

@test "codex+opencode: both install → single AGENTS.md section, refcount=2" {
  bash "$OC_ADAPTER" install "$PROJECT" >/dev/null
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  # Exactly one section
  local count
  count=$(grep -c "memory-bank:start" "$PROJECT/AGENTS.md")
  [ "$count" -eq 1 ]
  # Owners file has both
  jq -e '.owners | contains(["opencode","codex"])' "$PROJECT/.mb-agents-owners.json" >/dev/null
}

@test "codex+opencode: uninstall codex preserves section because opencode still owns" {
  bash "$OC_ADAPTER" install "$PROJECT" >/dev/null
  run_adapter install "$PROJECT"
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  # Section still present (opencode active)
  [ -f "$PROJECT/AGENTS.md" ]
  grep -q "memory-bank:start" "$PROJECT/AGENTS.md"
  # Owners reduced to opencode only
  jq -e '.owners == ["opencode"]' "$PROJECT/.mb-agents-owners.json" >/dev/null
}

@test "codex+opencode: uninstall BOTH removes AGENTS.md entirely (no owners left)" {
  bash "$OC_ADAPTER" install "$PROJECT" >/dev/null
  run_adapter install "$PROJECT"
  run_adapter uninstall "$PROJECT"
  bash "$OC_ADAPTER" uninstall "$PROJECT" >/dev/null
  [ ! -f "$PROJECT/AGENTS.md" ]
  [ ! -f "$PROJECT/.mb-agents-owners.json" ]
}

@test "codex+opencode: existing user AGENTS.md preserved after both uninstall" {
  echo "# User preamble" > "$PROJECT/AGENTS.md"
  bash "$OC_ADAPTER" install "$PROJECT" >/dev/null
  run_adapter install "$PROJECT"
  run_adapter uninstall "$PROJECT"
  bash "$OC_ADAPTER" uninstall "$PROJECT" >/dev/null
  [ -f "$PROJECT/AGENTS.md" ]
  grep -q "User preamble" "$PROJECT/AGENTS.md"
  ! grep -q "memory-bank:start" "$PROJECT/AGENTS.md"
}

# ═══════════════════════════════════════════════════════════════
# Global storage support (Stage 3 — AGENTS.md mentions resolver)
# ═══════════════════════════════════════════════════════════════

@test "codex: AGENTS.md section mentions global storage or resolver for bank path" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local agents="$PROJECT/AGENTS.md"
  [ -f "$agents" ]
  # The shared AGENTS.md section must mention that Memory Bank path can be
  # local OR global (resolved by skill), so users are not surprised in global mode
  grep -qi "MB_PATH\|global storage\|resolver\|resolved\|local OR global\|local or global" "$agents"
}

# ═══════════════════════════════════════════════════════════════
# Per-agent sub-invoke declaration (dynamic-flow Task 12, DoD#1 — REQ-DF-082)
# The adapter DECLARES the shell sub-invoke command mb-fanout uses on Codex.
# ═══════════════════════════════════════════════════════════════

@test "codex: 'subinvoke' action declares the codex sub-invoke command (codex exec, env prompt)" {
  run_adapter subinvoke
  [ "$status" -eq 0 ]
  [[ "$output" == *"codex exec"* ]]
  # The prompt flows ONLY via $MB_FANOUT_PROMPT — never an interpolated literal.
  [[ "$output" == *"\$MB_FANOUT_PROMPT"* ]]
  [[ "$output" == *"read-only"* ]]
}

@test "codex: the adapter's declared sub-invoke MATCHES the resolver's codex table entry" {
  # DoD#1 + DoD#2 coherence: the adapter declaration and the resolver table are
  # the SAME command, so what the adapter declares is exactly what mb-fanout bakes.
  local from_adapter from_resolver
  from_adapter="$(bash "$ADAPTER" subinvoke)"
  from_resolver="$(MB_AGENT=codex bash "$REPO_ROOT/scripts/mb-subinvoke-resolve.sh")"
  [ "$from_adapter" = "$from_resolver" ]
}

@test "codex: the adapter DECLARATION ignores a polluted MB_SUBINVOKE_CMD (stable Codex contract, not an override)" {
  # DoD#1 is an adapter DECLARATION: `codex subinvoke` must always declare the
  # Codex table command, even if an operator override is exported in the env (the
  # override belongs to mb-fanout's RESOLVE path, not the adapter's declaration).
  # Without this, the declaration is non-tautologically distinct from the resolver
  # under a polluted env — which is exactly the contract we assert.
  local declared
  declared="$(MB_SUBINVOKE_CMD='evil-runner "$MB_FANOUT_PROMPT"' bash "$ADAPTER" subinvoke)"
  [[ "$declared" == *"codex exec"* ]]
  [[ "$declared" != *"evil-runner"* ]]
  # And the resolver (RESOLVE path) DOES honour the override — proving the two
  # paths intentionally differ, so the MATCHES test above is not tautological.
  local resolved
  resolved="$(MB_AGENT=codex MB_SUBINVOKE_CMD='evil-runner "$MB_FANOUT_PROMPT"' bash "$REPO_ROOT/scripts/mb-subinvoke-resolve.sh")"
  [[ "$resolved" == *"evil-runner"* ]]
}

# ═══════════════════════════════════════════════════════════════
# C-2: backup + merge for existing user config.toml / hooks.json
# (must never clobber a user's Codex config without a recoverable backup)
# ═══════════════════════════════════════════════════════════════

@test "codex: backs up existing user config.toml before writing" {
  mkdir -p "$PROJECT/.codex"
  printf 'user_key = "keep"\n' > "$PROJECT/.codex/config.toml"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local bk
  bk=$(ls "$PROJECT/.codex/config.toml".pre-mb-backup.* 2>/dev/null | head -1)
  [ -n "$bk" ]
  grep -q 'user_key = "keep"' "$bk"
}

@test "codex: merge preserves foreign keys in config.toml" {
  mkdir -p "$PROJECT/.codex"
  printf 'user_key = "keep"\n' > "$PROJECT/.codex/config.toml"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  grep -q 'user_key = "keep"' "$PROJECT/.codex/config.toml"
  grep -q 'project_doc_max_bytes' "$PROJECT/.codex/config.toml"
}

@test "codex: MB top-level keys stay top-level when user config ends with a [table]" {
  # Regression: a Codex config.toml commonly ends with a section header
  # ([history], [tui], [mcp_servers.*], ...). If MB's block is appended AFTER
  # that header, its top-level keys (project_doc_max_bytes, ...) are parsed as
  # members of the user's last table — Codex never sees them, and the user's
  # table is polluted. MB keys must land at genuine TOML top level.
  command -v python3 >/dev/null || skip "python3 required"
  python3 -c 'import tomllib' 2>/dev/null || skip "tomllib (py3.11+) required"
  mkdir -p "$PROJECT/.codex"
  printf '[history]\npersistence = "save-all"\n' > "$PROJECT/.codex/config.toml"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  python3 - "$PROJECT/.codex/config.toml" <<'PY'
import sys, tomllib
d = tomllib.load(open(sys.argv[1], "rb"))
assert d.get("project_doc_max_bytes") == 65536, f"MB key not at top level: {d}"
assert "project_doc_max_bytes" not in d.get("history", {}), "MB key leaked into user's [history] table"
assert d["history"]["persistence"] == "save-all", "user table value lost"
PY
}

@test "codex: user's own top-level key (approval_policy) is not duplicated → config stays valid TOML" {
  # Regression: MB's block defines approval_policy/project_doc_max_bytes at top
  # level. If the user already set one of those, blindly prepending MB's copy
  # yields a duplicate top-level key → strict TOML parsers (tomllib, Codex) reject
  # the whole file. MB must defer to the user's value, emitting no duplicate.
  command -v python3 >/dev/null || skip "python3 required"
  python3 -c 'import tomllib' 2>/dev/null || skip "tomllib (py3.11+) required"
  mkdir -p "$PROJECT/.codex"
  printf 'approval_policy = "never"\n' > "$PROJECT/.codex/config.toml"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  python3 - "$PROJECT/.codex/config.toml" <<'PY'
import sys, tomllib
d = tomllib.load(open(sys.argv[1], "rb"))  # raises if duplicate key → test fails
assert d["approval_policy"] == "never", f"user value must win, got {d.get('approval_policy')!r}"
assert d.get("project_doc_max_bytes") == 65536, "non-colliding MB key must still be present"
PY
}

@test "codex: uninstall with a corrupted (unpaired) marker does NOT truncate user content" {
  # Regression: an interrupted install / manual edit can leave a lone start
  # marker with no end marker. A naive strip-to-EOF would delete everything after
  # it. The well-formedness guard must leave the file untouched instead.
  mkdir -p "$PROJECT/.codex"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  # Corrupt: drop the end marker, then append user content after the (now lone) block.
  grep -v '<<< memory-bank <<<' "$PROJECT/.codex/config.toml" > "$PROJECT/.codex/config.toml.x"
  printf '\nuser_tail_key = "precious"\n' >> "$PROJECT/.codex/config.toml.x"
  mv "$PROJECT/.codex/config.toml.x" "$PROJECT/.codex/config.toml"
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  # User's tail content must survive (guard refused to strip the malformed block).
  [ -f "$PROJECT/.codex/config.toml" ]
  grep -q 'user_tail_key = "precious"' "$PROJECT/.codex/config.toml"
}

@test "codex: existing hooks.json with non-array userpromptsubmit does not abort install" {
  # Regression: the merge jq assumed .hooks.userpromptsubmit is an array; any
  # other valid-JSON shape made jq exit non-zero → set -e killed install after
  # config.toml was already mutated (partial install). Wrong shape must fall back
  # to the fresh-MB-body branch (original already backed up), not abort.
  mkdir -p "$PROJECT/.codex"
  printf '{"hooks":{"userpromptsubmit":{"command":"weird"}},"keep":"me"}\n' \
    > "$PROJECT/.codex/hooks.json"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  jq . "$PROJECT/.codex/hooks.json" >/dev/null    # valid JSON after install
  # backup preserved the user's original odd shape
  local bk
  bk=$(ls "$PROJECT/.codex/hooks.json".pre-mb-backup.* 2>/dev/null | head -1)
  [ -n "$bk" ]
  jq -e '.keep == "me"' "$bk" >/dev/null
}

@test "codex: user's own top-level 'version' in hooks.json is preserved (not squatted)" {
  # Regression: merge hard-set version to MB's value and uninstall del(.version),
  # clobbering a user's legit top-level version. Merge must keep the user's
  # version; uninstall must not delete it while other user content survives.
  mkdir -p "$PROJECT/.codex"
  printf '{"version":9,"my_key":"keep"}\n' > "$PROJECT/.codex/hooks.json"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  jq -e '.version == 9' "$PROJECT/.codex/hooks.json" >/dev/null
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/.codex/hooks.json" ]
  jq -e '.version == 9 and .my_key == "keep"' "$PROJECT/.codex/hooks.json" >/dev/null
}

@test "codex: config dedup works with no python3 on PATH (pure-awk, no hard dep)" {
  # Regression (round-2): dedup must not depend on python3/tomllib. Hide python3
  # and confirm the collision check still drops the user's duplicate top-level key.
  command -v python3 >/dev/null || skip "python3 required to prove tomllib fallback path"
  python3 -c 'import tomllib' 2>/dev/null || skip "tomllib (py3.11+) required for the parse check"
  mkdir -p "$PROJECT/.codex"
  printf 'approval_policy = "never"\n' > "$PROJECT/.codex/config.toml"
  # Minimal PATH keeping only the tools the adapter needs (awk/jq/grep/sed/mktemp/…)
  # but WITHOUT python3, then install.
  local nopy; nopy="$(mktemp -d)"
  for t in bash sh awk jq grep sed mktemp cat cp mv rm mkdir ls date dirname basename chmod printf env; do
    p="$(command -v "$t" 2>/dev/null)" && ln -sf "$p" "$nopy/$t"
  done
  run env -i HOME="$HOME" PATH="$nopy" bash "$ADAPTER" install "$PROJECT"
  [ "$status" -eq 0 ]
  ! command -v python3 >/dev/null 2>&1 <<<"" || true
  # No duplicate top-level key → valid TOML, user's value wins.
  python3 - "$PROJECT/.codex/config.toml" <<'PY'
import sys, tomllib
d = tomllib.load(open(sys.argv[1], "rb"))
assert d["approval_policy"] == "never"
assert d.get("project_doc_max_bytes") == 65536
PY
  rm -rf "$nopy"
}

@test "codex: uninstall keeps a user's pre-existing version-only hooks.json (no data loss)" {
  # Regression (round-2 blocker): a user file that is exactly {"version":N} must
  # survive uninstall — MB must not infer 'MB-only' from shape and delete it.
  mkdir -p "$PROJECT/.codex"
  printf '{"version":9}\n' > "$PROJECT/.codex/hooks.json"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/.codex/hooks.json" ]
  jq -e '.version == 9' "$PROJECT/.codex/hooks.json" >/dev/null
}

@test "codex: uninstall leaves a wrong-shape hooks.json untouched (no truncation)" {
  # Regression (round-2 new): a valid-JSON but wrong-shape file (string .hooks,
  # from a manual post-install edit) must not be truncated to {} by the strip.
  mkdir -p "$PROJECT/.codex"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  # Corrupt the shape post-install, keeping a foreign key.
  printf '{"hooks":"broken","keep":"me"}\n' > "$PROJECT/.codex/hooks.json"
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/.codex/hooks.json" ]
  jq -e '.keep == "me" and .hooks == "broken"' "$PROJECT/.codex/hooks.json" >/dev/null
}

@test "codex: second install does not duplicate the MB config block" {
  mkdir -p "$PROJECT/.codex"
  printf 'user_key = "keep"\n' > "$PROJECT/.codex/config.toml"
  run_adapter install "$PROJECT"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local count
  count=$(grep -c '>>> memory-bank >>>' "$PROJECT/.codex/config.toml")
  [ "$count" -eq 1 ]
  grep -q 'user_key = "keep"' "$PROJECT/.codex/config.toml"
}

@test "codex: backs up existing user hooks.json and merges foreign keys" {
  mkdir -p "$PROJECT/.codex"
  printf '{"hooks":{"userpromptsubmit":[{"command":"echo user"}]},"my_key":"keep"}\n' \
    > "$PROJECT/.codex/hooks.json"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local bk
  bk=$(ls "$PROJECT/.codex/hooks.json".pre-mb-backup.* 2>/dev/null | head -1)
  [ -n "$bk" ]
  grep -q 'my_key' "$bk"
  jq -e '.my_key == "keep"' "$PROJECT/.codex/hooks.json" >/dev/null
  # MB's own hook is present alongside the user's
  jq -e '[.hooks.userpromptsubmit[]._mb_owned] | any' "$PROJECT/.codex/hooks.json" >/dev/null
  jq -e '[.hooks.userpromptsubmit[].command] | any(. == "echo user")' \
    "$PROJECT/.codex/hooks.json" >/dev/null
}

@test "codex: manifest records config/hooks backup paths" {
  mkdir -p "$PROJECT/.codex"
  printf 'user_key = "keep"\n' > "$PROJECT/.codex/config.toml"
  printf '{"my_key":"keep"}\n' > "$PROJECT/.codex/hooks.json"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  jq -e '.backups | length >= 2' "$PROJECT/.codex/.mb-manifest.json" >/dev/null
}

@test "codex: corrupt existing hooks.json is backed up, replaced with valid MB json" {
  mkdir -p "$PROJECT/.codex"
  printf 'not json at all {{{' > "$PROJECT/.codex/hooks.json"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local bk
  bk=$(ls "$PROJECT/.codex/hooks.json".pre-mb-backup.* 2>/dev/null | head -1)
  [ -n "$bk" ]
  jq . "$PROJECT/.codex/hooks.json" >/dev/null
}

# ═══════════════════════════════════════════════════════════════
# C-2 tail: uninstall must NOT clobber a user's foreign config.toml/
# hooks.json content — it must strip only the MB-managed block/hook
# entries, never rm -f a file that still carries foreign content.
# ═══════════════════════════════════════════════════════════════

@test "codex: uninstall preserves foreign config.toml key, removes only the MB block" {
  mkdir -p "$PROJECT/.codex"
  printf 'user_key = "keep"\n' > "$PROJECT/.codex/config.toml"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  # User's foreign key survives uninstall
  [ -f "$PROJECT/.codex/config.toml" ]
  grep -q 'user_key = "keep"' "$PROJECT/.codex/config.toml"
  # But the MB-managed block is gone
  ! grep -q '>>> memory-bank >>>' "$PROJECT/.codex/config.toml"
  ! grep -q 'project_doc_max_bytes' "$PROJECT/.codex/config.toml"
  # The original pristine backup is untouched by the uninstall logic
  local bk
  bk=$(ls "$PROJECT/.codex/config.toml".pre-mb-backup.* 2>/dev/null | head -1)
  [ -n "$bk" ]
  grep -q 'user_key = "keep"' "$bk"
}

@test "codex: uninstall preserves foreign hooks.json hook, removes only the MB hook entry" {
  mkdir -p "$PROJECT/.codex"
  printf '{"hooks":{"userpromptsubmit":[{"command":"echo user"}]},"my_key":"keep"}\n' \
    > "$PROJECT/.codex/hooks.json"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  # User's foreign key + hook entry survive uninstall
  [ -f "$PROJECT/.codex/hooks.json" ]
  jq -e '.my_key == "keep"' "$PROJECT/.codex/hooks.json" >/dev/null
  jq -e '[.hooks.userpromptsubmit[].command] | any(. == "echo user")' \
    "$PROJECT/.codex/hooks.json" >/dev/null
  # But the MB-owned hook entry is gone
  jq -e '[.hooks.userpromptsubmit[] | select(._mb_owned == true)] | length == 0' \
    "$PROJECT/.codex/hooks.json" >/dev/null
  # The original pristine backup is untouched by the uninstall logic
  local bk
  bk=$(ls "$PROJECT/.codex/hooks.json".pre-mb-backup.* 2>/dev/null | head -1)
  [ -n "$bk" ]
  grep -q 'my_key' "$bk"
}

@test "codex: uninstall with no foreign content removes config.toml/hooks.json entirely (unchanged behavior)" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  [ ! -f "$PROJECT/.codex/config.toml" ]
  [ ! -f "$PROJECT/.codex/hooks.json" ]
}

@test "codex: declared sub-invoke is consumable by bash -c with an env prompt (seam)" {
  # Prove the declared template runs under mb-fanout's `bash -c "$CMD"` seam with
  # the prompt supplied via env — never interpolated. We stub `codex` on PATH so
  # the round-trip needs no real Codex CLI.
  local stub="$PROJECT/stubbin"
  mkdir -p "$stub"
  printf '#!/bin/sh\nprintf "{\\"got\\":\\"%%s\\"}" "$MB_FANOUT_PROMPT"\n' > "$stub/codex"
  chmod +x "$stub/codex"
  local tmpl
  tmpl="$(bash "$ADAPTER" subinvoke)"
  run env PATH="$stub:$PATH" MB_FANOUT_PROMPT="hi-there" bash -c "$tmpl"
  [ "$status" -eq 0 ]
  [[ "$output" == *"hi-there"* ]]
}

# ═══════════════════════════════════════════════════════════════
# B2 (F-1): Codex gets /mb as prompts (~/.codex/prompts/) — global install.sh
# commands-loop must also deliver commands/*.md there, same as it already does
# for Claude/OpenCode/Pi. Full-install sandbox (LESSON L64 pattern): a tmp copy
# of the repo (manifest writes land in the copy, not the tracked repo) + a
# sandboxed $HOME (all client dirs are HOME-derived in install.sh).
# ═══════════════════════════════════════════════════════════════

setup_codex_prompts_sandbox() {
  command -v rsync >/dev/null || skip "rsync required"
  FAKE_HOME="$(mktemp -d)"
  INSTALL_PROJECT="$(mktemp -d)"
  SKILL_SRC="$(mktemp -d)/skill"
  mkdir -p "$SKILL_SRC"
  rsync -a \
    --exclude='.git' \
    --exclude='*.pre-mb-backup.*' \
    --exclude='.index' \
    --exclude='node_modules' \
    "$REPO_ROOT/" "$SKILL_SRC/"
}

teardown_codex_prompts_sandbox() {
  [ -n "${FAKE_HOME:-}" ] && [ -d "$FAKE_HOME" ] && rm -rf "$FAKE_HOME"
  [ -n "${INSTALL_PROJECT:-}" ] && [ -d "$INSTALL_PROJECT" ] && rm -rf "$INSTALL_PROJECT"
  [ -n "${SKILL_SRC:-}" ] && rm -rf "$(dirname "$SKILL_SRC")"
}

@test "codex: global install.sh delivers commands/*.md to ~/.codex/prompts/" {
  setup_codex_prompts_sandbox
  local raw status_
  raw=$(HOME="$FAKE_HOME" MB_SKIP_DEPS_CHECK=1 \
        bash "$SKILL_SRC/install.sh" --clients claude-code \
        --project-root "$INSTALL_PROJECT" --non-interactive \
        </dev/null 2>&1; printf '\n__EXIT__%s' "$?")
  status_="${raw##*__EXIT__}"
  [ "$status_" -eq 0 ]
  local prompts_dir="$FAKE_HOME/.codex/prompts"
  [ -f "$prompts_dir/mb.md" ]
  # At least one dispatcher-style command besides mb.md itself is present.
  local n
  n=$(find "$prompts_dir" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')
  [ "$n" -ge 2 ]
  # Generated FROM commands/ (content-identical to the source, not a stub).
  cmp -s "$SKILL_SRC/commands/mb.md" "$prompts_dir/mb.md"
  teardown_codex_prompts_sandbox
}

@test "codex: ~/.codex/prompts/*.md installed by install.sh are registered in the manifest (uninstall removes them)" {
  setup_codex_prompts_sandbox
  HOME="$FAKE_HOME" MB_SKIP_DEPS_CHECK=1 \
    bash "$SKILL_SRC/install.sh" --clients claude-code \
    --project-root "$INSTALL_PROJECT" --non-interactive \
    </dev/null >/dev/null 2>&1
  [ -f "$SKILL_SRC/.installed-manifest.json" ]
  jq -e --arg p "$FAKE_HOME/.codex/prompts/mb.md" \
    '.files | index($p) != null' "$SKILL_SRC/.installed-manifest.json" >/dev/null
  HOME="$FAKE_HOME" bash "$SKILL_SRC/uninstall.sh" --non-interactive >/dev/null 2>&1
  [ ! -f "$FAKE_HOME/.codex/prompts/mb.md" ]
  teardown_codex_prompts_sandbox
}
