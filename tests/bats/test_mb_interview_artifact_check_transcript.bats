#!/usr/bin/env bats
# artifact_check: — svp-interview-upgrade C8 structural validator, `transcript`
# mode (C4 grammar). Split out of test_mb_interview_artifact_check.bats, which
# keeps `plan` mode; the `artifact_check: ` name prefix is shared so the Eval
# red-anchor `not ok [0-9]+ artifact_check: ` matches either half.

bats_require_minimum_version 1.5.0
load 'lib/discuss_contract'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-interview-artifact-check.sh"
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

# ─── r2 review [15]: duplicate detection must not depend on adjacency ───

@test "artifact_check: NON-adjacent duplicate Q1 → q_number_duplicate, not merely out_of_order" {
  # `Q1, Q2, Q1` used to be reported only as q_number_out_of_order because the
  # duplicate check compared against the IMMEDIATELY preceding number. The
  # declared q_number_duplicate code must fire wherever the repeat sits.
  local f="$BATS_TEST_TMPDIR/t.md"
  printf '# Interview transcript: foo (2026-07-17)\n\n## Q&A\n\n**Q1 (a).** q?\n**A1.** x → **D-01**. Отклонено: none\n\n**Q2 (b).** q?\n**A2.** y → **D-02**. Отклонено: none\n\n**Q1 (c).** q?\n**A1.** z → **D-03**. Отклонено: none\n\n**Финальный гейт.** add?\n**Ответ.** No.\n' > "$f"
  run --separate-stderr "$SCRIPT" transcript "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':q_number_duplicate$'
}

@test "artifact_check: a duplicate takes precedence over the ordering code" {
  # One repeated number must not be reported under both codes — duplicate wins.
  local f="$BATS_TEST_TMPDIR/t.md"
  printf '# Interview transcript: foo (2026-07-17)\n\n## Q&A\n\n**Q1 (a).** q?\n**A1.** x → **D-01**. Отклонено: none\n\n**Q2 (b).** q?\n**A2.** y → **D-02**. Отклонено: none\n\n**Q1 (c).** q?\n**A1.** z → **D-03**. Отклонено: none\n\n**Финальный гейт.** add?\n**Ответ.** No.\n' > "$f"
  run --separate-stderr "$SCRIPT" transcript "$f"
  [ "$status" -eq 1 ]
  [ "$(echo "$stderr" | grep -c ':q_number_duplicate$')" -eq 1 ]
  [ "$(echo "$stderr" | grep -c ':q_number_out_of_order$')" -eq 0 ]
}

# ─── r2 review [12]: the inherited heading must match exactly ───

@test "artifact_check: malformed ## УнаследованоBROKEN does NOT satisfy --require-inherited" {
  # A glued suffix used to satisfy the C4 inherited-section gate via a prefix
  # match, so a transcript with no inherited section at all returned exit 0.
  local f="$BATS_TEST_TMPDIR/t.md"
  printf '# Interview transcript: foo (2026-07-17)\n\n## УнаследованоBROKEN\n\nD-00\n\n## Q&A\n\n**Q1 (a).** q?\n**A1.** x → **D-01**. Отклонено: none\n\n**Финальный гейт.** add?\n**Ответ.** No.\n' > "$f"
  run --separate-stderr "$SCRIPT" transcript "$f" --require-inherited
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':missing_inherited$'
}

@test "artifact_check: ## Унаследовано with trailing text stays valid" {
  # The exact heading, optionally followed by whitespace-separated text, is the
  # legal C4 form — the tightened matcher must not reject it.
  local f="$BATS_TEST_TMPDIR/t.md"
  printf '# Interview transcript: foo (2026-07-17)\n\n## Унаследовано из родителя\n\nD-00\n\n## Q&A\n\n**Q1 (a).** q?\n**A1.** x → **D-01**. Отклонено: none\n\n**Финальный гейт.** add?\n**Ответ.** No.\n' > "$f"
  run --separate-stderr "$SCRIPT" transcript "$f" --require-inherited
  [ "$status" -eq 0 ]
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

@test "artifact_check: malformed Q marker (no parens/dot) → no_questions (C8 enum)" {
  local f="$BATS_TEST_TMPDIR/t.md"
  printf '# Interview transcript: foo (2026-07-17)\n\n## Q&A\n\n**Q1 malformed without parens\n**A1.** ans → **D-01**. Отклонено: none\n\n**Финальный гейт.** add?\n**Ответ.** No.\n' > "$f"
  run --separate-stderr "$SCRIPT" transcript "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':no_questions$'
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

@test "artifact_check: malformed final-gate marker → missing_final_gate (C8 enum)" {
  local f="$BATS_TEST_TMPDIR/t.md"
  printf '# Interview transcript: foo (2026-07-17)\n\n## Q&A\n\n**Q1 (a).** q?\n**A1.** ans → **D-01**. Отклонено: none\n\n**Финальный гейт no terminator\n**Ответ.** No.\n' > "$f"
  run --separate-stderr "$SCRIPT" transcript "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':missing_final_gate$'
}

@test "artifact_check: empty **Ответ.** at the gate → gate_answer_missing" {
  local f="$BATS_TEST_TMPDIR/t.md"
  printf '# Interview transcript: foo (2026-07-17)\n\n## Q&A\n\n**Q1 (a).** q?\n**A1.** ans → **D-01**. Отклонено: none\n\n**Финальный гейт.** add?\n**Ответ.**\n' > "$f"
  run --separate-stderr "$SCRIPT" transcript "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':gate_answer_missing$'
}

@test "artifact_check: numbering that starts at Q2 → q_number_out_of_order (C8 enum)" {
  local f="$BATS_TEST_TMPDIR/t.md"
  printf '# Interview transcript: foo (2026-07-17)\n\n## Q&A\n\n**Q2 (a).** q?\n**A2.** ans → **D-02**. Отклонено: none\n\n**Финальный гейт.** add?\n**Ответ.** No.\n' > "$f"
  run --separate-stderr "$SCRIPT" transcript "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':q_number_out_of_order$'
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

@test "artifact_check: empty Q question (marker, no content) → no_questions (C8 enum)" {
  local f="$BATS_TEST_TMPDIR/t.md"
  printf '# Interview transcript: foo (2026-07-17)\n\n## Q&A\n\n**Q1 (tag).**\n**A1.** ans → **D-01**. Отклонено: none\n\n**Финальный гейт.** add?\n**Ответ.** No.\n' > "$f"
  run --separate-stderr "$SCRIPT" transcript "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':no_questions$'
}

@test "artifact_check: gate marker with arbitrary text → missing_final_gate (C8 enum)" {
  local f="$BATS_TEST_TMPDIR/t.md"
  printf '# Interview transcript: foo (2026-07-17)\n\n## Q&A\n\n**Q1 (a).** q?\n**A1.** ans → **D-01**. Отклонено: none\n\n**Финальный гейт garbage.** add?\n**Ответ.** No.\n' > "$f"
  run --separate-stderr "$SCRIPT" transcript "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':missing_final_gate$'
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
# ─── Q&A section scoping (review [8], contract C4) ───

@test "artifact_check: Q-block before the ## Q&A section → invalid, not artifact=ok" {
  # C4 requires the Q/A blocks to live INSIDE the canonical `## Q&A` section.
  # A transcript with a complete-looking block above an empty `## Q&A` used to
  # pass as `artifact=ok`.
  local f="$BATS_TEST_TMPDIR/t.md"
  printf '# Interview transcript: foo (2026-07-17)\n\n**Q1 (a).** q?\n**A1.** ans → **D-01**. Отклонено: none\n\n**Финальный гейт.** add?\n**Ответ.** No.\n\n## Q&A\n' > "$f"
  run --separate-stderr "$SCRIPT" transcript "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':no_questions$'
}

@test "artifact_check: final gate after the ## Q&A section ends → missing_final_gate" {
  local f="$BATS_TEST_TMPDIR/t.md"
  printf '# Interview transcript: foo (2026-07-17)\n\n## Q&A\n\n**Q1 (a).** q?\n**A1.** ans → **D-01**. Отклонено: none\n\n## Appendix\n\n**Финальный гейт.** add?\n**Ответ.** No.\n' > "$f"
  run --separate-stderr "$SCRIPT" transcript "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':missing_final_gate$'
}

@test "artifact_check: Q-block after the ## Q&A section ends is not counted" {
  local f="$BATS_TEST_TMPDIR/t.md"
  printf '# Interview transcript: foo (2026-07-17)\n\n## Q&A\n\n## Appendix\n\n**Q1 (a).** q?\n**A1.** ans → **D-01**. Отклонено: none\n\n**Финальный гейт.** add?\n**Ответ.** No.\n' > "$f"
  run --separate-stderr "$SCRIPT" transcript "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':no_questions$'
}
@test "artifact_check: shellcheck (error severity) and bash -n clean" {
  run shellcheck -x -S error "$SCRIPT"
  [ "$status" -eq 0 ]
  run bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
}
