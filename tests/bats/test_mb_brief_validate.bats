#!/usr/bin/env bats
# brief_validate: — svp-brief C1 structural validator (Task 2).
#
# Name convention (X-05, Eval red-anchor): every @test starts with the positive
# family prefix `brief_validate: `, so `bats <missing-file>` — which emits
# `not ok 1 bats-gather-tests` with the SAME exit 1 as a real failure — cannot
# match the declared anchor `not ok [0-9]+ brief_validate: `, while any real
# failure of a named case does.
#
# Every invalid fixture is derived from the single canonical valid one
# (fixtures/brief/valid.md) by a named mutation, so a case differs from `ok` in
# exactly the property it is named after.

bats_require_minimum_version 1.5.0
load 'lib/assert'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-brief-validate.sh"
  VALID="$REPO_ROOT/tests/bats/fixtures/brief/valid.md"
  MK="$REPO_ROOT/tests/bats/fixtures/brief/mkbrief.py"
}

# derive <dst-name> <mkbrief-op...> — build a variant in the test tmpdir.
derive() {
  local dst="$BATS_TEST_TMPDIR/$1"; shift
  python3 "$MK" "$VALID" "$dst" "$@"
  printf '%s\n' "$dst"
}

@test "brief_validate: ok — valid brief prints brief=ok, empty stderr, exit 0" {
  run --separate-stderr "$SCRIPT" "$VALID"
  [ "$status" -eq 0 ]
  [ "$output" = "brief=ok" ]
  [ "$stderr" = "" ]
}

@test "brief_validate: ok — optional assumptions_note with a value stays valid" {
  local f; f="$(derive an.md --fm-add 'assumptions_note=inferred the goal from the request')"
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 0 ]
  [ "$output" = "brief=ok" ]
  [ "$stderr" = "" ]
}

@test "brief_validate: missing-section — no ## UX gives error=missing_section section=UX" {
  local f; f="$(derive missing.md --drop-section UX)"
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 1 ]
  [ "$output" = "brief=invalid" ]
  [ "$stderr" = "error=missing_section section=UX" ]
}

@test "brief_validate: missing-section — a two-word section name is reported verbatim" {
  local f; f="$(derive missing2.md --drop-section 'Done Criteria')"
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 1 ]
  [ "$output" = "brief=invalid" ]
  [ "$stderr" = "error=missing_section section=Done Criteria" ]
}

@test "brief_validate: duplicate-section — a second ## Scenarios is rejected" {
  local f; f="$(derive dup.md --dup-section Scenarios)"
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 1 ]
  [ "$output" = "brief=invalid" ]
  [ "$stderr" = "error=duplicate_section section=Scenarios" ]
}

@test "brief_validate: empty-essence — a body of blanks and comments is empty" {
  local f; f="$(derive ee.md --empty-body Essence)"
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 1 ]
  [ "$output" = "brief=invalid" ]
  [ "$stderr" = "error=empty_essence section=Essence" ]
}

@test "brief_validate: empty-goal — Goal & Impact must carry a real line" {
  local f; f="$(derive eg.md --empty-body 'Goal & Impact')"
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 1 ]
  [ "$output" = "brief=invalid" ]
  [ "$stderr" = "error=empty_goal section=Goal & Impact" ]
}

@test "brief_validate: frontmatter-invalid — several broken fields collapse into one line" {
  local f; f="$(derive fm.md --fm-set created=17-07-2026 --fm-set status=frozen)"
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 1 ]
  [ "$output" = "brief=invalid" ]
  # Exactly one aggregate line, fields in the C1 key-set order.
  [ "$stderr" = "error=frontmatter_invalid section=frontmatter fields=created,status" ]
}

@test "brief_validate: frontmatter-invalid — a missing required key is reported" {
  local f; f="$(derive fmmiss.md --fm-del inputs)"
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 1 ]
  [ "$output" = "brief=invalid" ]
  [ "$stderr" = "error=frontmatter_invalid section=frontmatter fields=inputs" ]
}

@test "brief_validate: frontmatter-invalid — a duplicated key is a violation" {
  local f; f="$(derive fmdup.md --fm-add topic=checkout-v2)"
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 1 ]
  [ "$output" = "brief=invalid" ]
  [ "$stderr" = "error=frontmatter_invalid section=frontmatter fields=topic" ]
}

@test "brief_validate: frontmatter-invalid — an inputs entry outside inputs/ is rejected" {
  local f; f="$(derive fmpath.md --fm-set inputs=[../../etc/passwd])"
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 1 ]
  [ "$output" = "brief=invalid" ]
  [ "$stderr" = "error=frontmatter_invalid section=frontmatter fields=inputs" ]
}

@test "brief_validate: frontmatter-invalid — an inputs entry escaping via .. is rejected" {
  # The prefix check alone would accept this: it DOES start with `inputs/`.
  # C6 copies from this list, so a traversal here is a write outside the brief.
  local f; f="$(derive fmdotdot.md --fm-set inputs=[inputs/../../etc/passwd])"
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 1 ]
  [ "$output" = "brief=invalid" ]
  [ "$stderr" = "error=frontmatter_invalid section=frontmatter fields=inputs" ]
}

@test "brief_validate: frontmatter-invalid — an absolute inputs entry is rejected" {
  local f; f="$(derive fmabs.md --fm-set inputs=[/etc/passwd])"
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 1 ]
  [ "$output" = "brief=invalid" ]
  [ "$stderr" = "error=frontmatter_invalid section=frontmatter fields=inputs" ]
}

@test "brief_validate: frontmatter-invalid — a bare .. segment inside inputs/ is rejected" {
  local f; f="$(derive fmdotdot2.md --fm-set inputs=[inputs/sub/../../../secrets.env])"
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 1 ]
  [ "$output" = "brief=invalid" ]
  [ "$stderr" = "error=frontmatter_invalid section=frontmatter fields=inputs" ]
}

@test "brief_validate: frontmatter-invalid — a backslash inside an inputs entry is rejected" {
  # Survives the `inputs/` prefix check, so only the separate guard catches it.
  local f; f="$(derive fmbslash.md '--fm-set=inputs=[inputs/a\..\..\b.md]')"
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 1 ]
  [ "$output" = "brief=invalid" ]
  [ "$stderr" = "error=frontmatter_invalid section=frontmatter fields=inputs" ]
}

@test "brief_validate: ok — a '## ' line inside a code fence is not a heading" {
  # A brief that quotes markdown must not be failed for a section it only shows
  # as an example: without fence-awareness this reads as a duplicate ## UX.
  local f; f="$(derive fenced.md)"
  {
    printf '\n## Appendix\n\nAn example of the section we are replacing:\n\n'
    printf '```markdown\n## UX\n## Essence\n```\n'
  } >> "$f"
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 0 ]
  [ "$output" = "brief=ok" ]
  [ "$stderr" = "" ]
}

@test "brief_validate: missing-section — an H3 does not satisfy a required H2" {
  # C1 requires `## `; accepting any `#`-prefix would let ### Essence pass.
  local f; f="$(derive h3.md --demote Essence)"
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 1 ]
  [ "$output" = "brief=invalid" ]
  [ "$stderr" = "error=missing_section section=Essence" ]
}

@test "brief_validate: ok — a blank line between heading and body is not an empty section" {
  # The common markdown shape; reading the body only up to the first blank line
  # would call every such brief empty.
  local f; f="$(derive blank.md --blank-after Essence --blank-after 'Goal & Impact')"
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 0 ]
  [ "$output" = "brief=ok" ]
  [ "$stderr" = "" ]
}

@test "brief_validate: assumptions-note-empty — a whitespace-only value is empty too" {
  local f; f="$(derive anws.md '--fm-add=assumptions_note=   ')"
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 1 ]
  [ "$output" = "brief=invalid" ]
  [ "$stderr" = "error=frontmatter_invalid section=frontmatter fields=assumptions_note" ]
}

@test "brief_validate: frontmatter-invalid — an empty inputs list is allowed" {
  local f; f="$(derive fmempty.md --fm-set inputs=[])"
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 0 ]
  [ "$output" = "brief=ok" ]
  [ "$stderr" = "" ]
}

@test "brief_validate: frontmatter-unknown-key — a key outside the closed set is a violation" {
  local f; f="$(derive fmunk.md --fm-add owner=bob)"
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 1 ]
  [ "$output" = "brief=invalid" ]
  [ "$stderr" = "error=frontmatter_invalid section=frontmatter fields=owner" ]
}

@test "brief_validate: frontmatter-unknown-key — unknown keys follow known ones in file order" {
  local f; f="$(derive fmunk2.md --fm-set status=frozen --fm-add zeta=z --fm-add alpha=a)"
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 1 ]
  [ "$output" = "brief=invalid" ]
  # Known keys in key-set order first, then unknown keys in order of appearance.
  [ "$stderr" = "error=frontmatter_invalid section=frontmatter fields=status,zeta,alpha" ]
}

@test "brief_validate: assumptions-note-empty — present but empty is frontmatter_invalid" {
  local f; f="$(derive an0.md --fm-add assumptions_note=)"
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 1 ]
  [ "$output" = "brief=invalid" ]
  [ "$stderr" = "error=frontmatter_invalid section=frontmatter fields=assumptions_note" ]
}

@test "brief_validate: diagnostics-order — full stdout and stderr compared line by line" {
  local f; f="$(derive combo.md --fm-set created=17-07-2026 --fm-set status=frozen \
    --empty-body Essence --dup-section Essence --drop-section UX)"
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 1 ]

  # stdout is EXACTLY one line, whatever else went wrong.
  [ "$output" = "brief=invalid" ]

  # stderr, in full: the single frontmatter aggregate first, then section
  # diagnostics in the canonical nine-section order, and within one section
  # duplicate_section before empty_essence.
  local expected
  expected="$(printf '%s\n%s\n%s\n%s' \
    'error=frontmatter_invalid section=frontmatter fields=created,status' \
    'error=duplicate_section section=Essence' \
    'error=empty_essence section=Essence' \
    'error=missing_section section=UX')"
  [ "$stderr" = "$expected" ]
}

@test "brief_validate: oversize-warning — 121 lines warn last and keep exit 0" {
  # --pad 122 yields 121 newline-terminated lines: the first size over the limit.
  local f; f="$(derive big.md --pad 122)"
  [ "$(wc -l < "$f")" -eq 121 ]
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 0 ]
  [ "$output" = "brief=ok" ]
  [ "$stderr" = "warning=oversize lines=121 limit=120" ]
}

@test "brief_validate: oversize-warning — the warning is the LAST stderr line, after errors" {
  local f; f="$(derive bigbad.md --drop-section UX --pad 130)"
  [ "$(wc -l < "$f")" -eq 129 ]
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 1 ]
  [ "$output" = "brief=invalid" ]
  local expected
  expected="$(printf '%s\n%s' \
    'error=missing_section section=UX' \
    'warning=oversize lines=129 limit=120')"
  [ "$stderr" = "$expected" ]
}

@test "brief_validate: oversize-within-limit — exactly 120 lines does not warn" {
  local f; f="$(derive edge.md --pad 121)"
  [ "$(wc -l < "$f")" -eq 120 ]
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 0 ]
  [ "$output" = "brief=ok" ]
  [ "$stderr" = "" ]
}

@test "brief_validate: usage — no argument" {
  run --separate-stderr "$SCRIPT"
  [ "$status" -eq 2 ]
  [ "$output" = "" ]
  [ "$stderr" = "error=usage" ]
}

@test "brief_validate: usage — two arguments" {
  run --separate-stderr "$SCRIPT" "$VALID" "$VALID"
  [ "$status" -eq 2 ]
  [ "$output" = "" ]
  [ "$stderr" = "error=usage" ]
}

@test "brief_validate: usage — path does not exist" {
  run --separate-stderr "$SCRIPT" "$BATS_TEST_TMPDIR/nope.md"
  [ "$status" -eq 2 ]
  [ "$output" = "" ]
  [ "$stderr" = "error=usage" ]
}

@test "brief_validate: usage — path is a directory" {
  run --separate-stderr "$SCRIPT" "$BATS_TEST_TMPDIR"
  [ "$status" -eq 2 ]
  [ "$output" = "" ]
  [ "$stderr" = "error=usage" ]
}

@test "brief_validate: usage — unknown flag" {
  run --separate-stderr "$SCRIPT" --strict "$VALID"
  [ "$status" -eq 2 ]
  [ "$output" = "" ]
  [ "$stderr" = "error=usage" ]
}

@test "brief_validate: io — an existing unreadable file is error=io, not error=usage" {
  local f="$BATS_TEST_TMPDIR/noread.md"
  cp "$VALID" "$f"
  chmod 000 "$f"
  run --separate-stderr "$SCRIPT" "$f"
  chmod 644 "$f"
  [ "$status" -eq 2 ]
  [ "$output" = "" ]
  [ "$stderr" = "error=io path=$f" ]
}
