#!/usr/bin/env bats
# Tests for the `/mb drive` command wrapper and the AGENTS.md drive line
# (drive-loop REQ-DR-001/003/031; drive-autopilot REQ-019, REQ-046, REQ-050, REQ-051).
#
# Contract under test:
#   1. `commands/drive.md` wraps `scripts/mb-drive.sh`: one `<!-- mb-drive:start -->`
#      fence calls `mb-drive.sh start`, then the doc runs the "call `next` ->
#      execute -> `returned` -> repeat" loop until a `stop_*` action.
#   2. Start REFUSES without a resolvable goal — exit 1 plus a concrete fix-hint,
#      reusing the `mb-goal-validate.sh` failure path; it never silently starts.
#   3. The AGENTS.md block rendered by `adapters/_lib_agents_md.sh` carries the
#      drive line: start, next, returned, stop recording, never self-certify done.
#
# The refuse-path assertions EXTRACT the doc's start fence and execute it
# against an isolated temp bank, so the documented behaviour is the tested one.
#
# Name convention: every @test starts with `drive_cmd: ` (Eval red anchor).

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  DOC="$REPO_ROOT/commands/drive.md"
  LIB="$REPO_ROOT/adapters/_lib_agents_md.sh"
  ROUTER_DOC="$REPO_ROOT/commands/mb.md"
  BANK="$BATS_TEST_TMPDIR/bank"
  PROJECT="$BATS_TEST_TMPDIR/project"
  mkdir -p "$BANK" "$PROJECT"
  # `progress_source: checklist` resolves against the RESOLVED bank, not the
  # .memory-bank of the current directory.
  printf '# Checklist\n\n- ⬜ placeholder item\n' > "$BANK/checklist.md"
}

# Extract the executable start snippet documented in commands/drive.md.
extract_start() {
  awk '
    /<!-- mb-drive:start -->/ { want = 1; next }
    want && /^```bash$/       { inside = 1; want = 0; next }
    inside && /^```$/         { exit }
    inside                    { print }
  ' "$DOC"
}

# Run the documented start fence against an isolated bank (stdout only in $output).
run_start() {
  local snippet
  snippet="$(extract_start)"
  [ -n "$snippet" ] || {
    echo "no <!-- mb-drive:start --> bash block found in $DOC" >&2
    return 1
  }
  run env -u MB_PATH -u MB_SKILLS_ROOT -u CLAUDE_CODE_SESSION_ID SKILL_DIR="$REPO_ROOT" BANK="$BANK" \
    bash -c "$snippet"
}

write_valid_goal() {
  cat > "${1:-$BANK/goal.md}" <<'EOF'
---
id: G-900
status: active
mode: static
progress_source: checklist
progress_target: 100
---

# Goal

## Description

Drive refuse-path fixture.

## Acceptance criteria

- [ ] first acceptance item
- [x] second acceptance item
EOF
}

run_file_field() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' \
    "$BANK/.drive/$1.json" "$2"
}

# ---- commands/drive.md: shape + loop contract --------------------------------

@test "drive_cmd: commands/drive.md exists with command frontmatter" {
  [ -f "$DOC" ]
  grep -qE '^description:' "$DOC"
  grep -qE '^allowed-tools:' "$DOC"
}

@test "drive_cmd: doc wraps mb-drive.sh and documents the next -> execute -> returned loop" {
  local body
  body="$(cat "$DOC")"
  [[ "$body" == *"mb-drive.sh\" next"* ]] || false
  [[ "$body" == *"mb-drive.sh\" returned"* ]] || false
  [[ "$body" == *"stop_success"* ]] || false
  [[ "$body" == *"stop_human"* ]] || false
  [[ "$body" == *"stop_budget"* ]] || false
  [[ "$body" == *"mb-drive-stop.sh\" record"* ]] || false
}

@test "drive_cmd: exactly one start fence, and it calls mb-drive.sh start" {
  [ "$(grep -c '<!-- mb-drive:' "$DOC")" -eq 1 ]
  [[ "$(extract_start)" == *'mb-drive.sh" start'* ]] || false
}

@test "drive_cmd: doc references only shipped scripts (no vapor)" {
  local refs p
  refs="$(grep -oE '(scripts|hooks|adapters|templates)/[A-Za-z0-9._-]+\.(sh|py|md|yaml)' "$DOC" | sort -u)"
  [ -n "$refs" ]
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    if [ ! -f "$REPO_ROOT/$p" ]; then
      echo "VAPOR: commands/drive.md references non-shipped file: $p" >&2
      return 1
    fi
  done <<< "$refs"
}

# ---- start: refuse without a resolvable goal ---------------------------------

@test "drive_cmd: start refuses and scaffolds the template when goal.md is absent" {
  run_start
  [ "$status" -eq 1 ]
  [ -f "$BANK/goal.md" ]
  [ ! -d "$BANK/.drive" ]
}

@test "drive_cmd: start refuses an unresolvable goal through the validator" {
  cat > "$BANK/goal.md" <<'EOF'
---
id: G-901
status: active
progress_source: spec-tasks
---

# Goal

No acceptance criteria section here.
EOF
  run --separate-stderr env -u MB_PATH SKILL_DIR="$REPO_ROOT" BANK="$BANK" bash -c "$(extract_start)"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"cceptance"* ]] || false
}

@test "drive_cmd: a scaffolded but untouched goal is refused again" {
  run_start
  [ "$status" -eq 1 ]
  run --separate-stderr env -u MB_PATH SKILL_DIR="$REPO_ROOT" BANK="$BANK" bash -c "$(extract_start)"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"placeholder"* ]] || [[ "$stderr" == *"template"* ]]
}

@test "drive_cmd: start on a valid goal opens a planning run file and keeps goal.md" {
  write_valid_goal
  local before
  before="$(cat "$BANK/goal.md")"
  run_start
  [ "$status" -eq 0 ]
  local rid="${output##*run_id=}"
  [ -n "$rid" ]
  [ "$(run_file_field "$rid" phase)" = planning ]
  [ "$(cat "$BANK/goal.md")" = "$before" ]
}

@test "drive_cmd: --budget lands in the run's own budget slot" {
  write_valid_goal
  BUDGET=1000 run_start
  [ "$status" -eq 0 ]
  local rid="${output##*run_id=}"
  run python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["total"])' "$BANK/.work-budget/$rid.json"
  [ "$output" = "1000" ]
  [ ! -f "$BANK/.work-budget.json" ]
}

@test "drive_cmd: --serial is recorded in the run file" {
  write_valid_goal
  SERIAL=1 run_start
  [ "$status" -eq 0 ]
  local rid="${output##*run_id=}"
  [ "$(run_file_field "$rid" parallel_reason)" = serial-flag ]
}

@test "drive_cmd: a second start on the same goal names the live run" {
  write_valid_goal
  run_start
  [ "$status" -eq 0 ]
  local rid="${output##*run_id=}"
  run_start
  [ "$status" -eq 1 ]
  [[ "$output" != *"run_id="* ]] || false
  run bash "$REPO_ROOT/scripts/mb-drive.sh" start --bank "$BANK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"$rid"* ]] || false
}

@test "drive_cmd: --goal drives a second goal file beside the first" {
  write_valid_goal
  mkdir -p "$BANK/goals"
  write_valid_goal "$BANK/goals/second.md"
  run_start
  [ "$status" -eq 0 ]
  GOAL=goals/second.md run_start
  [ "$status" -eq 0 ]
  [ "$(find "$BANK/.drive" -name '*.json' | wc -l | tr -d ' ')" -eq 2 ]
}

@test "drive_cmd: start works against a bank at a non-standard path" {
  local alt="$BATS_TEST_TMPDIR/some/deep/custom-bank"
  mkdir -p "$alt"
  printf '# Checklist\n\n- ⬜ item\n' > "$alt/checklist.md"
  write_valid_goal "$alt/goal.md"
  run env -u MB_PATH SKILL_DIR="$REPO_ROOT" BANK="$alt" bash -c "cd '$BATS_TEST_TMPDIR' && $(extract_start)"
  [ "$status" -eq 0 ]
  [ -d "$alt/.drive" ]
}

@test "drive_cmd: a legacy run file without a phase is not a live run" {
  write_valid_goal
  mkdir -p "$BANK/.drive"
  printf '{"run_id":"old","status":"driving","stop_reason":""}\n' > "$BANK/.drive/old.json"
  run_start
  [ "$status" -eq 0 ]
  run bash "$REPO_ROOT/scripts/mb-drive.sh" resume --bank "$BANK"
  [ "$status" -eq 0 ]
  [[ "$output" != *"run_id=old "* ]] || false
}

# ---- the AGENTS.md drive line ------------------------------------------------

install_block() {
  local skill="$BATS_TEST_TMPDIR/skill"
  mkdir -p "$skill/rules"
  cat > "$skill/rules/RULES.md" <<'EOF'
# Global Rules

1. **Language**: English — responses and code comments. Technical terms may remain in English.
EOF
  echo "9.9.9" > "$skill/VERSION"
  # shellcheck source=/dev/null
  source "$LIB"
  agents_md_install "$PROJECT" "codex" "$skill" >/dev/null
}

@test "drive_cmd: AGENTS.md block carries the drive loop (start, next, returned, stops)" {
  command -v jq >/dev/null || skip "jq required"
  install_block
  local body
  body="$(cat "$PROJECT/AGENTS.md")"
  [[ "$body" == *"mb-drive.sh start"* ]] || false
  [[ "$body" == *"mb-drive.sh next"* ]] || false
  [[ "$body" == *"returned"* ]] || false
  [[ "$body" == *"/mb work"* ]] || false
  [[ "$body" == *"/mb team"* ]] || false
  [[ "$body" == *"stop_success"* ]] || false
  [[ "$body" == *"stop_human"* ]] || false
  [[ "$body" == *"stop_budget"* ]] || false
  [[ "$body" == *"mb-drive-stop.sh record"* ]] || false
}

@test "drive_cmd: AGENTS.md block forbids self-certified done" {
  command -v jq >/dev/null || skip "jq required"
  install_block
  local body
  body="$(cat "$PROJECT/AGENTS.md")"
  [[ "$body" == *"self-certif"* ]] || false
  [[ "$body" == *"mb-flow-verify.sh"* ]] || false
  [[ "$body" == *"mb-goal-acceptance.sh"* ]] || false
  [[ "$body" == *"mb-goal-validate.sh"* ]] || false
  [[ "$body" == *"refus"* ]] || false
}

@test "drive_cmd: AGENTS.md block references only shipped scripts (no vapor)" {
  command -v jq >/dev/null || skip "jq required"
  install_block
  local section refs p
  section="$(awk '/memory-bank:start/{f=1} f{print} /memory-bank:end/{f=0}' "$PROJECT/AGENTS.md")"
  refs="$(printf '%s\n' "$section" | grep -oE '(scripts|hooks|adapters)/[A-Za-z0-9._-]+\.(sh|py)' | sort -u)"
  [ -n "$refs" ]
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    if [ ! -f "$REPO_ROOT/$p" ]; then
      echo "VAPOR: AGENTS.md block references non-shipped script: $p" >&2
      return 1
    fi
  done <<< "$refs"
}

@test "drive_cmd: _agents_md_section renders byte-identically on repeat" {
  local skill="$BATS_TEST_TMPDIR/skill"
  mkdir -p "$skill/rules"
  echo "9.9.9" > "$skill/VERSION"
  # shellcheck source=/dev/null
  source "$LIB"
  local a b
  a="$(_agents_md_section "$skill" 0)"
  b="$(_agents_md_section "$skill" 0)"
  [ "$a" = "$b" ]
}

@test "drive_cmd: repeated install keeps AGENTS.md byte-identical (no blank-line drift)" {
  command -v jq >/dev/null || skip "jq required"
  install_block
  cp "$PROJECT/AGENTS.md" "$BATS_TEST_TMPDIR/after1"
  install_block
  cp "$PROJECT/AGENTS.md" "$BATS_TEST_TMPDIR/after2"
  install_block
  run diff "$BATS_TEST_TMPDIR/after1" "$BATS_TEST_TMPDIR/after2"
  [ "$status" -eq 0 ]
  run diff "$BATS_TEST_TMPDIR/after2" "$PROJECT/AGENTS.md"
  [ "$status" -eq 0 ]
  [ "$(grep -c 'memory-bank:start' "$PROJECT/AGENTS.md")" -eq 1 ]
}

@test "drive_cmd: repeated install over user content reaches a fixed point and preserves it" {
  command -v jq >/dev/null || skip "jq required"
  # Trailing blank run is deliberate: an old replace-branch prepended one more
  # blank line per re-install, so the file grew without bound.
  printf '# User doc\n\npara one\n\npara two\n\n\n' > "$PROJECT/AGENTS.md"

  install_block
  install_block
  cp "$PROJECT/AGENTS.md" "$BATS_TEST_TMPDIR/u2"
  install_block
  cp "$PROJECT/AGENTS.md" "$BATS_TEST_TMPDIR/u3"
  install_block

  run diff "$BATS_TEST_TMPDIR/u2" "$BATS_TEST_TMPDIR/u3"
  [ "$status" -eq 0 ]
  run diff "$BATS_TEST_TMPDIR/u3" "$PROJECT/AGENTS.md"
  [ "$status" -eq 0 ]

  # User content survives verbatim; the managed blocks sit at the top of the file.
  run tail -n 5 "$PROJECT/AGENTS.md"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '# User doc\n\npara one\n\npara two')" ]
  [ "$(grep -c 'memory-bank:start' "$PROJECT/AGENTS.md")" -eq 1 ]
}

# ---- the /mb router knows about `drive` --------------------------------------

@test "drive_cmd: mb.md carries a drive row and a ### drive section dispatching to commands/drive.md" {
  grep -qE '^\| `drive' "$ROUTER_DOC"
  run awk '/^### drive$/{f=1;next} /^### /{f=0} f{print}' "$ROUTER_DOC"
  [ "$status" -eq 0 ]
  [[ "$output" == *"commands/drive.md"* ]] || false
  [[ "$output" == *"mb-drive.sh"* ]] || false
}

# ---- dispatch stays role-shaped ----------------------------------------------

@test "drive_cmd: doc pins no model tier and points dispatch at SKILL.md Invocation" {
  local body
  body="$(cat "$DOC")"
  if printf '%s' "$body" | grep -qiE '\b(sonnet|opus|haiku|fable|gpt-5)\b'; then
    echo "PINNED TIER in commands/drive.md — contract must stay role-shaped" >&2
    return 1
  fi
  [[ "$body" == *"SKILL.md"*"Invocation"* ]] || false
}
