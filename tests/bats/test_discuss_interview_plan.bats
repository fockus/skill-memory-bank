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

load lib/assert

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  DISCUSS="$REPO_ROOT/commands/discuss.md"
  TEMPLATES="$REPO_ROOT/references/templates.md"
  MB_DISCUSS_CLAUSES=()
  MB_DISCUSS_CLAUSES+=("plan-file-path|mb_section|Interview plan|[Bb]efore the first question, write an interview plan to .*tmp/interview-plan|interview.plan|s/question, write an/question, do not write an/|REQ-001")
  MB_DISCUSS_CLAUSES+=("rule11-block-generation|mb_rule|11|[Dd]o not generate.*open|generate|s/Do not generate/You may generate/|REQ-002")
  MB_DISCUSS_CLAUSES+=("rule11-cancel-draft|mb_rule|11|[Cc]ancel.*status: draft.*preserv|[Cc]ancel|s/ and preserves the plan file for resume//|REQ-019")
  MB_DISCUSS_CLAUSES+=("rule14-record-tradeoff|mb_rule|14|record the choice.*trade.?off.*frontmatter|record the choice|s/ and its quality trade-off//|REQ-020")
  MB_DISCUSS_CLAUSES+=("rule14-quality-default|mb_rule|14|[Qq]uality mode stays the default|[Qq]uality mode|s/stays the default/is an option/|REQ-020")
  MB_DISCUSS_CLAUSES+=("template-c2-inherited|mb_section|Interview plan template|Inherited decisions .do not re-ask.|Discovered mid-interview|/Inherited decisions/d|REQ-001")
  MB_DISCUSS_CLAUSES+=("template-c2-topics|mb_section|Interview plan template|^## Topics|Inherited decisions|s/^## Topics/## Themes/|REQ-001")
  MB_DISCUSS_CLAUSES+=("template-c2-discovered|mb_section|Interview plan template|Discovered mid-interview|Inherited decisions|/Discovered mid-interview/d|REQ-001")
  # REQ-002 close-gate: the DETERMINISTIC pre-generation call, not just prose.
  MB_DISCUSS_CLAUSES+=("close-gate-invocation|mb_section|Write . finalize|mb-interview-artifact-check.sh. plan .* --require-closed|interview plan|s/ --require-closed//|REQ-002")
  MB_DISCUSS_CLAUSES+=("close-gate-blocking|mb_section|Write . finalize|open_topics. greater than 0 . unclosed themes. Generation does not start|generation|s/Generation does not start/Generation may proceed anyway/|REQ-002")
  MB_DISCUSS_CLAUSES+=("close-gate-not-judgement|mb_section|Write . finalize|never substitute your own judgement|exit code|s/never substitute your own judgement/you may substitute your own judgement/|REQ-002")
  MB_DISCUSS_CLAUSES+=("rule11-code-enforced|mb_rule|11|enforced by code, not by judgement|open|s/enforced by code, not by judgement/a matter of judgement/|REQ-002")
  # r3 review [15]: exit 1 covers BOTH open topics and structural breakage, so
  # the contract must route on open_topics, not on the exit code alone.
  MB_DISCUSS_CLAUSES+=("close-gate-routes-structural|mb_section|Write . finalize|open_topics=0. . the plan is structurally broken|open_topics|s/the plan is structurally broken/the same unanswered-theme case/|REQ-002")
  MB_DISCUSS_CLAUSES+=("close-gate-repair-path|mb_section|Write . finalize|repair the plan file from the stderr reason codes|repair|s/repair the plan file from the stderr reason codes/ask the missing questions/|REQ-002")
  # r3 review [16]: the glossary path must follow the resolved bank.
  # Pre-flight bank resolution must not hardcode a local .memory-bank/.
  MB_DISCUSS_CLAUSES+=("preflight-resolve-bank|mb_section|Pre-flight|mb_resolve_path|Memory Bank|s/mb_resolve_path/a hardcoded path/|REQ-002")
  MB_DISCUSS_CLAUSES+=("preflight-global-bank|mb_section|Pre-flight|[Nn]ever hardcode|global|s/Never hardcode/Always hardcode/|REQ-002")
  # r5 review [2]: the plan file is keyed by TOPIC, so a second /mb discuss on
  # the same topic shares it. The gate verdict must therefore be bound to BYTES
  # (digest), re-checked immediately before each publication.
  MB_DISCUSS_CLAUSES+=("plan-install-print-digest|mb_section|Interview plan|--print-digest|install-plan|s/ --print-digest//|REQ-002")
  MB_DISCUSS_CLAUSES+=("plan-digest-recorded|mb_section|Interview plan|Record the printed .digest. as .PLAN_DIGEST|digest|s/Record the printed/Ignore the printed/|REQ-002")
  MB_DISCUSS_CLAUSES+=("close-gate-digest-binding|mb_section|Write . finalize|digest=. MUST equal the .PLAN_DIGEST|digest|s/MUST equal/may differ from/|REQ-002")
  MB_DISCUSS_CLAUSES+=("close-gate-digest-mismatch-blocks|mb_section|Write . finalize|different digest means another .*do not generate|digest|s/: do not generate, re-read/: carry on, ignoring/|REQ-002")
  MB_DISCUSS_CLAUSES+=("close-gate-recheck-before-publish|mb_section|Write . finalize|[Rr]e-run the same gate command immediately before each publication|gate|s/immediately before each publication/at any convenient moment/|REQ-002")
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

# ─── r5 review [2]: the verdict is bound to bytes, not to a filename ────────

@test "interview_plan: the plan is installed with --print-digest" { _clause_pair plan-install-print-digest; }
@test "interview_plan: the printed digest is recorded for the run" { _clause_pair plan-digest-recorded; }
@test "interview_plan: the gate verdict must match the recorded digest" { _clause_pair close-gate-digest-binding; }
@test "interview_plan: a digest mismatch blocks generation" { _clause_pair close-gate-digest-mismatch-blocks; }
@test "interview_plan: the gate is re-run immediately before each publication" { _clause_pair close-gate-recheck-before-publish; }

@test "interview_plan: both scripts really accept --print-digest" {
  # The clause may not prescribe a flag the tools reject: run them, do not grep.
  local f="$BATS_TEST_TMPDIR/plan.md"
  printf '## Inherited decisions (do not re-ask)\n\n- none\n\n## Topics\n\n- [x] scope\n\n## Discovered mid-interview\n' > "$f"
  run "$REPO_ROOT/scripts/mb-interview-artifact-check.sh" plan "$f" --require-closed --print-digest
  [ "$status" -eq 0 ] || { echo "the checker rejected --print-digest: $output"; false; }
  [[ "$output" == *" digest="* ]] || { echo "no digest in: $output"; false; }

  local bank="$BATS_TEST_TMPDIR/bank"; mkdir -p "$bank/tmp"
  run "$REPO_ROOT/scripts/mb-interview-artifact-write.sh" install-plan \
    --mb "$bank" --topic foo --candidate "$f" --print-digest
  [ "$status" -eq 0 ] || { echo "the writer rejected --print-digest: $output"; false; }
  [[ "$output" == *" digest="* ]] || { echo "no digest in: $output"; false; }
}

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
  printf '%s\n' "$block" | grep -q 'mb_resolve_path'
  # `! cmd` does NOT fail a bats test unless it is the LAST command, so this
  # assertion used to be masked by the grep that followed it. Made explicit.
  if printf '%s\n' "$block" | grep -Eq 'MB_PATH = .memory-bank/'; then
    echo "pre-flight pins MB_PATH to a literal .memory-bank/"; false
  fi
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

@test "interview_plan: the bundle root is NOT derived from dirname \$0" {
  # r3 review [1]: in an executable-Markdown snippet `$0` is the SHELL, not this
  # file, so `$(dirname "$0")/..` resolves to the parent of the USER's cwd. The
  # mandatory close gate then pointed at a nonexistent (or foreign) helper.
  # Scoped to EXECUTABLE fenced code: the rule statement below the fence quotes
  # the anti-pattern on purpose, and prose is not what runs.
  # Anti-vacuity: the forbidden pattern must genuinely match the pre-fix line.
  printf '%s\n' 'SKILL_DIR="${SKILL_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"' \
    | grep -Eq 'dirname "\$0"'
  local code
  code="$(awk '/^```/{f=!f; next} f' "$DISCUSS")"
  [ -n "$code" ]
  ! printf '%s\n' "$code" | grep -Eq 'dirname "\$0"'
}

@test "interview_plan: discuss.md resolves the bundle through MB_SKILLS_ROOT" {
  # The repo-wide convention for command files (commands/mb.md, commands/agree.md):
  # ${MB_SKILLS_ROOT:-$HOME/.claude/skills/memory-bank}.
  # Scoped to the ASSIGNMENT inside executable code: grepping the whole section
  # stayed green when only the prose still mentioned the variable.
  local code
  code="$(awk '/^```/{f=!f; next} f' "$DISCUSS")"
  printf '%s\n' "$code" | grep -Eq 'SKILL_DIR="\$\{MB_SKILLS_ROOT:-'
}

@test "interview_plan: no bundled helper is invoked through a bare relative scripts/ path" {
  # Anti-vacuity: the pattern must genuinely match the pre-fix wording.
  printf '%s\n' 'bash scripts/mb-interview-artifact-check.sh plan "$X" --require-closed' \
    | grep -Eq '(^|[^/A-Za-z_$])scripts/mb-'
  # Pre-flight is exempt: that is where the anti-pattern is QUOTED as forbidden.
  local body
  body="$(grep -vFx -f <(mb_section "$DISCUSS" 'Pre-flight') "$DISCUSS")"
  refute_grep -Eq '(^|[^/A-Za-z_$-])scripts/mb-' <<<"$body"
}

# _preflight_resolution — the WHOLE fenced bundle-root block as documented.
# Extracting only the SKILL_DIR= line silently dropped the existence guard that
# follows it, so the guard could be deleted with every test still green.
_preflight_resolution() {
  mb_section "$DISCUSS" 'Pre-flight' | awk '/^```/{f=!f; next} f'
}

# _gate_cmd — the close-gate command exactly as documented, topic substituted.
_gate_cmd() {
  mb_section "$DISCUSS" 'Write . finalize' | grep -m1 'mb-interview-artifact-check.sh" plan'
}

_open_plan_project() {
  mkdir -p "$1/.memory-bank/tmp"
  printf '## Inherited decisions (do not re-ask)\n\n## Topics\n\n- [ ] still open\n\n## Discovered mid-interview\n' \
    > "$1/.memory-bank/tmp/interview-plan-foo.md"
}

@test "interview_plan: the close gate blocks from a foreign cwd with SKILL_DIR UNSET" {
  # The round-2 version of this test passed SKILL_DIR="$REPO_ROOT" and therefore
  # proved nothing about the resolution itself. Now the documented resolution
  # line runs for real; only the sanctioned MB_SKILLS_ROOT override is supplied.
  local proj="$BATS_TEST_TMPDIR/proj" res cmd
  _open_plan_project "$proj"
  res="$(_preflight_resolution)"; [ -n "$res" ]
  cmd="$(_gate_cmd)"; [ -n "$cmd" ]

  run env -i PATH="$PATH" HOME="$HOME" MB_SKILLS_ROOT="$REPO_ROOT" MB_PATH="$proj/.memory-bank" \
    bash -c "cd '$proj' && $res
${cmd//<topic>/foo}"
  [ "$status" -eq 1 ] || { echo "gate did not block (status=$status): $output"; false; }
}

@test "interview_plan: a forged project-local helper cannot supply the close gate" {
  local proj="$BATS_TEST_TMPDIR/proj2" res cmd
  _open_plan_project "$proj"
  mkdir -p "$proj/scripts"
  printf '#!/usr/bin/env bash\necho "artifact=ok open_topics=0"\nexit 0\n' \
    > "$proj/scripts/mb-interview-artifact-check.sh"
  chmod +x "$proj/scripts/mb-interview-artifact-check.sh"
  res="$(_preflight_resolution)"; [ -n "$res" ]
  cmd="$(_gate_cmd)"; [ -n "$cmd" ]

  run env -i PATH="$PATH" HOME="$HOME" MB_SKILLS_ROOT="$REPO_ROOT" MB_PATH="$proj/.memory-bank" \
    bash -c "cd '$proj' && $res
${cmd//<topic>/foo}"
  [ "$status" -eq 1 ] || { echo "forged local helper answered the gate (status=$status)"; false; }
}

@test "interview_plan: a forged helper in the cwd PARENT cannot be picked up" {
  # The precise round-2 defect: dirname "$0"/.. == the parent of the user's cwd.
  # An attacker tree there must never become the bundle.
  local root="$BATS_TEST_TMPDIR/outer" proj res cmd
  proj="$root/inner"
  _open_plan_project "$proj"
  mkdir -p "$root/scripts"
  printf '#!/usr/bin/env bash\necho "artifact=ok open_topics=0"\nexit 0\n' \
    > "$root/scripts/mb-interview-artifact-check.sh"
  chmod +x "$root/scripts/mb-interview-artifact-check.sh"
  res="$(_preflight_resolution)"; [ -n "$res" ]
  cmd="$(_gate_cmd)"; [ -n "$cmd" ]

  run env -i PATH="$PATH" HOME="$HOME" MB_SKILLS_ROOT="$REPO_ROOT" MB_PATH="$proj/.memory-bank" \
    bash -c "cd '$proj' && $res
${cmd//<topic>/foo}"
  [ "$status" -eq 1 ] || { echo "parent-dir forgery answered the gate (status=$status)"; false; }
}

@test "interview_plan: an unresolvable bundle fails LOUDLY, never silently proceeds" {
  # With no override and no installed bundle the resolution must not fall back to
  # something cwd-relative and must not report a passing gate.
  local proj="$BATS_TEST_TMPDIR/proj4" fakehome res cmd
  _open_plan_project "$proj"
  fakehome="$BATS_TEST_TMPDIR/nohome"; mkdir -p "$fakehome"
  res="$(_preflight_resolution)"; [ -n "$res" ]
  cmd="$(_gate_cmd)"; [ -n "$cmd" ]

  # `status != 0` is NOT enough: a missing helper yields 127 on its own, so that
  # assertion stayed green with the guard deleted. Demand the guard's own
  # contract — exit 2 and a message naming the override.
  run env -i PATH="$PATH" HOME="$fakehome" MB_PATH="$proj/.memory-bank" \
    bash -c "cd '$proj' && $res
${cmd//<topic>/foo}"
  [ "$status" -eq 2 ] || { echo "expected the loud guard (exit 2), got $status"; false; }
  echo "$output" | grep -q 'skill bundle not found' \
    || { echo "no diagnostic naming the unresolved bundle: $output"; false; }
  echo "$output" | grep -q 'MB_SKILLS_ROOT' \
    || { echo "diagnostic does not tell the user how to fix it: $output"; false; }
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

# ─── close-gate routing and glossary path (r3 review [15], [16]) ───

@test "interview_plan: a structurally broken plan is routed to repair, not to more questions" { _clause_pair close-gate-routes-structural; }
@test "interview_plan: the repair path is spelled out" { _clause_pair close-gate-repair-path; }

@test "interview_plan: rule 13 writes the glossary to the RESOLVED bank" {
  # `.memory-bank/glossary.md` does not exist in a project on a global bank.
  local block
  block="$(mb_rule "$DISCUSS" 13)"
  printf '%s\n' "$block" | grep -q 'MB_PATH/glossary.md'
  if printf '%s\n' "$block" | grep -Eq 'in .\.memory-bank/glossary\.md'; then
    echo "rule 13 still pins the literal local bank path"; false
  fi
}

@test "interview_plan: rule 13 passes --mb \$MB_PATH to the glossary writer" {
  mb_rule "$DISCUSS" 13 | grep -q -- '--mb "\$MB_PATH"'
}

# ─── the REQ template matches the executable command (r3 review [24]) ───

@test "interview_plan: templates.md documents the per-spec-local REQ namespace" {
  # The template said "project-wide monotonic" and called a bare
  # `scripts/mb-req-next-id.sh`, contradicting the command, which uses
  # --spec <topic> through $SKILL_DIR. A new topic could start at project max+1.
  grep -q 'per-spec-local' "$TEMPLATES"
  grep -q -- '--spec <topic>' "$TEMPLATES"
  if grep -q 'IDs are project-wide monotonic' "$TEMPLATES"; then
    echo "templates.md still claims a project-wide REQ namespace"; false
  fi
}

@test "interview_plan: templates.md calls mb-req-next-id through SKILL_DIR" {
  grep -Eq 'bash "\$SKILL_DIR/scripts/mb-req-next-id\.sh"' "$TEMPLATES"
  if grep -Eq '(^|[^/A-Za-z_$-])scripts/mb-req-next-id' "$TEMPLATES"; then
    echo "templates.md still calls the helper by a bare relative path"; false
  fi
}
