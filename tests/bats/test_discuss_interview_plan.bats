#!/usr/bin/env bats
# interview_plan: — svp-interview-upgrade Task 1 prompt contract.
# Interview-plan section + grilling rule 11 (block generation / cancel→draft) +
# grilling rule 14 (fast-to-code bypass) + the C2 interview-plan template.
# Every clause is proven with BOTH assert_clause (present) and
# assert_clause_load_bearing (behaviour-bearing, not word co-occurrence).
#
# Name convention: every @test starts with `interview_plan: ` — the Eval
# red-anchor (`not ok [0-9]+ (artifact_check|artifact_write|interview_plan): `).

load 'lib/discuss_contract'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  DISCUSS="$REPO_ROOT/commands/discuss.md"
  TEMPLATES="$REPO_ROOT/references/templates.md"
  MB_DISCUSS_CLAUSES=()
  MB_DISCUSS_CLAUSES+=("plan-file-path|mb_section|Interview plan|[Bb]efore the first question.*tmp/interview-plan|interview.plan|s/[Bb]efore the first question, //|REQ-001")
  MB_DISCUSS_CLAUSES+=("rule11-block-generation|mb_rule|11|[Dd]o not generate.*open|generate|s/Do not generate/You may generate/|REQ-002")
  MB_DISCUSS_CLAUSES+=("rule11-cancel-draft|mb_rule|11|[Cc]ancel.*status: draft.*preserv|[Cc]ancel|s/ and preserves the plan file for resume//|REQ-019")
  MB_DISCUSS_CLAUSES+=("rule14-record-tradeoff|mb_rule|14|record the choice.*trade.?off.*frontmatter|record the choice|s/ and its quality trade-off//|REQ-020")
  MB_DISCUSS_CLAUSES+=("rule14-quality-default|mb_rule|14|[Qq]uality mode stays the default|[Qq]uality mode|s/stays the default/is an option/|REQ-020")
  MB_DISCUSS_CLAUSES+=("template-c2-inherited|mb_section|Interview plan template|Inherited decisions .do not re-ask.|Discovered mid-interview|/Inherited decisions/d|REQ-001")
  MB_DISCUSS_CLAUSES+=("template-c2-topics|mb_section|Interview plan template|^## Topics|Inherited decisions|s/^## Topics/## Themes/|REQ-001")
  MB_DISCUSS_CLAUSES+=("template-c2-discovered|mb_section|Interview plan template|Discovered mid-interview|Inherited decisions|/Discovered mid-interview/d|REQ-001")
  # REQ-002 close-gate: the DETERMINISTIC pre-generation call, not just prose.
  MB_DISCUSS_CLAUSES+=("close-gate-invocation|mb_section|Write . finalize|mb-interview-artifact-check.sh. plan .* --require-closed|interview plan|s/ --require-closed//|REQ-002")
  MB_DISCUSS_CLAUSES+=("close-gate-blocking|mb_section|Write . finalize|[Ee]xit 1 means open .- \\[ \\]. topics remain: generation does not start|generation|s/generation does not start/generation may proceed anyway/|REQ-002")
  MB_DISCUSS_CLAUSES+=("close-gate-not-judgement|mb_section|Write . finalize|never substitute your own judgement|exit code|s/never substitute your own judgement/you may substitute your own judgement/|REQ-002")
  MB_DISCUSS_CLAUSES+=("rule11-code-enforced|mb_rule|11|enforced by code, not by judgement|open|s/enforced by code, not by judgement/a matter of judgement/|REQ-002")
  # Pre-flight bank resolution must not hardcode a local .memory-bank/.
  MB_DISCUSS_CLAUSES+=("preflight-resolve-bank|mb_section|Pre-flight|mb_resolve_path|Memory Bank|s/mb_resolve_path/a hardcoded path/|REQ-002")
  MB_DISCUSS_CLAUSES+=("preflight-global-bank|mb_section|Pre-flight|[Nn]ever hardcode|global|s/Never hardcode/Always hardcode/|REQ-002")
}

# ─── Interview-plan section (REQ-001) ───

@test "interview_plan: discuss.md writes the plan before the first question" {
  run assert_clause "$DISCUSS" plan-file-path
  [ "$status" -eq 0 ]
  run assert_clause_load_bearing "$DISCUSS" plan-file-path
  [ "$status" -eq 0 ]
}

# ─── Rule 11 — block generation while topics are open (REQ-002) ───

@test "interview_plan: rule 11 blocks generation while topics stay open" {
  run assert_clause "$DISCUSS" rule11-block-generation
  [ "$status" -eq 0 ]
  run assert_clause_load_bearing "$DISCUSS" rule11-block-generation
  [ "$status" -eq 0 ]
}

# ─── Rule 11 — cancel keeps draft + preserves plan (REQ-019) ───

@test "interview_plan: rule 11 keeps draft status and preserves the plan on cancel" {
  run assert_clause "$DISCUSS" rule11-cancel-draft
  [ "$status" -eq 0 ]
  run assert_clause_load_bearing "$DISCUSS" rule11-cancel-draft
  [ "$status" -eq 0 ]
}

# ─── Rule 14 — fast-to-code bypass records the trade-off (REQ-020) ───

@test "interview_plan: rule 14 records the fast-to-code choice and quality trade-off" {
  run assert_clause "$DISCUSS" rule14-record-tradeoff
  [ "$status" -eq 0 ]
  run assert_clause_load_bearing "$DISCUSS" rule14-record-tradeoff
  [ "$status" -eq 0 ]
}

@test "interview_plan: rule 14 keeps quality mode as the default" {
  run assert_clause "$DISCUSS" rule14-quality-default
  [ "$status" -eq 0 ]
  run assert_clause_load_bearing "$DISCUSS" rule14-quality-default
  [ "$status" -eq 0 ]
}

# ─── C2 template — all three headings (REQ-001) ───

@test "interview_plan: templates.md carries the C2 Inherited-decisions heading" {
  run assert_clause "$TEMPLATES" template-c2-inherited
  [ "$status" -eq 0 ]
  run assert_clause_load_bearing "$TEMPLATES" template-c2-inherited
  [ "$status" -eq 0 ]
}

@test "interview_plan: templates.md carries the C2 Topics heading" {
  run assert_clause "$TEMPLATES" template-c2-topics
  [ "$status" -eq 0 ]
  run assert_clause_load_bearing "$TEMPLATES" template-c2-topics
  [ "$status" -eq 0 ]
}

@test "interview_plan: templates.md carries the C2 Discovered-mid-interview heading" {
  run assert_clause "$TEMPLATES" template-c2-discovered
  [ "$status" -eq 0 ]
  run assert_clause_load_bearing "$TEMPLATES" template-c2-discovered
  [ "$status" -eq 0 ]
}

# ─── REQ-002 deterministic close-gate (review [1]) ───

_clause_pair() {
  run assert_clause "$DISCUSS" "$1"
  [ "$status" -eq 0 ]
  run assert_clause_load_bearing "$DISCUSS" "$1"
  [ "$status" -eq 0 ]
}

@test "interview_plan: generation is gated by an explicit --require-closed call" {
  # The DoD box was ticked while `grep -c require-closed commands/discuss.md`
  # returned 0 — rule 11 was prose only, with no deterministic code gate.
  _clause_pair close-gate-invocation
}

@test "interview_plan: a non-zero close-gate blocks generation" { _clause_pair close-gate-blocking; }
@test "interview_plan: the close-gate is the exit code, not the agent's judgement" { _clause_pair close-gate-not-judgement; }
@test "interview_plan: rule 11 defers to the code gate" { _clause_pair rule11-code-enforced; }

@test "interview_plan: the close-gate call names the plan validator in plan mode" {
  # Bind the clause to the real script: a prompt may not reference a validator
  # that does not exist, and the flag must be one the validator accepts.
  run assert_script_present scripts/mb-interview-artifact-check.sh
  [ "$status" -eq 0 ]
  grep -q -- '--require-closed' "$REPO_ROOT/scripts/mb-interview-artifact-check.sh"
}

# ─── Pre-flight resolves the ACTIVE bank, local or global (review [7]) ───

@test "interview_plan: pre-flight resolves the bank through mb_resolve_path" { _clause_pair preflight-resolve-bank; }
@test "interview_plan: pre-flight forbids hardcoding the bank path" { _clause_pair preflight-global-bank; }

@test "interview_plan: pre-flight no longer pins MB_PATH to a literal .memory-bank/" {
  # The exact regression: `Resolve MB_PATH = .memory-bank/` refused to run in a
  # project whose bank is registered globally.
  local block
  # Anti-vacuity: the pattern asserted absent must genuinely match the PRE-FIX
  # wording, proven here against an inline fixture. An earlier version of this
  # test read the old wording from `git show HEAD:` — which silently stopped
  # proving anything the moment the fix was committed and HEAD moved on.
  printf '%s\n' '1. Resolve `MB_PATH = .memory-bank/`. Refuse if missing (suggest `/mb init`).' \
    | grep -Eq 'MB_PATH = .memory-bank/'
  block="$(mb_section "$DISCUSS" 'Pre-flight')"
  ! printf '%s\n' "$block" | grep -Eq 'MB_PATH = .memory-bank/'
  printf '%s\n' "$block" | grep -q 'mb_resolve_path'
}

# ─── Harness self-test (C9): a bare clause (clause-ERE == topic-anchor) is rejected ───

@test "interview_plan: harness rejects a vacuous (bare) clause" {
  MB_DISCUSS_CLAUSES+=("bare-generate|mb_rule|11|generate|generate|s/Do not generate/You may generate/|REQ-002")
  run assert_clause_load_bearing "$DISCUSS" bare-generate
  [ "$status" -ne 0 ]
  echo "$output" | grep -Eq 'reason=(vacuous|mutation_removed_topic)'
}

@test "interview_plan: harness accepts a behavioural clause under mutation" {
  run assert_clause_load_bearing "$DISCUSS" rule11-block-generation
  [ "$status" -eq 0 ]
}

# ─── helper resolution: SKILL_DIR, not the consumer cwd (r2 review [2]) ───
#
# The documented close gate used to read `bash scripts/mb-interview-artifact-check.sh …`.
# From a normal project — which has no `scripts/` directory of its own — that is
# exit 127, so the mandatory REQ-002 gate simply did not run; and a project that
# DOES ship `scripts/mb-interview-artifact-check.sh` silently supplied its own
# gate. These tests drive the prompt the way a user would: from a scratch
# project directory outside this repo.

@test "interview_plan: discuss.md defines SKILL_DIR before using it" {
  # $SKILL_DIR was referenced (Phase 2, EARS validator) but never initialized.
  local block
  block="$(mb_section "$DISCUSS" 'Pre-flight')"
  printf '%s\n' "$block" | grep -q 'SKILL_DIR='
}

@test "interview_plan: no bundled helper is invoked through a bare relative scripts/ path" {
  # Anti-vacuity: the pattern must genuinely match the pre-fix wording.
  printf '%s\n' 'bash scripts/mb-interview-artifact-check.sh plan "$X" --require-closed' \
    | grep -Eq '(^|[^/A-Za-z_$])scripts/mb-'
  # Pre-flight is exempt: that is where the anti-pattern is QUOTED as forbidden.
  local body
  body="$(grep -vFx -f <(mb_section "$DISCUSS" 'Pre-flight') "$DISCUSS")"
  ! printf '%s\n' "$body" | grep -Eq '(^|[^/A-Za-z_$-])scripts/mb-'
}

@test "interview_plan: the close gate still blocks when run from a foreign project cwd" {
  # The real consumer path: extract the gate command from the prompt, run it
  # from a scratch project that has NO scripts/ directory. A 127 here means the
  # gate never executed.
  local proj="$BATS_TEST_TMPDIR/proj" cmd
  mkdir -p "$proj/.memory-bank/tmp"
  printf '## Inherited decisions (do not re-ask)\n\n## Topics\n\n- [ ] still open\n\n## Discovered mid-interview\n' \
    > "$proj/.memory-bank/tmp/interview-plan-foo.md"

  cmd="$(mb_section "$DISCUSS" 'Write . finalize' | grep -m1 'mb-interview-artifact-check.sh" plan')"
  [ -n "$cmd" ]

  run env -i PATH="$PATH" HOME="$HOME" SKILL_DIR="$REPO_ROOT" MB_PATH="$proj/.memory-bank" \
    bash -c "cd '$proj' && ${cmd//<topic>/foo}"
  [ "$status" -eq 1 ] || { echo "gate did not block (status=$status): $output"; false; }
}

@test "interview_plan: a forged project-local helper cannot supply the close gate" {
  # A project shipping its own scripts/mb-interview-artifact-check.sh must not be
  # able to answer the gate with exit 0.
  local proj="$BATS_TEST_TMPDIR/proj2" cmd
  mkdir -p "$proj/.memory-bank/tmp" "$proj/scripts"
  printf '## Inherited decisions (do not re-ask)\n\n## Topics\n\n- [ ] still open\n\n## Discovered mid-interview\n' \
    > "$proj/.memory-bank/tmp/interview-plan-foo.md"
  printf '#!/usr/bin/env bash\necho "artifact=ok open_topics=0"\nexit 0\n' \
    > "$proj/scripts/mb-interview-artifact-check.sh"
  chmod +x "$proj/scripts/mb-interview-artifact-check.sh"

  cmd="$(mb_section "$DISCUSS" 'Write . finalize' | grep -m1 'mb-interview-artifact-check.sh" plan')"
  [ -n "$cmd" ]

  run env -i PATH="$PATH" HOME="$HOME" SKILL_DIR="$REPO_ROOT" MB_PATH="$proj/.memory-bank" \
    bash -c "cd '$proj' && ${cmd//<topic>/foo}"
  [ "$status" -eq 1 ] || { echo "forged local helper answered the gate (status=$status)"; false; }
}

# ─── harness self-test: duplicate rules (r2 review [9]) ───

@test "interview_plan: mb_rule rejects a DUPLICATED rule number" {
  # mb_rule stopped at the first match, so a second rule 11 saying generation may
  # proceed with open topics left every clause test green while the executable
  # contract contained a direct REQ-002 inversion.
  local f="$BATS_TEST_TMPDIR/dup.md"
  cp "$DISCUSS" "$f"
  printf '\n11. **Generation may proceed with open topics.** The close gate is advisory.\n' >> "$f"
  run mb_rule "$f" 11
  [ "$status" -ne 0 ]
  echo "$output" | grep -q 'rule_duplicated'
}

@test "interview_plan: a contradictory duplicate rule 11 fails the REQ-002 clause" {
  # The consequence: the inverting duplicate must break the clause assertion,
  # not be silently skipped.
  local f="$BATS_TEST_TMPDIR/dup2.md"
  cp "$DISCUSS" "$f"
  printf '\n11. **Generation may proceed with open topics.** The close gate is advisory.\n' >> "$f"
  run assert_clause "$f" rule11-block-generation
  [ "$status" -ne 0 ]
}

@test "interview_plan: mb_rule still accepts a uniquely numbered rule" {
  run mb_rule "$DISCUSS" 11
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'No generation with open topics'
}
