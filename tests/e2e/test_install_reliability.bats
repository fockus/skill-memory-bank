#!/usr/bin/env bats
# End-to-end regression guards: install-reliability (Codex install-audit classes).
#
# These lock in A17 (adapter failure fails top-level install), A22 (manifest
# write/read failures are surfaced, not swallowed), and A24 (no-tty uninstall
# refuses to silently proceed) as a single, AGGREGATING end-to-end narrative
# per case — not a duplicate of the finer-grained unit assertions already in
# tests/e2e/test_install_uninstall.bats / test_install_clients.bats. Each test
# here exercises the FULL install→(failure)→uninstall lifecycle so a
# regression that only breaks the "recovery" half (not just the "detect
# failure" half) still gets caught.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SANDBOX_HOME="$(mktemp -d)"
  export HOME="$SANDBOX_HOME"
  PROJECT="$(mktemp -d)"

  command -v python3 >/dev/null || skip "python3 not installed"
}

teardown() {
  { [ -n "${SANDBOX_HOME:-}" ] && [ -d "$SANDBOX_HOME" ] && rm -rf "$SANDBOX_HOME"; } || true
  { [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && rm -rf "$PROJECT"; } || true
  { [ -n "${SKILL_COPY_PARENT:-}" ] && [ -d "$SKILL_COPY_PARENT" ] && rm -rf "$SKILL_COPY_PARENT"; } || true
  if [ -n "${RO_SKILL_PARENT:-}" ] && [ -d "$RO_SKILL_PARENT" ]; then
    chmod -R u+w "$RO_SKILL_PARENT" 2>/dev/null || true
    rm -rf "$RO_SKILL_PARENT"
  fi
  return 0
}

# Writable rsync copy of the repo — never mutate the real repo's adapters/ or
# VERSION. Mirrors the helper used in test_install_clients.bats (A17).
_make_skill_copy() {
  command -v rsync >/dev/null || skip "rsync required"
  SKILL_COPY_PARENT="$(mktemp -d)"
  SKILL_COPY="$SKILL_COPY_PARENT/skill"
  mkdir -p "$SKILL_COPY"
  rsync -a \
    --exclude='.git' \
    --exclude='*.pre-mb-backup.*' \
    --exclude='.index' \
    --exclude='node_modules' \
    --exclude='.installed-manifest.json' \
    "$REPO_ROOT/" "$SKILL_COPY/"
}

# Read-only skill-source copy — simulates a pip/sudo install tree the current
# user cannot write into (A12/A22 manifest-fallback scenarios).
_make_readonly_skill_copy() {
  command -v rsync >/dev/null || skip "rsync required"
  RO_SKILL_PARENT="$(mktemp -d)"
  RO_SKILL_SRC="$RO_SKILL_PARENT/skill"
  mkdir -p "$RO_SKILL_SRC"
  rsync -a \
    --exclude='.git' \
    --exclude='*.pre-mb-backup.*' \
    --exclude='.index' \
    --exclude='node_modules' \
    --exclude='.installed-manifest.json' \
    "$REPO_ROOT/" "$RO_SKILL_SRC/"
  chmod -R a-w "$RO_SKILL_SRC"
}

# ═══════════════════════════════════════════════════════════════
# (a) manifest write failure — install degrades predictably AND
#     uninstall still fully recovers (A12/A22 aggregate)
# ═══════════════════════════════════════════════════════════════

@test "reliability: manifest write failure surfaces a clear error, and uninstall still fully removes the install" {
  _make_readonly_skill_copy
  unset XDG_DATA_HOME

  # Both the in-tree path AND the XDG fallback are unwritable — worst case.
  mkdir -p "$HOME/.local/share/memory-bank"
  chmod a-w "$HOME/.local/share/memory-bank"

  run env MB_SKIP_DEPS_CHECK=1 bash "$RO_SKILL_SRC/install.sh" --non-interactive
  # Install itself is not a hard failure (manifest is a rollback aid)...
  [ "$status" -eq 0 ]
  # ...but the failure is reported honestly, not swallowed.
  [[ "$output" == *"Manifest write failed"* ]]

  # The actual artifacts were still installed despite the manifest failure.
  [ -f "$HOME/.claude/RULES.md" ]

  # Restore write access so a *subsequent* install can record a real manifest
  # and uninstall has something to roll back through (this is the aggregate
  # part: reliability means recovery is still possible after the incident).
  chmod u+w "$HOME/.local/share/memory-bank"
  run env MB_SKIP_DEPS_CHECK=1 bash "$RO_SKILL_SRC/install.sh" --non-interactive
  [ "$status" -eq 0 ]

  fallback="$HOME/.local/share/memory-bank/.installed-manifest.json"
  [ -f "$fallback" ]
  python3 -c "import json; json.load(open('$fallback'))"

  echo "y" | bash "$RO_SKILL_SRC/uninstall.sh" >/dev/null
  [ ! -f "$fallback" ]
  [ ! -f "$HOME/.claude/RULES.md" ]
}

@test "reliability: corrupt manifest fails uninstall loudly instead of silently no-op-ing" {
  bash "$REPO_ROOT/install.sh" --non-interactive >/dev/null

  export MB_MANIFEST_PATH="$HOME/.mb-reliability-corrupt-manifest.json"
  printf '{"schema_version": 1, "files": [' > "$MB_MANIFEST_PATH"   # truncated JSON

  run bash "$REPO_ROOT/uninstall.sh" -y
  [ "$status" -ne 0 ]
  [[ "$output" == *"corrupt"* ]] || [[ "$output" == *"invalid"* ]]

  # Nothing was silently removed as a side effect of the corrupt manifest.
  [ -f "$HOME/.claude/RULES.md" ]
}

# ═══════════════════════════════════════════════════════════════
# (b) adapter failure → top-level install nonzero, sibling still
#     installs, AND uninstall of the partial state still works (A17 aggregate)
# ═══════════════════════════════════════════════════════════════

@test "reliability: a failing adapter fails top-level install but leaves a cleanly uninstallable partial state" {
  _make_skill_copy
  cat > "$SKILL_COPY/adapters/codex.sh" <<'EOF'
#!/usr/bin/env bash
echo "[stub codex adapter] simulated failure" >&2
exit 1
EOF
  chmod +x "$SKILL_COPY/adapters/codex.sh"

  run bash "$SKILL_COPY/install.sh" --clients codex,cursor --project-root "$PROJECT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"codex"* ]]

  # The healthy sibling (cursor) still installed despite codex's failure.
  [ -f "$PROJECT/.cursor/rules/memory-bank.mdc" ]

  # Reliability means the partial state is still recoverable: uninstall must
  # not choke on the fact that codex partially/never wrote its artifacts.
  run bash "$SKILL_COPY/uninstall.sh" -y
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.claude/RULES.md" ]
}

# ═══════════════════════════════════════════════════════════════
# (c) no-tty uninstall without -y → nonzero + hint, and the
#     documented recovery (-y) still works right after (A24 aggregate)
# ═══════════════════════════════════════════════════════════════

@test "reliability: no-tty uninstall without -y refuses to proceed, then -y recovers cleanly" {
  bash "$REPO_ROOT/install.sh" --non-interactive >/dev/null

  run bash "$REPO_ROOT/uninstall.sh" < /dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *"-y"* ]]
  # Refusal must be a true no-op — nothing partially removed.
  [ -f "$HOME/.claude/RULES.md" ]
  [ -f "$HOME/.claude/CLAUDE.md" ]

  # The documented recovery path (-y, still no tty) completes the job.
  run bash "$REPO_ROOT/uninstall.sh" -y < /dev/null
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.claude/RULES.md" ]
}
