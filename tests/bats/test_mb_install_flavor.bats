#!/usr/bin/env bats
# Tests for scripts/_lib.sh::mb_install_flavor / mb_upgrade_command.
#
# mb-upgrade.sh (:119-168 historically) detected the install flavor inline.
# Stage 2's mb-version-check.sh needs the exact same answer, so the
# detection lives here once (DRY) — this suite pins the contract both
# callers rely on.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="$REPO_ROOT/scripts/_lib.sh"
  TMPDIR="$(mktemp -d)"

  [ -f "$LIB" ] || skip "scripts/_lib.sh not implemented yet (TDD red phase)"
  # shellcheck source=/dev/null
  source "$LIB"
}

teardown() {
  [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ] && rm -rf "$TMPDIR"
}

# ═══ mb_install_flavor: git ═══

@test "mb_install_flavor: dir with .git → git" {
  mkdir -p "$TMPDIR/skill/.git"
  run mb_install_flavor "$TMPDIR/skill"
  [ "$status" -eq 0 ]
  [ "$output" = "git" ]
}

# ═══ mb_install_flavor: pipx ═══

@test "mb_install_flavor: path under pipx/venvs/memory-bank-skill → pipx" {
  mkdir -p "$TMPDIR/home/.local/pipx/venvs/memory-bank-skill/share/memory-bank-skill"
  run mb_install_flavor "$TMPDIR/home/.local/pipx/venvs/memory-bank-skill/share/memory-bank-skill"
  [ "$status" -eq 0 ]
  [ "$output" = "pipx" ]
}

# ═══ mb_install_flavor: pip ═══

@test "mb_install_flavor: path under site-packages → pip" {
  mkdir -p "$TMPDIR/home/lib/python3.11/site-packages/memory_bank_skill/share/memory-bank-skill"
  run mb_install_flavor "$TMPDIR/home/lib/python3.11/site-packages/memory_bank_skill/share/memory-bank-skill"
  [ "$status" -eq 0 ]
  [ "$output" = "pip" ]
}

@test "mb_install_flavor: path under dist-packages → pip" {
  mkdir -p "$TMPDIR/usr/lib/python3/dist-packages/memory_bank_skill/share/memory-bank-skill"
  run mb_install_flavor "$TMPDIR/usr/lib/python3/dist-packages/memory_bank_skill/share/memory-bank-skill"
  [ "$status" -eq 0 ]
  [ "$output" = "pip" ]
}

@test "mb_install_flavor: resolved path IS the site-packages segment itself (no trailing component) → pip" {
  mkdir -p "$TMPDIR/home/lib/python3.11/site-packages"
  run mb_install_flavor "$TMPDIR/home/lib/python3.11/site-packages"
  [ "$status" -eq 0 ]
  [ "$output" = "pip" ]
}

@test "mb_install_flavor: resolved path IS the dist-packages segment itself (no trailing component) → pip" {
  mkdir -p "$TMPDIR/usr/lib/python3/dist-packages"
  run mb_install_flavor "$TMPDIR/usr/lib/python3/dist-packages"
  [ "$status" -eq 0 ]
  [ "$output" = "pip" ]
}

# ═══ mb_install_flavor: bug repro — a directory NAME that merely contains the
# keyword must NOT be misclassified (path-segment anchoring, not substring). ═══

@test "mb_install_flavor: a directory whose name merely CONTAINS 'site-packages' is NOT pip" {
  mkdir -p "$TMPDIR/dev/site-packages-playground/mb"
  run mb_install_flavor "$TMPDIR/dev/site-packages-playground/mb"
  [ "$status" -eq 0 ]
  [ "$output" = "unknown" ]
}

@test "mb_install_flavor: a directory whose name merely CONTAINS 'dist-packages' is NOT pip" {
  mkdir -p "$TMPDIR/dev/my-dist-packages-fork/mb"
  run mb_install_flavor "$TMPDIR/dev/my-dist-packages-fork/mb"
  [ "$status" -eq 0 ]
  [ "$output" = "unknown" ]
}

@test "mb_install_flavor: a directory whose name merely CONTAINS 'pipx' (not the real venv layout) is NOT pipx" {
  mkdir -p "$TMPDIR/dev/mypipx-tools/venvs/memory-bank-skill/mb"
  run mb_install_flavor "$TMPDIR/dev/mypipx-tools/venvs/memory-bank-skill/mb"
  [ "$status" -eq 0 ]
  [ "$output" = "unknown" ]
}

# ═══ mb_install_flavor: check ORDER — pipx venvs contain a site-packages/
# segment too, so pipx must still win even when both patterns would match. ═══

@test "mb_install_flavor: pipx venv path that ALSO has a site-packages/ segment still classifies as pipx" {
  mkdir -p "$TMPDIR/home/.local/pipx/venvs/memory-bank-skill/lib/python3.11/site-packages/memory_bank_skill"
  run mb_install_flavor "$TMPDIR/home/.local/pipx/venvs/memory-bank-skill/lib/python3.11/site-packages/memory_bank_skill"
  [ "$status" -eq 0 ]
  [ "$output" = "pipx" ]
}

# ═══ mb_install_flavor: brew (NEW) ═══

@test "mb_install_flavor: path under a Cellar prefix → brew" {
  mkdir -p "$TMPDIR/opt/homebrew/Cellar/memory-bank/1.0.0/share/memory-bank-skill"
  run mb_install_flavor "$TMPDIR/opt/homebrew/Cellar/memory-bank/1.0.0/share/memory-bank-skill"
  [ "$status" -eq 0 ]
  [ "$output" = "brew" ]
}

@test "mb_install_flavor: path under \$(brew --prefix) (no /Cellar/ segment) → brew" {
  mkdir -p "$TMPDIR/bin"
  cat > "$TMPDIR/bin/brew" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "--prefix" ]; then
  printf '%s\n' "$TMPDIR/fake-homebrew"
  exit 0
fi
exit 1
EOF
  chmod +x "$TMPDIR/bin/brew"
  mkdir -p "$TMPDIR/fake-homebrew/opt/memory-bank/share/memory-bank-skill"

  PATH="$TMPDIR/bin:$PATH" run mb_install_flavor "$TMPDIR/fake-homebrew/opt/memory-bank/share/memory-bank-skill"
  [ "$status" -eq 0 ]
  [ "$output" = "brew" ]
}

# ═══ mb_install_flavor: unknown ═══

@test "mb_install_flavor: unrecognized path with no brew on PATH → unknown" {
  mkdir -p "$TMPDIR/somewhere/random/memory-bank-skill"
  PATH="/usr/bin:/bin" run mb_install_flavor "$TMPDIR/somewhere/random/memory-bank-skill"
  [ "$status" -eq 0 ]
  [ "$output" = "unknown" ]
}

@test "mb_install_flavor: nonexistent dir → unknown, exit 0 (never fails)" {
  run mb_install_flavor "$TMPDIR/does/not/exist"
  [ "$status" -eq 0 ]
  [ "$output" = "unknown" ]
}

@test "mb_install_flavor: empty argument → unknown, exit 0 (never fails)" {
  run mb_install_flavor ""
  [ "$status" -eq 0 ]
  [ "$output" = "unknown" ]
}

# ═══ mb_install_flavor: symlinked alias resolves to the real flavor ═══

@test "mb_install_flavor: symlinked alias to a pipx bundle still resolves to pipx" {
  mkdir -p "$TMPDIR/home/.local/pipx/venvs/memory-bank-skill/share/memory-bank-skill"
  ln -s "$TMPDIR/home/.local/pipx/venvs/memory-bank-skill/share/memory-bank-skill" "$TMPDIR/alias-skill"

  run mb_install_flavor "$TMPDIR/alias-skill"
  [ "$status" -eq 0 ]
  [ "$output" = "pipx" ]
}

@test "mb_install_flavor: symlinked alias to a git checkout still resolves to git" {
  mkdir -p "$TMPDIR/real-skill/.git"
  ln -s "$TMPDIR/real-skill" "$TMPDIR/alias-skill"

  run mb_install_flavor "$TMPDIR/alias-skill"
  [ "$status" -eq 0 ]
  [ "$output" = "git" ]
}

# ═══ mb_upgrade_command ═══

@test "mb_upgrade_command: git → the mb-upgrade.sh git-pull + re-install path" {
  run mb_upgrade_command git
  [ "$status" -eq 0 ]
  [[ "$output" == *"mb-upgrade.sh"* ]]
}

# ═══ mb_upgrade_command: git flavor must be cwd-independent when the bundle
# location is known (bug repro — a SessionStart hook runs from an arbitrary
# project directory, not the skill bundle root). ═══

@test "mb_upgrade_command: git with an install_dir → an absolute, copy-pasteable command" {
  run mb_upgrade_command git "/opt/skills/skill-memory-bank"
  [ "$status" -eq 0 ]
  [ "$output" = "bash /opt/skills/skill-memory-bank/scripts/mb-upgrade.sh --force" ]
}

@test "mb_upgrade_command: git with an install_dir runs correctly from an unrelated cwd" {
  mkdir -p "$TMPDIR/bundle/scripts" "$TMPDIR/elsewhere"
  cat > "$TMPDIR/bundle/scripts/mb-upgrade.sh" <<'EOF'
#!/usr/bin/env bash
echo "ran-from-$(pwd)"
EOF
  chmod +x "$TMPDIR/bundle/scripts/mb-upgrade.sh"

  run mb_upgrade_command git "$TMPDIR/bundle"
  [ "$status" -eq 0 ]
  cmd="$output"

  cd "$TMPDIR/elsewhere"
  run bash -c "$cmd"
  [ "$status" -eq 0 ]
  [[ "$output" == "ran-from-"* ]]
}

@test "mb_upgrade_command: git with install_dir having a trailing slash does not double the slash" {
  run mb_upgrade_command git "/opt/skills/skill-memory-bank/"
  [ "$status" -eq 0 ]
  [ "$output" = "bash /opt/skills/skill-memory-bank/scripts/mb-upgrade.sh --force" ]
}

@test "mb_upgrade_command: git with install_dir omitted falls back to the relative form (deliberate, tested branch)" {
  run mb_upgrade_command git
  [ "$status" -eq 0 ]
  [ "$output" = "scripts/mb-upgrade.sh --force" ]
}

@test "mb_upgrade_command: git with an empty install_dir falls back to the relative form, never a broken /scripts path" {
  run mb_upgrade_command git ""
  [ "$status" -eq 0 ]
  [ "$output" = "scripts/mb-upgrade.sh --force" ]
  [[ "$output" != "bash /scripts/mb-upgrade.sh"* ]]
}

@test "mb_upgrade_command: pipx → pipx upgrade memory-bank-skill" {
  run mb_upgrade_command pipx
  [ "$status" -eq 0 ]
  [ "$output" = "pipx upgrade memory-bank-skill" ]
}

@test "mb_upgrade_command: pip → pip install --upgrade memory-bank-skill" {
  run mb_upgrade_command pip
  [ "$status" -eq 0 ]
  [ "$output" = "pip install --upgrade memory-bank-skill" ]
}

@test "mb_upgrade_command: brew → brew upgrade memory-bank" {
  run mb_upgrade_command brew
  [ "$status" -eq 0 ]
  [ "$output" = "brew upgrade memory-bank" ]
}

@test "mb_upgrade_command: unknown → a loud actionable hint, never empty" {
  run mb_upgrade_command unknown
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [[ "$output" == *"git"* ]]
  [[ "$output" == *"pipx"* || "$output" == *"pip"* ]]
}

@test "mb_upgrade_command: unrecognized flavor argument still exits 0 with a non-empty hint" {
  run mb_upgrade_command something-made-up
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}
