#!/usr/bin/env bats
# artifact_check: — svp-interview-upgrade C8 structural validator, `plan` mode
# (Task 1). `transcript` mode is added by Task 4 in the same file.
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

# ─── transcript mode (Task 4, C8 / C4 grammar) ───

# A minimal valid STRICT transcript (no legacy flag needed).
_strict_transcript() {
  cat > "$1" <<'EOF'
# Interview transcript: foo (2026-07-17)

## Q&A

**Q1 (scope).** What is the scope?
**A1.** The scope is X → **D-01**. Отклонено: none

**Финальный гейт.** Anything to add?
**Ответ.** No.
EOF
}

@test "artifact_check: parent live transcript (--legacy-live-fixture) → artifact=ok" {
  run --separate-stderr "$SCRIPT" transcript "$REPO_ROOT/.memory-bank/context/sdd-vision-pipeline-interview.md" --legacy-live-fixture
  [ "$status" -eq 0 ]
  [ "$output" = "artifact=ok open_topics=0" ]
}

@test "artifact_check: slice live transcript (--require-inherited --legacy-live-fixture) → artifact=ok" {
  run --separate-stderr "$SCRIPT" transcript "$REPO_ROOT/.memory-bank/context/svp-interview-upgrade-interview.md" --require-inherited --legacy-live-fixture
  [ "$status" -eq 0 ]
  [ "$output" = "artifact=ok open_topics=0" ]
}

@test "artifact_check: strict minimal transcript → artifact=ok" {
  local f="$BATS_TEST_TMPDIR/t.md"; _strict_transcript "$f"
  run --separate-stderr "$SCRIPT" transcript "$f"
  [ "$status" -eq 0 ]
  [ "$output" = "artifact=ok open_topics=0" ]
}

@test "artifact_check: wrong title form → missing_title (no bad_date)" {
  local f="$BATS_TEST_TMPDIR/t.md"; _strict_transcript "$f"
  printf '# Wrong header\n' > "$f.h"; tail -n +2 "$f" >> "$f.h"; mv "$f.h" "$f"
  run --separate-stderr "$SCRIPT" transcript "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':missing_title$'
  ! echo "$stderr" | grep -q ':bad_date$'
}

@test "artifact_check: calendar-invalid date 2026-02-31 → bad_date" {
  local f="$BATS_TEST_TMPDIR/t.md"; _strict_transcript "$f"
  sed 's/2026-07-17/2026-02-31/' "$f" > "$f.h"; mv "$f.h" "$f"
  run --separate-stderr "$SCRIPT" transcript "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':bad_date$'
}

@test "artifact_check: non-ISO date 17-07-2026 → bad_date not missing_title" {
  local f="$BATS_TEST_TMPDIR/t.md"; _strict_transcript "$f"
  sed 's/2026-07-17/17-07-2026/' "$f" > "$f.h"; mv "$f.h" "$f"
  run --separate-stderr "$SCRIPT" transcript "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':bad_date$'
  ! echo "$stderr" | grep -q ':missing_title$'
}

@test "artifact_check: no Q&A section → missing_qa_section" {
  local f="$BATS_TEST_TMPDIR/t.md"; _strict_transcript "$f"
  sed '/^## Q&A$/d' "$f" > "$f.h"; mv "$f.h" "$f"
  run --separate-stderr "$SCRIPT" transcript "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':missing_qa_section$'
}

@test "artifact_check: duplicate Q&A section → duplicate_qa_section" {
  local f="$BATS_TEST_TMPDIR/t.md"; _strict_transcript "$f"
  printf '\n## Q&A\n' >> "$f"
  run --separate-stderr "$SCRIPT" transcript "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':duplicate_qa_section$'
}

@test "artifact_check: --require-inherited without section → missing_inherited" {
  local f="$BATS_TEST_TMPDIR/t.md"; _strict_transcript "$f"
  run --separate-stderr "$SCRIPT" transcript "$f" --require-inherited
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':missing_inherited$'
}

@test "artifact_check: inherited after Q&A → inherited_after_qa" {
  local f="$BATS_TEST_TMPDIR/t.md"; _strict_transcript "$f"
  printf '\n## Унаследовано\n\nD-00\n' >> "$f"
  run --separate-stderr "$SCRIPT" transcript "$f" --require-inherited
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':inherited_after_qa$'
}

@test "artifact_check: zero Q-blocks → no_questions" {
  local f="$BATS_TEST_TMPDIR/t.md"
  printf '# Interview transcript: foo (2026-07-17)\n\n## Q&A\n\n**Финальный гейт.** add?\n**Ответ.** No.\n' > "$f"
  run --separate-stderr "$SCRIPT" transcript "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':no_questions$'
}

@test "artifact_check: Q2 before Q1 → q_number_out_of_order" {
  local f="$BATS_TEST_TMPDIR/t.md"
  printf '# Interview transcript: foo (2026-07-17)\n\n## Q&A\n\n**Q2 (a).** q?\n**A2.** x → **D-02**. Отклонено: none\n\n**Q1 (b).** q?\n**A1.** y → **D-01**. Отклонено: none\n\n**Финальный гейт.** add?\n**Ответ.** No.\n' > "$f"
  run --separate-stderr "$SCRIPT" transcript "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':q_number_out_of_order$'
}

@test "artifact_check: duplicate Q3 → q_number_duplicate" {
  local f="$BATS_TEST_TMPDIR/t.md"
  printf '# Interview transcript: foo (2026-07-17)\n\n## Q&A\n\n**Q3 (a).** q?\n**A3.** x → **D-03**. Отклонено: none\n\n**Q3 (b).** q?\n**A3.** y → **D-04**. Отклонено: none\n\n**Финальный гейт.** add?\n**Ответ.** No.\n' > "$f"
  run --separate-stderr "$SCRIPT" transcript "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':q_number_duplicate$'
}

@test "artifact_check: strict Q-block without **A<N>.** → answer_missing" {
  local f="$BATS_TEST_TMPDIR/t.md"
  printf '# Interview transcript: foo (2026-07-17)\n\n## Q&A\n\n**Q1 (a).** «quote in the question»?\n→ **D-01**. Отклонено: none\n\n**Финальный гейт.** add?\n**Ответ.** No.\n' > "$f"
  run --separate-stderr "$SCRIPT" transcript "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':answer_missing$'
}

@test "artifact_check: Q-block without a decision → decision_missing" {
  local f="$BATS_TEST_TMPDIR/t.md"
  printf '# Interview transcript: foo (2026-07-17)\n\n## Q&A\n\n**Q1 (a).** q?\n**A1.** x. Отклонено: none\n\n**Финальный гейт.** add?\n**Ответ.** No.\n' > "$f"
  run --separate-stderr "$SCRIPT" transcript "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':decision_missing$'
}

@test "artifact_check: strict decision without Отклонено → rejected_alternatives_missing" {
  local f="$BATS_TEST_TMPDIR/t.md"
  printf '# Interview transcript: foo (2026-07-17)\n\n## Q&A\n\n**Q1 (a).** q?\n**A1.** x → **D-01**.\n\n**Финальный гейт.** add?\n**Ответ.** No.\n' > "$f"
  run --separate-stderr "$SCRIPT" transcript "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':rejected_alternatives_missing$'
}

@test "artifact_check: no final gate → missing_final_gate" {
  local f="$BATS_TEST_TMPDIR/t.md"
  printf '# Interview transcript: foo (2026-07-17)\n\n## Q&A\n\n**Q1 (a).** q?\n**A1.** x → **D-01**. Отклонено: none\n' > "$f"
  run --separate-stderr "$SCRIPT" transcript "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':missing_final_gate$'
}

@test "artifact_check: gate without **Ответ.** → gate_answer_missing" {
  local f="$BATS_TEST_TMPDIR/t.md"
  printf '# Interview transcript: foo (2026-07-17)\n\n## Q&A\n\n**Q1 (a).** q?\n**A1.** x → **D-01**. Отклонено: none\n\n**Финальный гейт.** add?\n' > "$f"
  run --separate-stderr "$SCRIPT" transcript "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':gate_answer_missing$'
}

@test "artifact_check: two gates without круг → gate_round_missing" {
  local f="$BATS_TEST_TMPDIR/t.md"
  printf '# Interview transcript: foo (2026-07-17)\n\n## Q&A\n\n**Q1 (a).** q?\n**A1.** x → **D-01**. Отклонено: none\n\n**Финальный гейт.** add?\n**Ответ.** yes\n\n**Финальный гейт.** more?\n**Ответ.** No.\n' > "$f"
  run --separate-stderr "$SCRIPT" transcript "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':gate_round_missing$'
}

@test "artifact_check: круг 2 before круг 1 → gate_round_out_of_order" {
  local f="$BATS_TEST_TMPDIR/t.md"
  printf '# Interview transcript: foo (2026-07-17)\n\n## Q&A\n\n**Q1 (a).** q?\n**A1.** x → **D-01**. Отклонено: none\n\n**Финальный гейт, круг 2.** add?\n**Ответ.** yes\n\n**Финальный гейт, круг 1.** more?\n**Ответ.** No.\n' > "$f"
  run --separate-stderr "$SCRIPT" transcript "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':gate_round_out_of_order$'
}

@test "artifact_check: --legacy-live-fixture on a non-fixture file → legacy_fixture_forbidden exit 2" {
  local f="$BATS_TEST_TMPDIR/t.md"; _strict_transcript "$f"
  run --separate-stderr "$SCRIPT" transcript "$f" --legacy-live-fixture
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$stderr" = "$f:0:legacy_fixture_forbidden" ]
}

@test "artifact_check: --require-closed with transcript mode → usage error exit 2" {
  local f="$BATS_TEST_TMPDIR/t.md"; _strict_transcript "$f"
  run --separate-stderr "$SCRIPT" transcript "$f" --require-closed
  [ "$status" -eq 2 ]
  [ "$stderr" = "error=usage" ]
}

# ─── legacy-fixture basename spoof (blocker F2) ───

@test "artifact_check: legacy basename spoof in a temp dir → legacy_fixture_forbidden exit 2" {
  # A file whose basename matches a frozen fixture but whose canonical path does
  # NOT must be refused the legacy grammar (rename cannot borrow the relaxation).
  mkdir -p "$BATS_TEST_TMPDIR/ctx"
  local f="$BATS_TEST_TMPDIR/ctx/sdd-vision-pipeline-interview.md"
  printf '# Interview transcript: spoof (2026-07-17)\n\n## Q&A\n\n**Q1 (a).** q?\nОтвет голосом (суть): «да» → **D-01**.\n\n## Отклонённые альтернативы\nОтклонено: x\n\n**Финальный гейт.** add?\n**Ответ.** No.\n' > "$f"
  run --separate-stderr "$SCRIPT" transcript "$f" --legacy-live-fixture
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$stderr" = "$f:0:legacy_fixture_forbidden" ]
}

# ─── strict-grammar tightening (blocker F3) — one fixture per rule ───

@test "artifact_check: malformed Q marker (no parens/dot) → q_malformed" {
  local f="$BATS_TEST_TMPDIR/t.md"
  printf '# Interview transcript: foo (2026-07-17)\n\n## Q&A\n\n**Q1 malformed without parens\n**A1.** ans → **D-01**. Отклонено: none\n\n**Финальный гейт.** add?\n**Ответ.** No.\n' > "$f"
  run --separate-stderr "$SCRIPT" transcript "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':q_malformed$'
}

@test "artifact_check: empty **A<N>.** marker → answer_missing" {
  local f="$BATS_TEST_TMPDIR/t.md"
  printf '# Interview transcript: foo (2026-07-17)\n\n## Q&A\n\n**Q1 (a).** q?\n**A1.**\n→ **D-01**. Отклонено: none\n\n**Финальный гейт.** add?\n**Ответ.** No.\n' > "$f"
  run --separate-stderr "$SCRIPT" transcript "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':answer_missing$'
}

@test "artifact_check: empty Отклонено: marker → rejected_alternatives_missing" {
  local f="$BATS_TEST_TMPDIR/t.md"
  printf '# Interview transcript: foo (2026-07-17)\n\n## Q&A\n\n**Q1 (a).** q?\n**A1.** ans → **D-01**. Отклонено:\n\n**Финальный гейт.** add?\n**Ответ.** No.\n' > "$f"
  run --separate-stderr "$SCRIPT" transcript "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':rejected_alternatives_missing$'
}

@test "artifact_check: malformed final-gate marker → gate_malformed" {
  local f="$BATS_TEST_TMPDIR/t.md"
  printf '# Interview transcript: foo (2026-07-17)\n\n## Q&A\n\n**Q1 (a).** q?\n**A1.** ans → **D-01**. Отклонено: none\n\n**Финальный гейт no terminator\n**Ответ.** No.\n' > "$f"
  run --separate-stderr "$SCRIPT" transcript "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':gate_malformed$'
}

@test "artifact_check: empty **Ответ.** at the gate → gate_answer_missing" {
  local f="$BATS_TEST_TMPDIR/t.md"
  printf '# Interview transcript: foo (2026-07-17)\n\n## Q&A\n\n**Q1 (a).** q?\n**A1.** ans → **D-01**. Отклонено: none\n\n**Финальный гейт.** add?\n**Ответ.**\n' > "$f"
  run --separate-stderr "$SCRIPT" transcript "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':gate_answer_missing$'
}

@test "artifact_check: numbering that starts at Q2 → q_number_not_one" {
  local f="$BATS_TEST_TMPDIR/t.md"
  printf '# Interview transcript: foo (2026-07-17)\n\n## Q&A\n\n**Q2 (a).** q?\n**A2.** ans → **D-02**. Отклонено: none\n\n**Финальный гейт.** add?\n**Ответ.** No.\n' > "$f"
  run --separate-stderr "$SCRIPT" transcript "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':q_number_not_one$'
}

# ─── plan empty-checkbox items (major F5) ───

@test "artifact_check: empty open item - [ ] → empty_topic (not counted as open)" {
  local f="$BATS_TEST_TMPDIR/plan.md"
  printf '## Inherited decisions (do not re-ask)\n\n- none\n\n## Topics\n\n- [ ]\n\n## Discovered mid-interview\n\n- [x] telemetry\n' > "$f"
  run --separate-stderr "$SCRIPT" plan "$f"
  [ "$status" -eq 1 ]
  [ "$output" = "artifact=invalid open_topics=0" ]
  echo "$stderr" | grep -q ':empty_topic$'
}

@test "artifact_check: empty closed item - [x] does not pass --require-closed" {
  local f="$BATS_TEST_TMPDIR/plan.md"
  printf '## Inherited decisions (do not re-ask)\n\n- none\n\n## Topics\n\n- [x]\n\n## Discovered mid-interview\n\n- [x] telemetry\n' > "$f"
  run --separate-stderr "$SCRIPT" plan "$f" --require-closed
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':empty_topic$'
}

# ─── symlinked-invocation fixture spoof (cycle-2 blocker) ───

@test "artifact_check: symlinked invocation cannot relocate the legacy whitelist" {
  # Invoke the validator through a symlink in an attacker tree carrying a weak
  # transcript at fake/.memory-bank/context/<fixture-name>. Physical-path
  # resolution must keep REPO_ROOT at the real repo → spoof forbidden.
  mkdir -p "$BATS_TEST_TMPDIR/fake/scripts" "$BATS_TEST_TMPDIR/fake/.memory-bank/context"
  ln -s "$SCRIPT" "$BATS_TEST_TMPDIR/fake/scripts/mb-interview-artifact-check.sh"
  local spoof="$BATS_TEST_TMPDIR/fake/.memory-bank/context/sdd-vision-pipeline-interview.md"
  printf '# Interview transcript: spoof (2026-07-17)\n\n## Q&A\n\n**Q1 (a).** q?\nОтвет голосом (суть): «да» → **D-01**.\n\n## Отклонённые альтернативы\nОтклонено: x\n\n**Финальный гейт.** add?\n**Ответ.** No.\n' > "$spoof"
  run --separate-stderr "$BATS_TEST_TMPDIR/fake/scripts/mb-interview-artifact-check.sh" transcript "$spoof" --legacy-live-fixture
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  echo "$stderr" | grep -q ':legacy_fixture_forbidden$'
}

# ─── C4 marker grammar: optional tag/round, required separators (cycle-2) ───

@test "artifact_check: **Q1.** q? (optional tag omitted) is valid" {
  local f="$BATS_TEST_TMPDIR/t.md"
  printf '# Interview transcript: foo (2026-07-17)\n\n## Q&A\n\n**Q1.** q?\n**A1.** ans → **D-01**. Отклонено: none\n\n**Финальный гейт.** add?\n**Ответ.** No.\n' > "$f"
  run --separate-stderr "$SCRIPT" transcript "$f"
  [ "$status" -eq 0 ]
  [ "$output" = "artifact=ok open_topics=0" ]
}

@test "artifact_check: empty Q question (marker, no content) → q_malformed" {
  local f="$BATS_TEST_TMPDIR/t.md"
  printf '# Interview transcript: foo (2026-07-17)\n\n## Q&A\n\n**Q1 (tag).**\n**A1.** ans → **D-01**. Отклонено: none\n\n**Финальный гейт.** add?\n**Ответ.** No.\n' > "$f"
  run --separate-stderr "$SCRIPT" transcript "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':q_malformed$'
}

@test "artifact_check: gate marker with arbitrary text → gate_malformed" {
  local f="$BATS_TEST_TMPDIR/t.md"
  printf '# Interview transcript: foo (2026-07-17)\n\n## Q&A\n\n**Q1 (a).** q?\n**A1.** ans → **D-01**. Отклонено: none\n\n**Финальный гейт garbage.** add?\n**Ответ.** No.\n' > "$f"
  run --separate-stderr "$SCRIPT" transcript "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':gate_malformed$'
}

@test "artifact_check: Rejected: only in the question does not satisfy the rule" {
  local f="$BATS_TEST_TMPDIR/t.md"
  printf '# Interview transcript: foo (2026-07-17)\n\n## Q&A\n\n**Q1 (a).** q? Rejected: nothing\n**A1.** ans → **D-01**.\n\n**Финальный гейт.** add?\n**Ответ.** No.\n' > "$f"
  run --separate-stderr "$SCRIPT" transcript "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':rejected_alternatives_missing$'
}

@test "artifact_check: answer marker without the separator space → answer_missing" {
  local f="$BATS_TEST_TMPDIR/t.md"
  printf '# Interview transcript: foo (2026-07-17)\n\n## Q&A\n\n**Q1 (a).** q?\n**A1.**ans → **D-01**. Отклонено: none\n\n**Финальный гейт.** add?\n**Ответ.** No.\n' > "$f"
  run --separate-stderr "$SCRIPT" transcript "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':answer_missing$'
}

@test "artifact_check: gate round optional form **Финальный гейт, круг 2.** stays valid" {
  local f="$BATS_TEST_TMPDIR/t.md"
  printf '# Interview transcript: foo (2026-07-17)\n\n## Q&A\n\n**Q1 (a).** q?\n**A1.** ans → **D-01**. Отклонено: none\n\n**Финальный гейт, круг 1.** add?\n**Ответ.** yes → **D-02**. Отклонено: none\n\n**Финальный гейт, круг 2.** more?\n**Ответ.** No.\n' > "$f"
  run --separate-stderr "$SCRIPT" transcript "$f"
  [ "$status" -eq 0 ]
  [ "$output" = "artifact=ok open_topics=0" ]
}

@test "artifact_check: shellcheck (error severity) and bash -n clean" {
  run shellcheck -x -S error "$SCRIPT"
  [ "$status" -eq 0 ]
  run bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
}
