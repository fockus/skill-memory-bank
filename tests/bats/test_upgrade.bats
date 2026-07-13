#!/usr/bin/env bats
# Tests for scripts/mb-upgrade.sh — skill self-update pre-flight checks.
#
# Network-dependent behaviors (`fetch`, `pull`) are not tested — only
# pre-flight guards: git repo detection, dirty tree, missing VERSION.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-upgrade.sh"
  TMPDIR="$(mktemp -d)"

  [ -f "$SCRIPT" ] || skip "scripts/mb-upgrade.sh not implemented yet (TDD red)"
}

teardown() {
  [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ] && rm -rf "$TMPDIR"
}

# ═══ Pre-flight: not a git repo ═══

@test "upgrade: fails when MB_SKILL_DIR is not a git repo" {
  mkdir -p "$TMPDIR/fake-skill"
  MB_SKILL_DIR="$TMPDIR/fake-skill" run bash "$SCRIPT" --check
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"git"* || "$output$stderr" == *"repository"* ]]
}

@test "upgrade: fails when MB_SKILL_DIR does not exist" {
  MB_SKILL_DIR="$TMPDIR/nonexistent" run bash "$SCRIPT" --check
  [ "$status" -ne 0 ]
}

# ═══ Pre-flight: dirty working tree ═══

@test "upgrade: fails when working tree has unstaged changes" {
  cd "$TMPDIR"
  mkdir -p skill
  cd skill
  git init -q
  git config user.email "test@test"
  git config user.name "Test"
  echo "v1" > VERSION
  git add VERSION
  git commit -q -m "init"
  # Make dirty
  echo "dirty" >> VERSION

  MB_SKILL_DIR="$TMPDIR/skill" run bash "$SCRIPT" --check
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"dirty"* || "$output$stderr" == *"local changes"* || "$output$stderr" == *"uncommitted"* ]]
}

@test "upgrade: fails when working tree has staged but uncommitted changes" {
  cd "$TMPDIR"
  mkdir -p skill
  cd skill
  git init -q
  git config user.email "test@test"
  git config user.name "Test"
  echo "v1" > VERSION
  git add VERSION
  git commit -q -m "init"
  echo "staged" > new.txt
  git add new.txt  # staged but not committed

  MB_SKILL_DIR="$TMPDIR/skill" run bash "$SCRIPT" --check
  [ "$status" -ne 0 ]
}

# ═══ Version reading ═══

@test "upgrade: reads VERSION file correctly" {
  cd "$TMPDIR"
  mkdir -p skill
  cd skill
  git init -q
  git config user.email "test@test"
  git config user.name "Test"
  echo "1.2.3" > VERSION
  git add VERSION
  git commit -q -m "init"

  # `--check` without a remote means `fetch` fails, but VERSION must still be read
  MB_SKILL_DIR="$TMPDIR/skill" run bash "$SCRIPT" --check
  # Any exit code is acceptable, but output must contain 1.2.3
  [[ "$output" == *"1.2.3"* ]]
}

@test "upgrade: handles missing VERSION file gracefully" {
  cd "$TMPDIR"
  mkdir -p skill
  cd skill
  git init -q
  git config user.email "test@test"
  git config user.name "Test"
  echo "file" > README.md
  git add README.md
  git commit -q -m "init"

  MB_SKILL_DIR="$TMPDIR/skill" run bash "$SCRIPT" --check
  # It must not fail because VERSION is missing — output should contain "unknown"
  [[ "$output" == *"unknown"* ]]
}

# ═══ A21 (CDX-I10): persist + reapply install options across upgrade ═══
#
# `mb-upgrade.sh --force` used to re-run install.sh bare, silently resetting
# the locale to en and dropping any project --clients the user had picked.
# install.sh now persists {language, clients_requested, project_root} into its
# own manifest (scripts/_lib.sh::mb_resolve_manifest_path) — mb-upgrade.sh
# reads that manifest and reapplies the same options non-interactively.

_a21_setup_upgradeable_skill() {
  cd "$TMPDIR"
  mkdir -p skill
  cd skill
  git init -q
  git config user.email "test@test"
  git config user.name "Test"
  echo "1.0.0" > VERSION
  git add VERSION
  git commit -q -m "init"

  # Stub install.sh: records the argv it was invoked with instead of
  # installing anything real (this suite never runs the real installer).
  cat > install.sh <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$(dirname "$0")/.install-args-recorded"
exit 0
EOF
  chmod +x install.sh
  git add install.sh
  git commit -q -m "add install stub"

  MB_UPGRADE_TEST_BRANCH="$(git rev-parse --abbrev-ref HEAD)"

  # Bare "origin" seeded from the current state (works regardless of the
  # default branch name being main/master).
  git clone -q --bare . "$TMPDIR/origin.git"
  git remote add origin "$TMPDIR/origin.git"

  # Advance "origin" by one commit via a second clone so `behind` > 0 and the
  # apply path (git pull + re-run install.sh) actually executes.
  (
    cd "$TMPDIR"
    git clone -q "$TMPDIR/origin.git" origin-work
    cd origin-work
    git config user.email "test@test"
    git config user.name "Test"
    echo "1.0.1" > VERSION
    git add VERSION
    git commit -q -m "bump version"
    git push -q origin "HEAD:$MB_UPGRADE_TEST_BRANCH"
  )
}

@test "upgrade: --force reapplies persisted language + clients non-interactively (A21)" {
  _a21_setup_upgradeable_skill

  # Simulate a previous install: manifest with persisted options (A21 adds
  # these keys to install.sh's own flush_manifest payload).
  cat > "$TMPDIR/skill/.installed-manifest.json" <<'EOF'
{
  "schema_version": 1,
  "language": "ru",
  "clients_requested": "codex",
  "project_root": "/tmp/some-persisted-project",
  "files": [],
  "backups": [],
  "clients": ["codex"]
}
EOF

  MB_SKILL_DIR="$TMPDIR/skill" run bash "$SCRIPT" --force
  [ "$status" -eq 0 ]

  recorded="$TMPDIR/skill/.install-args-recorded"
  [ -f "$recorded" ]
  run cat "$recorded"
  [[ "$output" == *"--non-interactive"* ]]
  [[ "$output" == *"--language"* ]]
  [[ "$output" == *"ru"* ]]
  [[ "$output" == *"--clients"* ]]
  [[ "$output" == *"codex"* ]]
  [[ "$output" == *"--project-root"* ]]
  [[ "$output" == *"/tmp/some-persisted-project"* ]]
}

@test "upgrade: pre-A21 manifest (no persisted options) falls back to defaults with a warning" {
  _a21_setup_upgradeable_skill

  cat > "$TMPDIR/skill/.installed-manifest.json" <<'EOF'
{
  "schema_version": 1,
  "files": [],
  "backups": [],
  "clients": []
}
EOF

  MB_SKILL_DIR="$TMPDIR/skill" run bash "$SCRIPT" --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"no persisted install options"* ]]

  recorded="$TMPDIR/skill/.install-args-recorded"
  [ -f "$recorded" ]
  run cat "$recorded"
  [[ "$output" == *"--non-interactive"* ]]
  [[ "$output" != *"--language"* ]]
  [[ "$output" != *"--clients"* ]]
}

@test "upgrade: explicit --language/--clients flags override the persisted manifest (A21)" {
  _a21_setup_upgradeable_skill

  cat > "$TMPDIR/skill/.installed-manifest.json" <<'EOF'
{
  "schema_version": 1,
  "language": "ru",
  "clients_requested": "codex",
  "project_root": "/tmp/some-persisted-project",
  "files": [],
  "backups": [],
  "clients": ["codex"]
}
EOF

  MB_SKILL_DIR="$TMPDIR/skill" run bash "$SCRIPT" --force --language en --clients cursor
  [ "$status" -eq 0 ]

  recorded="$TMPDIR/skill/.install-args-recorded"
  [ -f "$recorded" ]
  run cat "$recorded"
  [[ "$output" == *"--language"* ]]
  [[ "$output" == *"en"* ]]
  [[ "$output" == *"--clients"* ]]
  [[ "$output" == *"cursor"* ]]
  [[ "$output" != *"ru"* ]]
}

# ═══ Regression: install-flavor detection now delegates to _lib.sh
# (scripts/_lib.sh::mb_install_flavor / mb_upgrade_command) — these pin the
# exact user-facing output + exit codes so that refactor cannot silently
# change what users see. ═══

@test "upgrade: pipx flavor — prints the pinned info+hint lines and exits 0" {
  mkdir -p "$TMPDIR/home/.local/pipx/venvs/memory-bank-skill/share/memory-bank-skill"
  MB_SKILL_DIR="$TMPDIR/home/.local/pipx/venvs/memory-bank-skill/share/memory-bank-skill" \
    run bash "$SCRIPT" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"[info] memory-bank-skill is installed via pipx (bundle:"* ]]
  [[ "$output" == *"[info] Git-based auto-upgrade is not applicable for pipx installs."* ]]
  [[ "$output" == *"To update, run:"* ]]
  [[ "$output" == *"    pipx upgrade memory-bank-skill"* ]]
  [[ "$output" == *"Or force-reinstall from GitHub (for release candidates):"* ]]
  [[ "$output" == *"    pipx install --force 'git+https://github.com/fockus/skill-memory-bank.git'"* ]]
}

@test "upgrade: pip flavor (site-packages) — prints the pinned info+hint lines and exits 0" {
  mkdir -p "$TMPDIR/home/lib/python3.11/site-packages/memory_bank_skill/share/memory-bank-skill"
  MB_SKILL_DIR="$TMPDIR/home/lib/python3.11/site-packages/memory_bank_skill/share/memory-bank-skill" \
    run bash "$SCRIPT" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"[info] memory-bank-skill appears to be a pip install (bundle:"* ]]
  [[ "$output" == *"To update, run:"* ]]
  [[ "$output" == *"    pip install --upgrade memory-bank-skill"* ]]
}

@test "upgrade: pip flavor (dist-packages) — prints the pinned info+hint lines and exits 0" {
  mkdir -p "$TMPDIR/usr/lib/python3/dist-packages/memory_bank_skill/share/memory-bank-skill"
  MB_SKILL_DIR="$TMPDIR/usr/lib/python3/dist-packages/memory_bank_skill/share/memory-bank-skill" \
    run bash "$SCRIPT" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"[info] memory-bank-skill appears to be a pip install (bundle:"* ]]
  [[ "$output" == *"    pip install --upgrade memory-bank-skill"* ]]
}

@test "upgrade: brew flavor (NEW) — prints an info+hint block and exits 0" {
  mkdir -p "$TMPDIR/opt/homebrew/Cellar/memory-bank/1.0.0/share/memory-bank-skill"
  MB_SKILL_DIR="$TMPDIR/opt/homebrew/Cellar/memory-bank/1.0.0/share/memory-bank-skill" \
    run bash "$SCRIPT" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"[info] memory-bank-skill is installed via Homebrew (bundle:"* ]]
  [[ "$output" == *"To update, run:"* ]]
  [[ "$output" == *"    brew upgrade memory-bank"* ]]
}

@test "upgrade: unknown flavor — prints the pinned error+reinstall-hint lines and exits 1" {
  mkdir -p "$TMPDIR/somewhere/random/not-a-known-install"
  MB_SKILL_DIR="$TMPDIR/somewhere/random/not-a-known-install" run bash "$SCRIPT" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"[error] $TMPDIR/somewhere/random/not-a-known-install is not a git repository and not a known package install"* ]]
  [[ "$output" == *"[hint] Reinstall options:"* ]]
  [[ "$output" == *"    git clone:  rm -rf $TMPDIR/somewhere/random/not-a-known-install && git clone https://github.com/fockus/skill-memory-bank.git $TMPDIR/somewhere/random/not-a-known-install"* ]]
  [[ "$output" == *"    pipx:       pipx install memory-bank-skill"* ]]
  [[ "$output" == *"    pip:        pip install memory-bank-skill"* ]]
}

@test "upgrade: no second copy of the flavor pattern-matching remains in mb-upgrade.sh" {
  run grep -nE 'pipx/venvs/memory-bank-skill|site-packages\*\)|dist-packages\*\)|/Cellar/' "$SCRIPT"
  [ "$status" -ne 0 ]
}

@test "upgrade: drops a persisted client no longer supported instead of failing the whole upgrade" {
  _a21_setup_upgradeable_skill

  cat > "$TMPDIR/skill/.installed-manifest.json" <<'EOF'
{
  "schema_version": 1,
  "language": "en",
  "clients_requested": "codex,retired-client",
  "project_root": "",
  "files": [],
  "backups": [],
  "clients": ["codex"]
}
EOF

  MB_SKILL_DIR="$TMPDIR/skill" run bash "$SCRIPT" --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"retired-client"* ]]

  recorded="$TMPDIR/skill/.install-args-recorded"
  [ -f "$recorded" ]
  run cat "$recorded"
  [[ "$output" == *"codex"* ]]
  [[ "$output" != *"retired-client"* ]]
}
