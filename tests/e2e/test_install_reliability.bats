#!/usr/bin/env bats
# End-to-end regression guards: install-reliability (Codex install-audit classes).
#
# These lock in A17 (adapter failure fails top-level install), A22 (manifest
# write/read failures are surfaced, not swallowed), and A24 (no-tty uninstall
# refuses to silently proceed). Required-render faults additionally preserve
# exact pending preimages and previously committed ownership.

load ../bats/lib/assert

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SANDBOX_HOME="$(mktemp -d)"
  export HOME="$SANDBOX_HOME"
  # Per-test manifest: never the repo's own (the owner's live install manifest).
  export MB_MANIFEST_PATH="$BATS_TEST_TMPDIR/installed-manifest.json"
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
  unset MB_MANIFEST_PATH   # these tests exercise the resolver's own default, on a copy
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

_required_render_failure() {
  local kind="$1" fault="$BATS_TEST_TMPDIR/read-EIO" marker='<!-- memory-bank-opencode:start -->' prior record
  local -a options=()
  _make_skill_copy
  export XDG_CONFIG_HOME="$HOME/xdg" TMPDIR="$HOME/tmp"
  local agents="$XDG_CONFIG_HOME/opencode/AGENTS.md" source="$SKILL_COPY/rules/CLAUDE-GLOBAL.md"
  prior="$XDG_CONFIG_HOME/opencode/commands/adr.md"; record="$MB_MANIFEST_PATH"
  mkdir -p "$fault" "$(dirname "$agents")" "$TMPDIR"
  if [ "$kind" != first ]; then
    case "$kind" in legacy|localize) marker='<!-- memory-bank:start -->' ;; esac
    printf 'User before\n%s\nPrevious managed instructions\n%s\nUser after\n' "$marker" "${marker/start/end}" > "$agents"
    chmod 640 "$agents"
  fi
  if [ "$kind" = partway ]; then
    options+=(--with-extensions=opencode)
    prior="$XDG_CONFIG_HOME/opencode/agent/mb-developer.md"; record="$XDG_CONFIG_HOME/opencode/.mb-global-extensions-manifest.json"
  fi
  [ "$kind" != late ] || source="$SKILL_COPY/rules/key-rules.json"
  cat > "$fault/sitecustomize.py" <<'PY'
import errno, io, json, os, shutil, sys
from pathlib import Path
original = io.open
def checked(file, *args, **kwargs):
    kind = os.environ['FAULT_KIND']
    match = str(file) == os.environ['FAULT_READ'] and (kind == 'late' or sys.argv[0] == '-')
    if kind == 'late':
        match = match and any('<!-- mb-key-rules:start -->' in p.read_text()
                              for p in (Path(os.environ['HOME']) / '.pi/agent').glob('AGENTS.md'))
    if kind == 'localize':
        match = False
        if '<!-- memory-bank-opencode:start -->' in sys.argv:
            target = sys.argv[sys.argv.index('--path') + 1] if '--path' in sys.argv else sys.argv[1]
            match = str(file) == target
    if match:
        root, agents = Path(os.environ['FAULT_DIR']), Path(os.environ['FAULT_AGENTS'])
        for key in ('MB_MANIFEST_PATH', 'FAULT_RECORD'):
            shutil.copy2(os.environ[key], root / key)
        if agents.exists():
            shutil.copy2(agents, root / 'agents.before')
            info = agents.stat()
            (root / 'stat.before').write_text(json.dumps([info.st_mode, info.st_ino]))
        raise OSError(errno.EIO, 'required-source read EIO', str(file))
    return original(file, *args, **kwargs)
io.open = checked
PY
  run env PYTHONPATH="$fault" FAULT_KIND="$kind" FAULT_READ="$source" FAULT_DIR="$fault" FAULT_AGENTS="$agents" FAULT_RECORD="$record" \
    bash "$SKILL_COPY/install.sh" --non-interactive --clients opencode --project-root "$PROJECT" "${options[@]}"
  printf '%s\n' "$output" > "$BATS_TEST_TMPDIR/render-output"
  [ ! -f "$agents" ] || cp -p "$agents" "$BATS_TEST_TMPDIR/agents.after"
  snapshot "$MB_MANIFEST_PATH" "$BATS_TEST_TMPDIR/manifest.after"
  [ "$status" -ne 0 ]
  assert_substring "$output" 'required-source read EIO'
  refute_substring "$output" 'Manifest saved'
  assert_unchanged "$MB_MANIFEST_PATH" "$fault/MB_MANIFEST_PATH"
  assert_unchanged "$record" "$fault/FAULT_RECORD"
  if [ -f "$fault/agents.before" ]; then
    assert_unchanged "$agents" "$fault/agents.before"
    python3 -c 'import json,os,sys; s=os.stat(sys.argv[1]); assert [s.st_mode,s.st_ino] == json.load(open(sys.argv[2]))' "$agents" "$fault/stat.before"
  else refute_file "$agents"; fi
  [ "$kind" != legacy ] || assert_grep -qF '<!-- memory-bank:start -->' "$fault/agents.before"
  case "$kind" in partway|late) python3 "$SKILL_COPY/adapters/opencode_files.py" owned "$prior" "$record" "$XDG_CONFIG_HOME/opencode" ;; esac
  [ -z "$(find "$TMPDIR" -mindepth 1 -print)" ]
}

@test "render EIO: first install never publishes a partial OpenCode block" { _required_render_failure first; }
@test "render EIO: legacy markers remain unchanged until required rendering succeeds" { _required_render_failure legacy; }
@test "render EIO: partway failure preserves instructions and committed global roles" { _required_render_failure partway; }
@test "render EIO: required OpenCode localization preserves the previous instructions" { _required_render_failure localize; }
@test "render EIO: late Key rules source failure retains completed checkpoint ownership" { _required_render_failure late; }

# ═══════════════════════════════════════════════════════════════
# (a) unavailable ownership fails before mutation; restored access permits recovery.
# ═══════════════════════════════════════════════════════════════

@test "reliability: unavailable ownership preserves user files before a successful retry and uninstall" {
  _make_readonly_skill_copy
  unset XDG_DATA_HOME

  # Both the in-tree path AND the XDG fallback are unwritable — worst case.
  mkdir -p "$HOME/.local/share/memory-bank"
  chmod a-w "$HOME/.local/share/memory-bank"
  mkdir -p "$HOME/.claude" "$HOME/.config/opencode" "$HOME/.pi/agent"
  printf 'Original user rules\n' > "$HOME/.claude/RULES.md"
  printf '{"theme":"user-theme"}\n' > "$HOME/.config/opencode/opencode.json"
  printf '{"theme":"user-pi"}\n' > "$HOME/.pi/agent/settings.json"
  snapshot "$HOME/.claude/RULES.md" "$BATS_TEST_TMPDIR/rules.before"
  snapshot "$HOME/.config/opencode/opencode.json" "$BATS_TEST_TMPDIR/opencode.before"
  snapshot "$HOME/.pi/agent/settings.json" "$BATS_TEST_TMPDIR/pi.before"
  run env MB_SKIP_DEPS_CHECK=1 bash "$RO_SKILL_SRC/install.sh" --non-interactive --clients opencode --project-root "$PROJECT"
  [ "$status" -ne 0 ]
  assert_substring "$output" 'manifest'
  refute_substring "$output" 'Manifest saved'
  assert_unchanged "$HOME/.claude/RULES.md" "$BATS_TEST_TMPDIR/rules.before"
  assert_unchanged "$HOME/.config/opencode/opencode.json" "$BATS_TEST_TMPDIR/opencode.before"
  assert_unchanged "$HOME/.pi/agent/settings.json" "$BATS_TEST_TMPDIR/pi.before"
  refute_file "$HOME/.config/opencode/commands/adr.md"
  [ ! -e "$HOME/.config/opencode/skills/memory-bank" ]
  [ -z "$(find "$HOME" -name '*.pre-mb-backup.*' -print)" ]
  chmod u+w "$HOME/.local/share/memory-bank"
  run env MB_SKIP_DEPS_CHECK=1 bash "$RO_SKILL_SRC/install.sh" --non-interactive --clients opencode --project-root "$PROJECT"
  [ "$status" -eq 0 ]

  fallback="$HOME/.local/share/memory-bank/.installed-manifest.json"
  [ -f "$fallback" ]
  python3 -c "import json; json.load(open('$fallback'))"

  run bash "$RO_SKILL_SRC/uninstall.sh" -y
  [ "$status" -eq 0 ]
  [ ! -f "$fallback" ]
  refute_file "$HOME/.config/opencode/commands/adr.md"
  refute_file "$PROJECT/.opencode/plugins/memory-bank.js"
  assert_unchanged "$HOME/.claude/RULES.md" "$BATS_TEST_TMPDIR/rules.before"
  assert_unchanged "$HOME/.config/opencode/opencode.json" "$BATS_TEST_TMPDIR/opencode.before"
  # Ordinary Pi cleanup already normalizes JSON and leaves an empty skills list.
  jq -e '.theme == "user-pi" and .skills == []' "$HOME/.pi/agent/settings.json"
}

@test "RST10: unknown identical command bytes never become install or uninstall authority" {
  local target="$PROJECT/.opencode/commands/adr.md" record="$PROJECT/.opencode/.mb-manifest.json"
  mkdir -p "$(dirname "$target")"
  cp "$REPO_ROOT/commands/adr.md" "$target"
  snapshot "$target" "$BATS_TEST_TMPDIR/identical.before"
  run bash "$REPO_ROOT/adapters/opencode.sh" install "$PROJECT"
  [ "$status" -ne 0 ]
  assert_unchanged "$target" "$BATS_TEST_TMPDIR/identical.before"
  jq -e --arg p "$target" '(.files | index($p)) == null and .file_sha256[$p] == null' "$record"
  run bash "$REPO_ROOT/adapters/opencode.sh" uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  assert_unchanged "$target" "$BATS_TEST_TMPDIR/identical.before"
}

@test "RST10: a missing committed hash is not repaired by rerecording unchanged bytes" {
  local target="$PROJECT/.opencode/commands/adr.md" record="$PROJECT/.opencode/.mb-manifest.json"
  run bash "$REPO_ROOT/adapters/opencode.sh" install "$PROJECT"
  [ "$status" -eq 0 ]
  snapshot "$target" "$BATS_TEST_TMPDIR/hashless.before"
  jq --arg p "$target" 'del(.file_sha256[$p])' "$record" > "$BATS_TEST_TMPDIR/hashless.json"
  mv "$BATS_TEST_TMPDIR/hashless.json" "$record"
  run bash "$REPO_ROOT/adapters/opencode.sh" install "$PROJECT"
  [ "$status" -ne 0 ]
  assert_unchanged "$target" "$BATS_TEST_TMPDIR/hashless.before"
  jq -e --arg p "$target" '.file_sha256[$p] == null' "$record"
  run bash "$REPO_ROOT/adapters/opencode.sh" uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  assert_unchanged "$target" "$BATS_TEST_TMPDIR/hashless.before"
}

@test "RST10: project owner-store I/O failure cannot be reported as a successful pair" {
  local fault="$BATS_TEST_TMPDIR/owner-fault" first_exit first_output recovery
  mkdir "$fault"
  printf 'User project instructions\n' > "$PROJECT/AGENTS.md"
  cat > "$fault/mv" <<'SH'
#!/bin/bash
for destination; do :; done
if [ "$destination" = "$FAULT_OWNERS" ]; then chmod 500 "$FAULT_PROJECT"; fi
exec /bin/mv "$@"
SH
  chmod +x "$fault/mv"
  run env PATH="$fault:$PATH" FAULT_PROJECT="$PROJECT" FAULT_OWNERS="$PROJECT/.mb-agents-owners.json" \
    bash "$REPO_ROOT/adapters/opencode.sh" install "$PROJECT"
  first_exit="$status"; first_output="$output"
  chmod u+w "$PROJECT"
  [ "$first_exit" -ne 0 ]
  refute_substring "$first_output" '[opencode-adapter] installed to'
  recovery="$(printf '%s\n' "$first_output" | sed -n 's/.*recovery: //p' | tail -1)"
  [ -d "$recovery" ]
  [ -n "$(find "$recovery" -type f -print -quit)" ]
  if [ -n "${S5_EVIDENCE_DIR:-}" ]; then
    tar -czf "$S5_EVIDENCE_DIR/owner-store-recovery.tar.gz" -C "$(dirname "$recovery")" "$(basename "$recovery")"
  fi
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
