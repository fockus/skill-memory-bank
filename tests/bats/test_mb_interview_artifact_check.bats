#!/usr/bin/env bats
# artifact_check: — svp-interview-upgrade C8 structural validator, `plan` mode.
# `transcript` mode lives in test_mb_interview_artifact_check_transcript.bats;
# both files keep the `artifact_check: ` test-name prefix so the Eval red-anchor
# `not ok [0-9]+ artifact_check: ` still matches either half.
#
# Name convention: every @test starts with `artifact_check: ` — part of the Eval
# red-anchor. `bats` on a missing file emits `not ok 1 bats-gather-tests` (same
# exit 1), so an exit-only anchor would misread "file absent" as red.

bats_require_minimum_version 1.5.0
load 'lib/discuss_contract'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-interview-artifact-check.sh"
}

_valid_closed_plan() {
  cat > "$1" <<'EOF'
## Inherited decisions (do not re-ask)

- Storage layout is fixed (D-03).

## Topics

- [x] purpose
- [x] edge cases

## Discovered mid-interview

- [x] telemetry
EOF
}

_valid_open_plan() {
  cat > "$1" <<'EOF'
## Inherited decisions (do not re-ask)

- none

## Topics

- [ ] purpose
- [x] edge cases

## Discovered mid-interview

- [ ] telemetry
EOF
}

@test "artifact_check: the plan validator script is present" {
  run assert_script_present scripts/mb-interview-artifact-check.sh
  [ "$status" -eq 0 ]
}

@test "artifact_check: valid closed plan → artifact=ok open_topics=0 exit 0" {
  local f="$BATS_TEST_TMPDIR/plan.md"; _valid_closed_plan "$f"
  run --separate-stderr "$SCRIPT" plan "$f"
  [ "$status" -eq 0 ]
  [ "$output" = "artifact=ok open_topics=0" ]
}

@test "artifact_check: valid plan with open topics (no --require-closed) → ok" {
  local f="$BATS_TEST_TMPDIR/plan.md"; _valid_open_plan "$f"
  run --separate-stderr "$SCRIPT" plan "$f"
  [ "$status" -eq 0 ]
  [ "$output" = "artifact=ok open_topics=2" ]
}

@test "artifact_check: open topics with --require-closed → invalid exit 1" {
  local f="$BATS_TEST_TMPDIR/plan.md"; _valid_open_plan "$f"
  run --separate-stderr "$SCRIPT" plan "$f" --require-closed
  [ "$status" -eq 1 ]
  [ "$output" = "artifact=invalid open_topics=2" ]
  echo "$stderr" | grep -q ":open_topics$"
}

@test "artifact_check: missing required section → exit 1 + missing_section" {
  local f="$BATS_TEST_TMPDIR/plan.md"
  printf '## Topics\n\n- [x] a\n\n## Discovered mid-interview\n\n- [x] b\n' > "$f"
  run --separate-stderr "$SCRIPT" plan "$f"
  [ "$status" -eq 1 ]
  [ "$output" = "artifact=invalid open_topics=0" ]
  echo "$stderr" | grep -q ":missing_section$"
}

@test "artifact_check: sections out of order → section_out_of_order" {
  local f="$BATS_TEST_TMPDIR/plan.md"
  printf '## Topics\n\n- [x] a\n\n## Inherited decisions (do not re-ask)\n\n- x\n\n## Discovered mid-interview\n\n- [x] b\n' > "$f"
  run --separate-stderr "$SCRIPT" plan "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ":section_out_of_order$"
}

@test "artifact_check: bad bullet under Topics → bad_bullet" {
  local f="$BATS_TEST_TMPDIR/plan.md"
  printf '## Inherited decisions (do not re-ask)\n\n- none\n\n## Topics\n\n* purpose\n\n## Discovered mid-interview\n\n- [x] b\n' > "$f"
  run --separate-stderr "$SCRIPT" plan "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ":bad_bullet$"
}

@test "artifact_check: missing file → exit 2 unreadable, stdout empty" {
  run --separate-stderr "$SCRIPT" plan "$BATS_TEST_TMPDIR/nope.md"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  echo "$stderr" | grep -q ":0:unreadable$"
}

@test "artifact_check: --require-inherited with plan mode → usage error exit 2" {
  local f="$BATS_TEST_TMPDIR/plan.md"; _valid_closed_plan "$f"
  run --separate-stderr "$SCRIPT" plan "$f" --require-inherited
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$stderr" = "error=usage" ]
}

@test "artifact_check: unknown flag → usage error, stdout empty, stderr error=usage" {
  local f="$BATS_TEST_TMPDIR/plan.md"; _valid_closed_plan "$f"
  run --separate-stderr "$SCRIPT" plan "$f" --bogus
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$stderr" = "error=usage" ]
}

@test "artifact_check: no mode argument → usage error exit 2" {
  run --separate-stderr "$SCRIPT"
  [ "$status" -eq 2 ]
  [ "$stderr" = "error=usage" ]
}
# ─── plan empty-checkbox items (major F5) ───

@test "artifact_check: empty open item - [ ] → bad_bullet (C8 enum, not counted as open)" {
  local f="$BATS_TEST_TMPDIR/plan.md"
  printf '## Inherited decisions (do not re-ask)\n\n- none\n\n## Topics\n\n- [ ]\n\n## Discovered mid-interview\n\n- [x] telemetry\n' > "$f"
  run --separate-stderr "$SCRIPT" plan "$f"
  [ "$status" -eq 1 ]
  [ "$output" = "artifact=invalid open_topics=0" ]
  echo "$stderr" | grep -q ':bad_bullet$'
}

@test "artifact_check: empty closed item - [x] → bad_bullet (C8 enum)" {
  local f="$BATS_TEST_TMPDIR/plan.md"
  printf '## Inherited decisions (do not re-ask)\n\n- none\n\n## Topics\n\n- [x]\n\n## Discovered mid-interview\n\n- [x] telemetry\n' > "$f"
  run --separate-stderr "$SCRIPT" plan "$f" --require-closed
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':bad_bullet$'
}
# ─── plan: every non-checkbox row under Topics/Discovered (r2 review [1]) ───
#
# The close gate used to inspect ONLY column-1 bullet markers, so plain prose, a
# numbered item, or an INDENTED `- [ ]` slipped through: the plan reported
# `artifact=ok open_topics=0` under --require-closed while an unclosed theme was
# sitting in the file. That silently bypasses REQ-002, so every nonblank row that
# is not an exact `- [ ]` / `- [x]` item is now bad_bullet.

@test "artifact_check: plain prose row under Topics → bad_bullet" {
  local f="$BATS_TEST_TMPDIR/plan.md"
  printf '## Inherited decisions (do not re-ask)\n\n- none\n\n## Topics\n\n- [x] purpose\nSecurity review pending\n\n## Discovered mid-interview\n' > "$f"
  run --separate-stderr "$SCRIPT" plan "$f" --require-closed
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':bad_bullet$'
}

@test "artifact_check: numbered item under Topics → bad_bullet" {
  local f="$BATS_TEST_TMPDIR/plan.md"
  printf '## Inherited decisions (do not re-ask)\n\n- none\n\n## Topics\n\n- [x] purpose\n1. numbered open item\n\n## Discovered mid-interview\n' > "$f"
  run --separate-stderr "$SCRIPT" plan "$f" --require-closed
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':bad_bullet$'
}

@test "artifact_check: INDENTED open checkbox under Topics → bad_bullet, never silently closed" {
  local f="$BATS_TEST_TMPDIR/plan.md"
  printf '## Inherited decisions (do not re-ask)\n\n- none\n\n## Topics\n\n- [x] purpose\n  - [ ] indented security\n\n## Discovered mid-interview\n' > "$f"
  run --separate-stderr "$SCRIPT" plan "$f" --require-closed
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':bad_bullet$'
}

@test "artifact_check: indented row under Discovered → bad_bullet" {
  local f="$BATS_TEST_TMPDIR/plan.md"
  printf '## Inherited decisions (do not re-ask)\n\n- none\n\n## Topics\n\n- [x] purpose\n\n## Discovered mid-interview\n\n\t- [ ] tabbed theme\n' > "$f"
  run --separate-stderr "$SCRIPT" plan "$f" --require-closed
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':bad_bullet$'
}

@test "artifact_check: the whole malformed-row set together never reports ok" {
  # The exact reproduction from the round-2 review: a plan that used to return
  # `artifact=ok open_topics=0` under --require-closed.
  local f="$BATS_TEST_TMPDIR/plan.md"
  printf '## Inherited decisions (do not re-ask)\n\n## Topics\n- [x] Closed one\nSecurity review pending\n1. Numbered open item\n  - [ ] Indented security\n\n## Discovered mid-interview\n' > "$f"
  run --separate-stderr "$SCRIPT" plan "$f" --require-closed
  [ "$status" -eq 1 ]
  [ "$output" != "artifact=ok open_topics=0" ]
  [ "$(echo "$stderr" | grep -c ':bad_bullet$')" -eq 3 ]
}

@test "artifact_check: blank and whitespace-only rows stay legal inside Topics" {
  # The strict rule must not reject the ordinary blank separators the template
  # itself uses, otherwise every valid plan breaks.
  local f="$BATS_TEST_TMPDIR/plan.md"
  printf '## Inherited decisions (do not re-ask)\n\n- none\n\n## Topics\n\n- [x] purpose\n   \n- [x] edge cases\n\n## Discovered mid-interview\n\n- [x] telemetry\n' > "$f"
  run --separate-stderr "$SCRIPT" plan "$f" --require-closed
  [ "$status" -eq 0 ]
  [ "$output" = "artifact=ok open_topics=0" ]
}

# ─── C8 closed reason-code enum (review [9]) ───

# The normative C8 enums, verbatim from
# .memory-bank/specs/svp-interview-upgrade/design.md § C8. A consumer that
# validates a closed enum breaks on any code outside these lists, so the
# validator may never invent one.
_c8_plan_reasons() {
  printf '%s\n' missing_section section_out_of_order bad_bullet open_topics
}

_c8_transcript_reasons() {
  printf '%s\n' missing_title bad_date missing_qa_section duplicate_qa_section \
    missing_inherited inherited_after_qa no_questions q_number_out_of_order \
    q_number_duplicate answer_missing decision_missing \
    rejected_alternatives_missing missing_final_gate gate_answer_missing \
    gate_round_missing gate_round_out_of_order legacy_fixture_forbidden \
    duplicate_inherited
}
# r4 review [8]: these two lists are a CONVENIENCE COPY, and a copy that can be
# hand-extended is not a contract — `duplicate_inherited` was added here while
# the spec did not declare it, so the test blessed output no consumer could
# accept. The test below makes the copy unable to outrun the spec: every code
# named here must be declared in design.md. Add the code to the SPEC first.
_design_md() { printf '%s' "$REPO_ROOT/.memory-bank/specs/svp-interview-upgrade/design.md"; }

@test "artifact_check: the local C8 enum copy never extends the spec" {
  # Anti-vacuity: a code the spec does not declare must be detectable.
  printf '%s\n' 'totally_invented_code' | grep -qx 'totally_invented_code'
  local declared undeclared
  declared="$(grep -oE '`[a-z][a-z0-9_]+`' "$(_design_md)" | tr -d '`' | sort -u)"
  [ -n "$declared" ]
  undeclared="$(comm -23 \
    <( { _c8_plan_reasons; _c8_transcript_reasons; } | sort -u ) \
    <(printf '%s\n' "$declared"))"
  [ -z "$undeclared" ] || {
    echo "reason codes named in this test but NOT declared in design.md: $undeclared"
    echo "add them to the spec first — a test may not extend the contract it checks"
    false; }
}


@test "artifact_check: every reason code in the source belongs to the closed C8 enum" {
  # Static guard: scrape every finding literal the validator can emit and prove
  # membership in the union of the two declared enums. Catches a newly invented
  # code the moment it is written, not only when a fixture happens to hit it.
  local allowed emitted bad
  allowed="$( { _c8_plan_reasons; _c8_transcript_reasons; printf 'unreadable\n'; } | sort -u )"
  emitted="$(grep -E '"F ' "$SCRIPT" \
    | grep -oE '[a-z_]+(\\n)?"' | tr -d '"' | sed 's/\\n$//' | sort -u)"
  [ -n "$emitted" ]
  bad="$(comm -23 <(printf '%s\n' "$emitted") <(printf '%s\n' "$allowed"))"
  [ -z "$bad" ] || { echo "non-contract reason codes: $bad"; false; }
}

@test "artifact_check: a corpus of invalid plans emits only C8 plan reason codes" {
  local allowed d f seen bad
  allowed="$(_c8_plan_reasons | sort -u)"
  d="$BATS_TEST_TMPDIR/corpus"; mkdir -p "$d"
  printf '## Topics\n\n- [x] a\n' > "$d/1.md"
  printf '## Topics\n\n- [x] a\n\n## Inherited decisions (do not re-ask)\n\n- x\n\n## Discovered mid-interview\n\n- [x] b\n' > "$d/2.md"
  printf '## Inherited decisions (do not re-ask)\n\n- none\n\n## Topics\n\n* purpose\n\n## Discovered mid-interview\n\n- [x] b\n' > "$d/3.md"
  printf '## Inherited decisions (do not re-ask)\n\n- none\n\n## Topics\n\n- [ ]\n\n## Discovered mid-interview\n\n- [x] b\n' > "$d/4.md"
  printf '## Inherited decisions (do not re-ask)\n\n- none\n\n## Topics\n\n- [ ] open\n\n## Discovered mid-interview\n\n- [x] b\n' > "$d/5.md"
  seen=""
  for f in "$d"/*.md; do
    seen="$seen$("$SCRIPT" plan "$f" --require-closed 2>&1 >/dev/null | sed 's/.*://')
"
  done
  seen="$(printf '%s' "$seen" | grep -v '^$' | sort -u)"
  [ -n "$seen" ]
  bad="$(comm -23 <(printf '%s\n' "$seen") <(printf '%s\n' "$allowed"))"
  [ -z "$bad" ] || { echo "non-contract plan reason codes: $bad"; false; }
}
# ─── duplicated required section must not bypass the close-gate (review [2]) ───

@test "artifact_check: duplicate ## Topics section → invalid, close-gate not bypassed" {
  # REQ-002/C2: a second `## Topics` carrying an open item used to sail through
  # --require-closed as `artifact=ok open_topics=0` — the whole point of the gate.
  local f="$BATS_TEST_TMPDIR/plan.md"
  printf '## Inherited decisions (do not re-ask)\n\n- none\n\n## Topics\n\n- [x] closed\n\n## Discovered mid-interview\n\n- [x] done\n\n## Topics\n\n- [ ] STILL OPEN\n' > "$f"
  run --separate-stderr "$SCRIPT" plan "$f" --require-closed
  [ "$status" -eq 1 ]
  [ "$output" = "artifact=invalid open_topics=1" ]
  echo "$stderr" | grep -q ':section_out_of_order$'
  echo "$stderr" | grep -q ':open_topics$'
}

@test "artifact_check: duplicate ## Discovered section is rejected even when fully closed" {
  local f="$BATS_TEST_TMPDIR/plan.md"
  printf '## Inherited decisions (do not re-ask)\n\n- none\n\n## Topics\n\n- [x] a\n\n## Discovered mid-interview\n\n- [x] b\n\n## Discovered mid-interview\n\n- [x] c\n' > "$f"
  run --separate-stderr "$SCRIPT" plan "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':section_out_of_order$'
}

@test "artifact_check: duplicate ## Inherited section is rejected" {
  local f="$BATS_TEST_TMPDIR/plan.md"
  printf '## Inherited decisions (do not re-ask)\n\n- none\n\n## Topics\n\n- [x] a\n\n## Discovered mid-interview\n\n- [x] b\n\n## Inherited decisions (do not re-ask)\n\n- extra\n' > "$f"
  run --separate-stderr "$SCRIPT" plan "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':section_out_of_order$'
}
@test "artifact_check: shellcheck (error severity) and bash -n clean" {
  run shellcheck -x -S error "$SCRIPT"
  [ "$status" -eq 0 ]
  run bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
}

# ─── no section may hide items from the close gate (r3 review [4]) ───

@test "artifact_check: an UNKNOWN level-2 section with an open item fails the close gate" {
  # scan_section stopped at any `## `, and an unrecognised heading was never
  # rejected — so parking `- [ ] security` under `## Hidden unresolved themes`
  # returned `artifact=ok open_topics=0` under --require-closed.
  local f="$BATS_TEST_TMPDIR/plan.md"
  printf '## Inherited decisions (do not re-ask)\n\n## Topics\n\n- [x] purpose\n\n## Hidden unresolved themes\n\n- [ ] security\n\n## Discovered mid-interview\n\n- [x] telemetry\n' > "$f"
  run --separate-stderr "$SCRIPT" plan "$f" --require-closed
  [ "$status" -eq 1 ] || { echo "unknown section bypassed the gate: $output"; false; }
  [ "$output" != "artifact=ok open_topics=0" ]
}

@test "artifact_check: an unknown level-2 section is rejected even when fully closed" {
  local f="$BATS_TEST_TMPDIR/plan.md"
  printf '## Inherited decisions (do not re-ask)\n\n## Topics\n\n- [x] purpose\n\n## Notes\n\nfree text\n\n## Discovered mid-interview\n\n- [x] telemetry\n' > "$f"
  run --separate-stderr "$SCRIPT" plan "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':section_out_of_order$'
}

@test "artifact_check: the three canonical sections alone still validate" {
  local f="$BATS_TEST_TMPDIR/plan.md"; _valid_closed_plan "$f"
  run --separate-stderr "$SCRIPT" plan "$f" --require-closed
  [ "$status" -eq 0 ]
  [ "$output" = "artifact=ok open_topics=0" ]
}

# ─── r4 [6]: the checkbox enum is exactly `- [ ]` and `- [x]` ──────────────

@test "artifact_check: an UPPERCASE - [X] item is bad_bullet, never a closed topic" {
  # C8 declares only `- [ ]` and `- [x]`. `- [X]` was accepted by the regex, so a
  # plan whose single topic used it passed --require-closed with open_topics=0.
  local f="$BATS_TEST_TMPDIR/plan.md"
  printf '## Inherited decisions (do not re-ask)\n\n## Topics\n\n- [X] scope\n\n## Discovered mid-interview\n\n- [x] t\n' > "$f"
  run --separate-stderr "$SCRIPT" plan "$f" --require-closed
  [ "$status" -eq 1 ] || { echo "uppercase checkbox passed the close gate: $output"; false; }
  echo "$stderr" | grep -q ':bad_bullet$'
}

@test "artifact_check: a lowercase - [x] item is still accepted" {
  local f="$BATS_TEST_TMPDIR/plan.md"
  printf '## Inherited decisions (do not re-ask)\n\n## Topics\n\n- [x] scope\n\n## Discovered mid-interview\n\n- [x] t\n' > "$f"
  run --separate-stderr "$SCRIPT" plan "$f" --require-closed
  [ "$status" -eq 0 ]
}

# ─── r4 [7]: a plan with no topics at all is not a closed plan ─────────────

@test "artifact_check: an EMPTY Topics section fails the close gate" {
  # REQ-001 requires a plan that LISTS the themes to close; three headings and
  # no items passed --require-closed with artifact=ok open_topics=0, so
  # generation was permitted with nothing ever planned.
  local f="$BATS_TEST_TMPDIR/plan.md"
  printf '## Inherited decisions (do not re-ask)\n\n## Topics\n\n## Discovered mid-interview\n' > "$f"
  run --separate-stderr "$SCRIPT" plan "$f" --require-closed
  [ "$status" -eq 1 ] || { echo "empty Topics passed the close gate: $output"; false; }
  echo "$stderr" | grep -q ':missing_section$' \
    || { echo "no declared reason for an empty Topics: $stderr"; false; }
}

@test "artifact_check: an empty Topics section is invalid even without --require-closed" {
  local f="$BATS_TEST_TMPDIR/plan.md"
  printf '## Inherited decisions (do not re-ask)\n\n## Topics\n\n## Discovered mid-interview\n' > "$f"
  run --separate-stderr "$SCRIPT" plan "$f"
  [ "$status" -eq 1 ]
}

@test "artifact_check: an empty DISCOVERED section stays legal" {
  # Only Topics must be non-empty: Discovered legitimately starts empty and only
  # fills as themes surface mid-interview.
  local f="$BATS_TEST_TMPDIR/plan.md"
  printf '## Inherited decisions (do not re-ask)\n\n## Topics\n\n- [x] scope\n\n## Discovered mid-interview\n' > "$f"
  run --separate-stderr "$SCRIPT" plan "$f" --require-closed
  [ "$status" -eq 0 ] || { echo "an empty Discovered section was rejected: $output"; false; }
}

# ═══ r5 review [2]: the verdict must be attributable to specific BYTES ══════
#
# The close gate is `check → (the agent renders) → publish`, three separate
# steps against one shared `<bank>/tmp/interview-plan-<topic>.md`. A second
# `/mb discuss` on the same topic can install an OPEN plan between them, and the
# gate's exit 0 then described a file that no longer exists. A verdict nobody
# can tie to bytes cannot be re-checked, so `--print-digest` reports the sha256
# of exactly what was validated, and commands/discuss.md compares it before it
# generates anything.

_sha256() {
  MB_F="$1" python3 -c 'import hashlib, os, sys
h = hashlib.sha256()
with open(os.environ["MB_F"], "rb") as fh:
    for chunk in iter(lambda: fh.read(65536), b""):
        h.update(chunk)
sys.stdout.write(h.hexdigest())'
}

@test "artifact_check: --print-digest reports the sha256 of the validated file" {
  local f="$BATS_TEST_TMPDIR/plan.md"; _valid_closed_plan "$f"
  run --separate-stderr "$SCRIPT" plan "$f" --require-closed --print-digest
  [ "$status" -eq 0 ]
  [ "$output" = "artifact=ok open_topics=0 digest=$(_sha256 "$f")" ] \
    || { echo "unexpected stdout: $output"; false; }
}

@test "artifact_check: without --print-digest the stdout contract is unchanged" {
  local f="$BATS_TEST_TMPDIR/plan.md"; _valid_closed_plan "$f"
  run --separate-stderr "$SCRIPT" plan "$f" --require-closed
  [ "$status" -eq 0 ]
  [ "$output" = "artifact=ok open_topics=0" ]
}

@test "artifact_check: an INVALID plan still reports the digest it judged" {
  # The repair loop needs the same binding: reinstall, re-gate, compare.
  local f="$BATS_TEST_TMPDIR/plan.md"
  printf '## Inherited decisions (do not re-ask)\n\n## Topics\n\n- [ ] open\n\n## Discovered mid-interview\n' > "$f"
  run --separate-stderr "$SCRIPT" plan "$f" --require-closed --print-digest
  [ "$status" -eq 1 ]
  [ "$output" = "artifact=invalid open_topics=1 digest=$(_sha256 "$f")" ] \
    || { echo "unexpected stdout: $output"; false; }
}

@test "artifact_check: the digest describes the PARSED bytes, not a later re-read" {
  # A digest taken by re-opening the path after the parse would describe the
  # file the competing run installed, and the caller's CAS check would compare
  # two values that were never both true — the same TOCTOU one level up.
  # `awk` is interposed so the swap lands exactly when parsing ends.
  local f="$BATS_TEST_TMPDIR/plan.md"; _valid_closed_plan "$f"
  local original; original="$(_sha256 "$f")"
  local bin="$BATS_TEST_TMPDIR/bin-digest"; mkdir -p "$bin"
  printf '## Topics\n\n- [ ] a competing run installed this\n' > "$BATS_TEST_TMPDIR/other-plan.md"

  local realawk; realawk="$(command -v awk)"
  cat > "$bin/awk" <<EOF
#!/usr/bin/env bash
rc=0
"$realawk" "\$@" || rc=\$?
if [ ! -e "$BATS_TEST_TMPDIR/.digest-swapped" ]; then
  : > "$BATS_TEST_TMPDIR/.digest-swapped"
  cp "$BATS_TEST_TMPDIR/other-plan.md" "$f" 2>/dev/null || true
fi
exit \$rc
EOF
  chmod +x "$bin/awk"

  PATH="$bin:$PATH" run --separate-stderr "$SCRIPT" plan "$f" --require-closed --print-digest
  [ -e "$BATS_TEST_TMPDIR/.digest-swapped" ] || { echo "the awk interposer never fired"; false; }
  [ "$status" -eq 0 ] || { echo "the verdict followed the swapped file: $stderr"; false; }
  [ "$output" = "artifact=ok open_topics=0 digest=$original" ] \
    || { echo "the digest is not the validated file's: $output"; false; }
}
