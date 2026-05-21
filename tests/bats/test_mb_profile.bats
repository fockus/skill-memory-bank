#!/usr/bin/env bats
# Tests for scripts/mb-profile.sh — rules profile CLI.
#
# Sprint 3 / Stage 2 — TDD contract tests (written before implementation).
#
# Contract:
#   mb-profile show          — print resolved JSON profile
#   mb-profile init          — create user or project profile
#   mb-profile path          — print active profile paths
#   mb-profile validate <f>  — validate profile file; exit 2 on failure
#   mb-profile set <k=v>     — update one field (--scope required)
#
# Precedence: baseline → user → project → task (task only tightens).
# Immutable rules cannot be disabled by any profile operation.

# shellcheck disable=SC2317

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  PROFILE_CMD="$REPO_ROOT/scripts/mb-profile.sh"
  FIXTURES="$REPO_ROOT/tests/fixtures/rules-profiles"

  # Fresh sandbox — isolates HOME so global profiles never touch the real one.
  SANDBOX="$(mktemp -d)"
  export HOME="$SANDBOX/home"
  mkdir -p "$HOME"

  # Project dir without Memory Bank (default state).
  PROJECT="$SANDBOX/project"
  mkdir -p "$PROJECT"

  # Unset env vars that could carry state between tests.
  unset MB_PATH MB_AGENT MB_PROFILE_USER MB_PROFILE_PROJECT
}

teardown() {
  [ -n "${SANDBOX:-}" ] && [ -d "$SANDBOX" ] && rm -rf "$SANDBOX"
}

# ═══════════════════════════════════════════════════════════════
# Smoke
# ═══════════════════════════════════════════════════════════════

@test "profile: script exists and is executable" {
  [ -f "$PROFILE_CMD" ]
  [ -x "$PROFILE_CMD" ]
}

@test "profile: --help prints subcommands" {
  run bash "$PROFILE_CMD" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"show"* ]]
  [[ "$output" == *"init"* ]]
  [[ "$output" == *"validate"* ]]
}

# ═══════════════════════════════════════════════════════════════
# show — baseline fallback
# ═══════════════════════════════════════════════════════════════

@test "profile: show returns baseline when no profiles exist" {
  # No user profile, no project profile — must show baseline defaults.
  run bash "$PROFILE_CMD" show
  [ "$status" -eq 0 ]
  # Output is valid JSON containing immutable_rules.
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert 'immutable_rules' in d, 'missing immutable_rules'
assert 'no-placeholders' in d['immutable_rules'], 'missing no-placeholders'
assert 'sources' in d, 'missing sources'
"
}

# ═══════════════════════════════════════════════════════════════
# init — user scope
# ═══════════════════════════════════════════════════════════════

@test "profile: init user backend go writes global profile outside project" {
  # Must write to HOME-relative path, NOT inside PROJECT.
  run bash "$PROFILE_CMD" init \
    --scope=user \
    --role=backend \
    --stack=go \
    --architecture=clean \
    --delivery=tdd \
    --agent=claude-code
  [ "$status" -eq 0 ]

  # Written file must exist under HOME (global location).
  WRITTEN="$HOME/.claude/memory-bank/rules-profile.json"
  [ -f "$WRITTEN" ]

  # Must be valid JSON with correct fields.
  python3 -c "
import json
with open('$WRITTEN') as f:
    d = json.load(f)
assert d['role'] == 'backend'
assert d['stack'] == 'go'
assert d['scope'] == 'user'
"
  # Must NOT have created any file inside PROJECT.
  [ ! -f "$PROJECT/rules-profile.json" ]
  [ ! -d "$PROJECT/.memory-bank" ]
}

# ═══════════════════════════════════════════════════════════════
# init — project scope
# ═══════════════════════════════════════════════════════════════

@test "profile: init project frontend typescript writes <mb>/rules-profile.json" {
  # Create a Memory Bank so project scope is resolvable.
  MB_DIR="$PROJECT/.memory-bank"
  mkdir -p "$MB_DIR"

  run bash "$PROFILE_CMD" init \
    --scope=project \
    --role=frontend \
    --stack=typescript \
    --architecture=fsd \
    --delivery=sdd \
    --mb="$MB_DIR"
  [ "$status" -eq 0 ]

  WRITTEN="$MB_DIR/rules-profile.json"
  [ -f "$WRITTEN" ]

  python3 -c "
import json
with open('$WRITTEN') as f:
    d = json.load(f)
assert d['role'] == 'frontend'
assert d['stack'] == 'typescript'
assert d['architecture'] == 'fsd'
assert d['scope'] == 'project'
"
}

# ═══════════════════════════════════════════════════════════════
# Precedence — project overrides user for architecture
# ═══════════════════════════════════════════════════════════════

@test "profile: project overrides user for architecture" {
  USER_PROFILE="$HOME/.claude/memory-bank/rules-profile.json"
  mkdir -p "$(dirname "$USER_PROFILE")"
  python3 -c "
import json
d = {'schema_version':1,'scope':'user','role':'backend','stack':'go','architecture':'clean','delivery':'tdd','strictness':'warn'}
with open('$USER_PROFILE','w') as f:
    json.dump(d, f, indent=2)
"

  MB_DIR="$PROJECT/.memory-bank"
  mkdir -p "$MB_DIR"
  PROJECT_PROFILE="$MB_DIR/rules-profile.json"
  python3 -c "
import json
d = {'schema_version':1,'scope':'project','role':'backend','stack':'go','architecture':'microservices','delivery':'contract-first','strictness':'warn'}
with open('$PROJECT_PROFILE','w') as f:
    json.dump(d, f, indent=2)
"

  run bash "$PROFILE_CMD" show \
    --user="$USER_PROFILE" \
    --project="$PROJECT_PROFILE"
  [ "$status" -eq 0 ]

  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['architecture'] == 'microservices', f'expected microservices, got {d[\"architecture\"]}'
assert d['sources']['architecture'] == 'project', f'expected project source, got {d[\"sources\"][\"architecture\"]}'
"
}

# ═══════════════════════════════════════════════════════════════
# Immutable baseline cannot be disabled
# ═══════════════════════════════════════════════════════════════

@test "profile: immutable baseline cannot be disabled by profile set" {
  # Create a profile file to operate on.
  PROFILE_FILE="$SANDBOX/test-profile.json"
  python3 -c "
import json
d = {'schema_version':1,'scope':'user','role':'backend','stack':'go','architecture':'clean','delivery':'tdd','strictness':'warn'}
with open('$PROFILE_FILE','w') as f:
    json.dump(d, f, indent=2)
"

  # Attempt to disable an immutable rule must fail with non-zero exit.
  run bash "$PROFILE_CMD" set \
    --scope=user \
    --file="$PROFILE_FILE" \
    "baseline.no-placeholders=false"
  [ "$status" -ne 0 ]

  # The profile file must remain unchanged (immutable rule still not disabled).
  python3 -c "
import json
with open('$PROFILE_FILE') as f:
    d = json.load(f)
assert 'baseline' not in d or d.get('baseline', {}).get('no-placeholders', True) is not False, \
    'immutable rule was disabled — must never happen'
"
}

# ═══════════════════════════════════════════════════════════════
# Invalid stack exits 2
# ═══════════════════════════════════════════════════════════════

@test "profile: invalid stack exits 2" {
  run bash "$PROFILE_CMD" init \
    --scope=user \
    --role=backend \
    --stack=cobol \
    --architecture=clean \
    --delivery=tdd \
    --agent=claude-code
  [ "$status" -eq 2 ]
}

# ═══════════════════════════════════════════════════════════════
# validate — unknown field reporting
# ═══════════════════════════════════════════════════════════════

@test "profile: validate reports unknown field with line/key context" {
  BAD_PROFILE="$SANDBOX/bad-profile.json"
  python3 -c "
import json
d = {'schema_version':1,'scope':'user','role':'backend','stack':'go','architecture':'clean','delivery':'tdd','strictness':'warn','forbidden_key':'oops'}
with open('$BAD_PROFILE','w') as f:
    json.dump(d, f, indent=2)
"

  run bash "$PROFILE_CMD" validate "$BAD_PROFILE"
  [ "$status" -ne 0 ]
  # Error output must mention the unknown key.
  [[ "$output" == *"forbidden_key"* ]] || [[ "$stderr" == *"forbidden_key"* ]]
}

# ═══════════════════════════════════════════════════════════════
# No Memory Bank — project scope rejected with hint
# ═══════════════════════════════════════════════════════════════

@test "profile: no Memory Bank project rejects --scope=project with hint" {
  # Force a non-existent MB path so the script cannot resolve a project bank.
  # PROJECT has no .memory-bank directory — we point MB_PATH to a path that
  # does not exist to guarantee no local bank is found.
  export MB_PATH="$PROJECT/.memory-bank-nonexistent"

  run bash "$PROFILE_CMD" init \
    --scope=project \
    --role=backend \
    --stack=python \
    --architecture=clean \
    --delivery=tdd \
    --mb="$PROJECT/.memory-bank-nonexistent"
  [ "$status" -ne 0 ]
  # Error or hint output must suggest /mb init or --scope=user.
  [[ "$output" == *"init"* ]] || [[ "$output" == *"scope=user"* ]] || \
    [[ "$output" == *"--scope=user"* ]] || [[ "$output" == *"mb init"* ]]
}
