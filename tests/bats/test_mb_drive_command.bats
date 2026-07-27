#!/usr/bin/env bats
# Tests for the `/mb drive` command wrapper + the AGENTS.md drive loop-contract
# (drive-loop Task 2 — REQ-DR-001, REQ-DR-003, REQ-DR-030, REQ-DR-031).
#
# Contract under test:
#   1. `commands/drive.md` wraps `scripts/mb-drive.sh`: it reads/scaffolds
#      `goal.md`, then documents the "call `next` -> execute the action ->
#      repeat" loop until a `stop_*` action (REQ-DR-001/003).
#   2. `/mb drive` REFUSES without a resolvable `goal.md` — exit 1 plus a
#      concrete fix-hint, reusing the `mb-goal-validate.sh` failure path; it
#      never silently starts (REQ-DR-031).
#   3. The shared AGENTS.md block rendered by `adapters/_lib_agents_md.sh`
#      carries the drive loop-contract: the agent is the runtime, role dispatch
#      is resolved from `pipeline.yaml` with exact `model`/`thinking`, and the
#      agent NEVER self-certifies done (REQ-DR-030 + REQ-DR-014).
#
# The refuse-path assertions do not grep prose: they EXTRACT the doc's
# `<!-- mb-drive:preflight -->` bash block and execute it against an isolated
# temp bank, so the documented behaviour is the tested behaviour.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  DOC="$REPO_ROOT/commands/drive.md"
  LIB="$REPO_ROOT/adapters/_lib_agents_md.sh"
  ROUTER_DOC="$REPO_ROOT/commands/mb.md"
  BANK="$BATS_TEST_TMPDIR/bank"
  PROJECT="$BATS_TEST_TMPDIR/project"
  mkdir -p "$BANK" "$PROJECT"
  # `progress_source: checklist` resolves against the RESOLVED bank. Before the
  # FIX-3 two-arg wiring the validator fell back to `.memory-bank` relative to
  # CWD (the real repo bank), so these tests passed for the wrong reason.
  printf '# Checklist\n\n- ⬜ placeholder item\n' > "$BANK/checklist.md"
}

# Extract the executable preflight snippet documented in commands/drive.md.
extract_preflight() {
  awk '
    /<!-- mb-drive:preflight -->/ { want = 1; next }
    want && /^```bash$/           { inside = 1; want = 0; next }
    inside && /^```$/             { exit }
    inside                        { print }
  ' "$DOC"
}

# Run the documented preflight against an isolated bank.
run_preflight() {
  local snippet
  snippet="$(extract_preflight)"
  [ -n "$snippet" ] || {
    echo "no <!-- mb-drive:preflight --> bash block found in $DOC" >&2
    return 1
  }
  run env SKILL_DIR="$REPO_ROOT" BANK="$BANK" bash -c "$snippet"
}

write_valid_goal() {
  cat > "$BANK/goal.md" <<'EOF'
---
id: G-900
status: active
mode: static
progress_source: checklist
progress_target: 100
---

# Goal

## Description

Drive-loop refuse-path fixture.

## Acceptance criteria

- [ ] first acceptance item
- [x] second acceptance item
EOF
}

# ---- commands/drive.md: shape + loop contract --------------------------------

@test "drive-cmd: commands/drive.md exists with command frontmatter" {
  [ -f "$DOC" ]
  run grep -qE '^description:' "$DOC"
  [ "$status" -eq 0 ]
  run grep -qE '^allowed-tools:' "$DOC"
  [ "$status" -eq 0 ]
}

@test "drive-cmd: doc wraps mb-drive.sh and documents the next->execute->repeat loop (REQ-DR-001/003)" {
  local body
  body="$(cat "$DOC")"
  # Wraps the decision function, and names the `next` subcommand explicitly.
  [[ "$body" == *"scripts/mb-drive.sh"* ]]
  [[ "$body" == *"mb-drive.sh next"* ]]
  # The agent is the runtime: execute the returned action, then call again.
  [[ "$body" == *"repeat"* ]] || [[ "$body" == *"again"* ]]
  # Terminates only on a stop_* action — all three must be named.
  [[ "$body" == *"stop_success"* ]]
  [[ "$body" == *"stop_human"* ]]
  [[ "$body" == *"stop_budget"* ]]
}

@test "drive-cmd: doc documents reading/scaffolding goal.md before the loop (DoD-1)" {
  local body
  body="$(cat "$DOC")"
  [[ "$body" == *"goal.md"* ]]
  [[ "$body" == *"templates/goal.md"* ]]
  [[ "$body" == *"scaffold"* ]] || [[ "$body" == *"Scaffold"* ]]
}

@test "drive-cmd: doc references only shipped scripts (no vapor)" {
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

# ---- REQ-DR-031: refuse without a resolvable goal.md -------------------------

@test "drive-cmd: preflight refuses (exit 1 + fix-hint) when goal.md is absent (REQ-DR-031)" {
  [ ! -f "$BANK/goal.md" ]
  run_preflight
  [ "$status" -eq 1 ]
  [[ "$output" == *"goal.md"* ]]
  # A concrete fix-hint, not a bare failure.
  [[ "$output" == *"re-run"* ]] || [[ "$output" == *"fill"* ]]
}

@test "drive-cmd: preflight scaffolds the goal template while refusing to start (DoD-1 + REQ-DR-031)" {
  run_preflight
  [ "$status" -eq 1 ]
  # Scaffolded so the user has something to fill in...
  [ -f "$BANK/goal.md" ]
  # ...but the loop must NOT have been declared startable off a bare template.
  [[ "$output" != *"drive loop started"* ]]
}

@test "drive-cmd: preflight refuses on an unresolvable goal.md via the validator failure path (REQ-DR-031)" {
  cat > "$BANK/goal.md" <<'EOF'
---
id: G-901
status: active
progress_source: spec-tasks
---

# Goal

No acceptance criteria section here.
EOF
  run_preflight
  [ "$status" -eq 1 ]
  # The validator's own fix-hints must surface (reuse, not a parallel message).
  [[ "$output" == *"acceptance"* ]] || [[ "$output" == *"Acceptance"* ]]
}

@test "drive-cmd: preflight passes (exit 0) on a resolvable goal.md" {
  write_valid_goal
  run_preflight
  [ "$status" -eq 0 ]
}

@test "drive-cmd: preflight never overwrites an existing goal.md" {
  write_valid_goal
  local before
  before="$(cat "$BANK/goal.md")"
  run_preflight
  [ "$status" -eq 0 ]
  [ "$(cat "$BANK/goal.md")" = "$before" ]
}

# ---- REQ-DR-030 + DoD-3: the AGENTS.md drive loop-contract -------------------

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

@test "drive-cmd: AGENTS.md block carries the drive loop-contract (REQ-DR-003/030)" {
  command -v jq >/dev/null || skip "jq required"
  install_block
  local body
  body="$(cat "$PROJECT/AGENTS.md")"
  # The agent is the runtime and calls the decision function itself.
  [[ "$body" == *"mb-drive.sh next"* ]]
  # Loop until a stop_* action.
  [[ "$body" == *"stop_success"* ]]
  [[ "$body" == *"stop_human"* ]]
  [[ "$body" == *"stop_budget"* ]]
  # Dispatch is resolved from pipeline.yaml with exact model/thinking.
  [[ "$body" == *"pipeline.yaml"* ]]
  [[ "$body" == *"model"* ]]
  [[ "$body" == *"thinking"* ]]
  [[ "$body" == *"codex"* ]]
  [[ "$body" == *"judge"* ]]
}

@test "drive-cmd: AGENTS.md block forbids self-certified done (REQ-DR-014/030)" {
  command -v jq >/dev/null || skip "jq required"
  install_block
  local body
  body="$(cat "$PROJECT/AGENTS.md")"
  [[ "$body" == *"self-certif"* ]] || [[ "$body" == *"self-assess"* ]]
  # Done requires BOTH firewall exit 0 and acceptance 100% — never the model.
  [[ "$body" == *"mb-flow-verify.sh"* ]]
  [[ "$body" == *"mb-goal-acceptance.sh"* ]]
  [[ "$body" == *"100%"* ]]
}

@test "drive-cmd: AGENTS.md block documents the no-goal refusal (REQ-DR-031)" {
  command -v jq >/dev/null || skip "jq required"
  install_block
  local body
  body="$(cat "$PROJECT/AGENTS.md")"
  [[ "$body" == *"mb-goal-validate.sh"* ]]
  [[ "$body" == *"refus"* ]]
}

@test "drive-cmd: AGENTS.md block references only shipped scripts (no vapor)" {
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

# ---- idempotency: re-rendering the block must not drift ----------------------

@test "drive-cmd: _agents_md_section renders byte-identically on repeat" {
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

@test "drive-cmd: repeated install keeps AGENTS.md byte-identical (no blank-line drift)" {
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
  # Exactly one MB section survives every re-render.
  [ "$(grep -c 'memory-bank:start' "$PROJECT/AGENTS.md")" -eq 1 ]
}

@test "drive-cmd: repeated install over user content reaches a fixed point and preserves it" {
  command -v jq >/dev/null || skip "jq required"
  # Trailing blank run is deliberate: the pre-fix replace-branch prepended one
  # more blank line per re-install, so the file grew without bound.
  printf '# User doc\n\npara one\n\npara two\n\n\n' > "$PROJECT/AGENTS.md"

  install_block
  install_block
  cp "$PROJECT/AGENTS.md" "$BATS_TEST_TMPDIR/u2"
  install_block
  cp "$PROJECT/AGENTS.md" "$BATS_TEST_TMPDIR/u3"
  install_block

  # Fixed point from the second render onwards — no per-install growth.
  run diff "$BATS_TEST_TMPDIR/u2" "$BATS_TEST_TMPDIR/u3"
  [ "$status" -eq 0 ]
  run diff "$BATS_TEST_TMPDIR/u3" "$PROJECT/AGENTS.md"
  [ "$status" -eq 0 ]

  # User content survives verbatim, interior blank lines included.
  run head -5 "$PROJECT/AGENTS.md"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '# User doc\n\npara one\n\npara two')" ]
  [ "$(grep -c 'memory-bank:start' "$PROJECT/AGENTS.md")" -eq 1 ]
}

# ═══════════════════════════════════════════════════════════════════════
# Fix-cycle 2 (judge NO_GO package, run 619bb6fe). One block per FIX-N.
# ═══════════════════════════════════════════════════════════════════════

# ---- FIX-1 [BLOCKER]: /mb router knows about `drive` ------------------------

@test "FIX-1: mb.md Subcommands table carries a drive row" {
  run grep -qE '^\| `drive' "$ROUTER_DOC"
  [ "$status" -eq 0 ]
}

@test "FIX-1: mb.md has a '### drive' implementation section dispatching to commands/drive.md" {
  run grep -qE '^### drive$' "$ROUTER_DOC"
  [ "$status" -eq 0 ]
  # The section must hand off to the command file, like ### openspec does.
  run awk '/^### drive$/{f=1;next} /^### /{f=0} f{print}' "$ROUTER_DOC"
  [ "$status" -eq 0 ]
  [[ "$output" == *"commands/drive.md"* ]]
  [[ "$output" == *"mb-drive.sh"* ]]
}

@test "FIX-1: the drive row documents the flags the command actually accepts" {
  local row
  row="$(grep -E '^\| `drive' "$ROUTER_DOC")"
  [[ "$row" == *"--route"* ]]
  [[ "$row" == *"--budget"* ]]
  [[ "$row" == *"--max-cycles"* ]]
}

# ---- FIX-2 [MAJOR]: --budget / --max-cycles are actually wired --------------

@test "FIX-2: preflight fence initialises the budget only when --budget was given" {
  local fence
  fence="$(extract_preflight)"
  [[ "$fence" == *"mb-work-budget.sh"* ]]
  [[ "$fence" == *"init"* ]]
  # Conditional, not unconditional: a drive without --budget must not stamp one.
  run bash -c 'printf %s "$1" | grep -c "mb-work-budget.sh\" init"' _ "$fence"
  [ "$output" -ge 1 ]
  [[ "$fence" == *'if [ -n "$BUDGET" ]'* ]] || [[ "$fence" == *'[ -n "$BUDGET" ]'* ]]
}

@test "FIX-2: preflight fence passes --max-cycles into mb-work-state.sh init" {
  local fence state_line
  fence="$(extract_preflight)"
  [[ "$fence" == *"mb-work-state.sh"* ]]
  [[ "$fence" == *"--max-cycles"* ]]
  # --max-cycles must reach the state init, not float unused.
  state_line="$(printf '%s\n' "$fence" | grep -n 'mb-work-state.sh" init' | head -1)"
  [ -n "$state_line" ]
  [[ "$fence" == *'MAX_CYCLES'* ]]
}

@test "FIX-2: one run-id threads through state, budget, stop-telemetry and the loop" {
  local body fence
  fence="$(extract_preflight)"
  body="$(cat "$DOC")"
  # A single run id is minted once...
  [[ "$fence" == *"new-run-id"* ]]
  [[ "$fence" == *"RUN_ID"* ]]
  # ...and reaches every stateful consumer.
  [[ "$fence" == *'mb-work-state.sh" init'* ]]
  [[ "$fence" == *'--run-id "$RUN_ID"'* ]]
  # the loop itself must carry it too
  [[ "$body" == *'--run-id "$RUN_ID"'* ]]
}

@test "FIX-2: every flag advertised in usage is wired to a real script call" {
  local body usage flag
  body="$(cat "$DOC")"
  usage="$(grep -oE '^/mb drive.*' "$DOC" | head -1)"
  [ -n "$usage" ]
  for flag in $(printf '%s\n' "$usage" | grep -oE '\-\-[a-z-]+'); do
    # Each advertised flag must appear on a line that invokes a scripts/ helper
    # (i.e. it is conducted), otherwise it is a silent no-op.
    if ! grep -E "scripts/mb-[a-z-]+\.sh" "$DOC" | grep -q -- "$flag"; then
      # --route/--phase go to mb-drive.sh next; allow that form too
      if ! grep -E "mb-drive\.sh\" (next|status)" "$DOC" | grep -q -- "$flag"; then
        echo "SILENT NO-OP: usage advertises $flag but nothing conducts it" >&2
        return 1
      fi
    fi
  done
}

@test "FIX-2 (codex R2): documented repair cycle works after preflight — mb-work-state.sh cycle exits 0" {
  write_valid_goal
  run_preflight
  [ "$status" -eq 0 ]
  # The run-id the preflight minted is durable state; the repair action's
  # documented call must succeed against it (pre-fix it exited 2: no init).
  local rid
  rid="$(bash "$REPO_ROOT/scripts/mb-work-state.sh" status --mb "$BANK" 2>/dev/null | python3 -c 'import json,sys; print((json.load(sys.stdin) or {}).get("run_id",""))' 2>/dev/null || true)"
  [ -n "$rid" ]
  run bash "$REPO_ROOT/scripts/mb-work-state.sh" cycle --run-id "$rid" --mb "$BANK"
  [ "$status" -eq 0 ]
}

# ---- FIX-3 [MAJOR]: bank resolution via mb_resolve_path --------------------

@test "FIX-3: preflight resolves the bank through _lib.sh::mb_resolve_path, not a hardcoded path" {
  local fence
  fence="$(extract_preflight)"
  [[ "$fence" == *"mb_resolve_path"* ]]
  [[ "$fence" == *"scripts/_lib.sh"* ]]
  # The bare hardcoded default must be gone as the SOLE source of the bank.
  run bash -c 'printf %s "$1" | grep -c "BANK=\"\\.memory-bank\""' _ "$fence"
  [ "$output" -eq 0 ]
}

@test "FIX-3: goal validation passes the bank as the second argument" {
  local fence
  fence="$(extract_preflight)"
  [[ "$fence" == *'mb-goal-validate.sh" "$BANK/goal.md" "$BANK"'* ]]
}

@test "FIX-3: preflight works against a bank at a non-standard path" {
  local alt="$BATS_TEST_TMPDIR/some/deep/custom-bank"
  mkdir -p "$alt"
  printf '# Checklist\n\n- ⬜ item\n' > "$alt/checklist.md"
  BANK="$alt" write_valid_goal
  # Run from a directory that has NO .memory-bank, so a hardcoded default or a
  # one-arg validator call would resolve the wrong bank and fail.
  local snippet
  snippet="$(extract_preflight)"
  run env -u MB_PATH SKILL_DIR="$REPO_ROOT" BANK="$alt" bash -c "cd '$BATS_TEST_TMPDIR' && $snippet"
  [ "$status" -eq 0 ]
}

# ---- FIX-4 [MAJOR]: honest dispatch source, no pinned model tiers -----------

@test "FIX-4: doc does not claim mb-workflow.sh reports agent/model/thinking" {
  # mb-workflow.sh emits name/source/steps/entrypoint/interactive/loop only —
  # verified by a live run. Claiming it carries the role tiers is vapor.
  local body
  body="$(cat "$DOC")"
  if printf '%s' "$body" | grep -qiE 'mb-workflow\.sh[^.]{0,120}(model|thinking)'; then
    echo "VAPOR: doc attributes model/thinking to mb-workflow.sh" >&2
    return 1
  fi
}

@test "FIX-4: doc sources exact agent/model/thinking from pipeline.yaml roles" {
  local body
  body="$(cat "$DOC")"
  [[ "$body" == *"pipeline.yaml"* ]]
  [[ "$body" == *"roles"* ]]
  [[ "$body" == *"mb-pipeline.sh"* ]]
}

@test "FIX-4: dispatch contract pins NO model tier (role-shaped, per AGR-023)" {
  local body section
  body="$(cat "$DOC")"
  # No tier names hardcoded as the dispatch norm anywhere in the doc.
  if printf '%s' "$body" | grep -qiE '\b(sonnet|opus|haiku|fable|gpt-5)\b'; then
    echo "PINNED TIER in commands/drive.md — contract must stay role-shaped" >&2
    printf '%s' "$body" | grep -inE '\b(sonnet|opus|haiku|fable|gpt-5)\b' >&2
    return 1
  fi
  section="$(awk '/memory-bank:start/{f=1} f{print} /memory-bank:end/{f=0}' "$PROJECT/AGENTS.md" 2>/dev/null || true)"
}

@test "FIX-4: AGENTS.md drive block is role-shaped and cites pipeline.yaml roles" {
  command -v jq >/dev/null || skip "jq required"
  install_block
  local section
  section="$(awk '/memory-bank:start/{f=1} f{print} /memory-bank:end/{f=0}' "$PROJECT/AGENTS.md")"
  [[ "$section" == *"pipeline.yaml"* ]]
  [[ "$section" == *"roles"* ]]
  if printf '%s' "$section" | grep -qiE '\b(sonnet|opus|haiku|fable)\b'; then
    echo "PINNED TIER in the AGENTS.md drive contract" >&2
    return 1
  fi
  if printf '%s' "$section" | grep -qiE 'mb-workflow\.sh[^.]{0,120}(model|thinking)'; then
    echo "VAPOR: AGENTS.md block attributes model/thinking to mb-workflow.sh" >&2
    return 1
  fi
}

# ---- FIX-5 [MAJOR]: T4 stop-telemetry wiring -------------------------------

@test "FIX-5: preflight arms stop-telemetry after a successful preflight" {
  local fence
  fence="$(extract_preflight)"
  [[ "$fence" == *"mb-drive-stop.sh"* ]]
  [[ "$fence" == *"arm"* ]]
}

@test "FIX-5: the loop records every stop_* action before exiting" {
  local body
  body="$(cat "$DOC")"
  [[ "$body" == *"mb-drive-stop.sh"* ]]
  [[ "$body" == *"record --action"* ]]
}

@test "FIX-5: arming actually produces a drive-state slot (functional)" {
  write_valid_goal
  run_preflight
  [ "$status" -eq 0 ]
  # arm's whole job: mark the drive RUNNING so the Stop-hook gate is live.
  run bash "$REPO_ROOT/scripts/mb-drive-stop.sh" state --bank "$BANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"running"* ]] || [[ "$output" == *"status"* ]]
}

# ---- FIX-6 [MAJOR]: an untouched scaffold must never start the loop ---------

@test "FIX-6: a scaffolded-but-unedited goal.md is still refused on re-run (REQ-DR-031)" {
  # First run scaffolds and refuses (already covered) ...
  run_preflight
  [ "$status" -eq 1 ]
  [ -f "$BANK/goal.md" ]
  # ... and the SECOND run, with the template untouched, must ALSO refuse.
  # Pre-fix this returned 0 (the shipped template is structurally valid), so
  # the loop started on placeholder text.
  run_preflight
  [ "$status" -eq 1 ]
  [[ "$output" == *"placeholder"* ]] || [[ "$output" == *"template"* ]]
}

@test "FIX-6: filling the template in makes the goal acceptable" {
  run_preflight
  [ "$status" -eq 1 ]
  write_valid_goal
  run_preflight
  [ "$status" -eq 0 ]
}

# ---- static analysis of the executable documentation ------------------------

@test "preflight fence passes shellcheck (logic in markdown must still be linted)" {
  command -v shellcheck >/dev/null || skip "shellcheck not installed"
  local f="$BATS_TEST_TMPDIR/fence.sh"
  { echo '#!/usr/bin/env bash'; extract_preflight; } > "$f"
  run shellcheck --severity=error --shell=bash "$f"
  [ "$status" -eq 0 ]
}
