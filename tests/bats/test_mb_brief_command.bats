#!/usr/bin/env bats
# brief_cmd: — svp-brief C6 helper (scripts/mb-brief.sh) + C7 prompt contract
# of commands/brief.md (Task 1).
#
# Two halves, both deterministic and both without an LLM:
#   * the FILE half drives the helper directly — validation, the exists gate,
#     the scan aggregation, staging and the single atomic publish;
#   * the PROMPT half asserts the normative clauses of commands/brief.md through
#     the S1-C9 harness (`assert_clause` + `assert_clause_load_bearing`). A bare
#     `grep -q <word>` is forbidden as an assertion gate (BRIEF-006, R2-003).
#
# Name convention (X-05, Eval red-anchor): every @test starts with `brief_cmd: `.

bats_require_minimum_version 1.5.0
load 'lib/assert'
load 'lib/discuss_contract'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  BRIEF="$REPO_ROOT/scripts/mb-brief.sh"
  VALID="$REPO_ROOT/tests/bats/fixtures/brief/valid.md"
  MK="$REPO_ROOT/tests/bats/fixtures/brief/mkbrief.py"
  CMD="$REPO_ROOT/commands/brief.md"
  BANK="$BATS_TEST_TMPDIR/bank"
  SK="sk-ant-api03ABCDEFGHIJKLMNOP"
  mkdir -p "$BANK/tmp" "$BANK/briefs"

  # ── C7 clause registry (design C7). Registered from THIS consumer file;
  # the S1 harness itself is never edited (cross-slice request X-01).
  MB_DISCUSS_CLAUSES+=("brief-questions-unclear|mb_section|Light questions|no more than five clarifying questions[^.]*only when the essence or the goal cannot be extracted[^.]*and .--auto. was not passed[^.]*before generating|clarifying question|s/no more than five/as many as it takes/|REQ-003")
  MB_DISCUSS_CLAUSES+=("brief-questions-skipped-when-clear|mb_section|Light questions|essence and the goal are clear[^.]*the question step is skipped and the brief is generated immediately|question step|s/is skipped and the brief is generated immediately/is performed anyway/|REQ-004")
  MB_DISCUSS_CLAUSES+=("brief-auto-skips-questions|mb_section|Light questions|--auto. always skips the question gate and requires a non-empty .assumptions_note|--auto|s/ always skips/ sometimes skips/|REQ-004")
  MB_DISCUSS_CLAUSES+=("brief-request-source-xor|mb_section|Request source|Passing both .--request. and .--request-file. is .error=usage[^.]*only the text of the user message|--request-file|s/only the text of the user message/any nearby text/|REQ-001")
  MB_DISCUSS_CLAUSES+=("brief-request-inline-nonempty|mb_section|Request source|--request. whose value has no non-whitespace character is .error=request_empty. before the candidate is written|request_empty|s/no non-whitespace character/no character/|REQ-001")
  MB_DISCUSS_CLAUSES+=("brief-request-file-guard|mb_section|Request source|--request-file. that is missing, a symlink, a directory or contains .[.][.]. is .error=request_unreadable path=|request_unreadable|s/, a symlink, a directory or contains .[.][.]./ /|REQ-001")
  # `[^;]*`, not `[^.]*`: the candidate path itself contains dots.
  MB_DISCUSS_CLAUSES+=("brief-candidate-before-helper|mb_section|Generation|complete brief text[^;]*is written to the candidate[^;]*before [^;]*scripts/mb-brief.sh. create. is invoked|candidate|s#before [^;]*scripts/mb-brief.sh. create. is invoked#after that helper has run#|REQ-001")
  MB_DISCUSS_CLAUSES+=("brief-helper-publish|mb_section|Publication|only path that publishes[^.]*writing into .briefs/. directly is forbidden|publish|s/only path that publishes/usual path that publishes/|REQ-001")
  MB_DISCUSS_CLAUSES+=("brief-attachments-links|mb_section|Generation|Attachments lists every copied source as a relative link .inputs/<basename>|Attachments|s/ as a relative link .inputs.<basename>.//|REQ-008")
  MB_DISCUSS_CLAUSES+=("brief-handoff-line|mb_section|Handoff|final line of the output is exactly ./mb discuss <topic>|discuss|s/final line of the output is exactly/output mentions somewhere/|REQ-005")
}

# cand <name> [mkbrief-op...] — a candidate brief in the bank's tmp/.
cand() {
  local dst="$BANK/tmp/$1"; shift
  python3 "$MK" "$VALID" "$dst" "$@"
  printf '%s\n' "$dst"
}

# src <name> <content> — a source document offered as --input.
src() {
  local p="$BATS_TEST_TMPDIR/$1"
  mkdir -p "$(dirname "$p")"
  printf '%s\n' "$2" > "$p"
  printf '%s\n' "$p"
}

# ─────────────────────────── create: the happy path ─────────────────────────

@test "brief_cmd: create-publishes-atomically — one step from a complete candidate" {
  local c i
  c="$(cand ok.md --inputs PRD.md)"
  i="$(src PRD.md 'product requirements, nothing secret')"
  run --separate-stderr "$BRIEF" create --mb "$BANK" --topic checkout-v2 \
    --candidate "$c" --input "$i"
  [ "$status" -eq 0 ]
  [ "$output" = "brief=created path=briefs/checkout-v2/brief.md" ]
  [ "$stderr" = "" ]
  [ -f "$BANK/briefs/checkout-v2/brief.md" ]
  [ -f "$BANK/briefs/checkout-v2/inputs/PRD.md" ]
  # The candidate is consumed on success, and no staging residue is left.
  refute_file "$c"
  refute_cmd bash -c "ls -d '$BANK'/tmp/*staging* 2>/dev/null | grep -q ."
}

@test "brief_cmd: create-publishes-atomically — the published brief is the candidate byte for byte" {
  local c i before
  c="$(cand ok.md --inputs PRD.md)"
  before="$BATS_TEST_TMPDIR/before.md"
  snapshot "$c" "$before"
  i="$(src PRD.md 'product requirements')"
  run "$BRIEF" create --mb "$BANK" --topic checkout-v2 --candidate "$c" --input "$i"
  [ "$status" -eq 0 ]
  assert_unchanged "$BANK/briefs/checkout-v2/brief.md" "$before"
}

@test "brief_cmd: no-input — a prompt-only brief carries inputs: [] and '- None'" {
  local c
  c="$(cand none.md --inputs '')"
  run --separate-stderr "$BRIEF" create --mb "$BANK" --topic solo --candidate "$c"
  [ "$status" -eq 0 ]
  [ "$output" = "brief=created path=briefs/solo/brief.md" ]
  [ -f "$BANK/briefs/solo/brief.md" ]
  assert_grep -q '^- None$' "$BANK/briefs/solo/brief.md"
  # An empty inputs/ directory is not created for a brief with no sources.
  refute_file "$BANK/briefs/solo/inputs"
}

@test "brief_cmd: first-publish-creates-roots — a fresh bank has neither tmp/ nor briefs/" {
  local fresh="$BATS_TEST_TMPDIR/fresh" c
  mkdir -p "$fresh"
  c="$(cand roots.md --inputs '')"
  cp "$c" "$fresh-candidate.md"
  refute_file "$fresh/briefs"
  refute_file "$fresh/tmp"
  run --separate-stderr "$BRIEF" create --mb "$fresh" --topic roots \
    --candidate "$fresh-candidate.md"
  [ "$status" -eq 0 ]
  [ "$output" = "brief=created path=briefs/roots/brief.md" ]
  [ -f "$fresh/briefs/roots/brief.md" ]
}

# ─────────────────────────── exists gate ────────────────────────────────────

@test "brief_cmd: empty-topic-dir-blocks — staging is not nested inside it" {
  local c
  c="$(cand e.md --inputs '')"
  mkdir -p "$BANK/briefs/taken"
  run --separate-stderr "$BRIEF" create --mb "$BANK" --topic taken --candidate "$c"
  [ "$status" -eq 1 ]
  [ "$output" = "brief=blocked reason=exists" ]
  assert_substring "$stderr" "error=exists path=briefs/taken"
  # Nothing was moved INTO the pre-existing directory.
  [ -z "$(ls -A "$BANK/briefs/taken")" ]
}

@test "brief_cmd: exists-blocks-without-overwrite — the existing brief is untouched" {
  local c keep
  c="$(cand x.md --inputs '')"
  mkdir -p "$BANK/briefs/taken"
  printf 'the original brief\n' > "$BANK/briefs/taken/brief.md"
  keep="$BATS_TEST_TMPDIR/keep.md"
  snapshot "$BANK/briefs/taken/brief.md" "$keep"
  run --separate-stderr "$BRIEF" create --mb "$BANK" --topic taken --candidate "$c"
  [ "$status" -eq 1 ]
  [ "$output" = "brief=blocked reason=exists" ]
  assert_unchanged "$BANK/briefs/taken/brief.md" "$keep"
}

@test "brief_cmd: exists-blocks-without-overwrite — a SYMLINK at the destination blocks too" {
  # Otherwise `mv` would follow the link and publish the brief — with its
  # scanned inputs — into an attacker-chosen directory outside the bank.
  local c outside
  c="$(cand s.md --inputs '')"
  outside="$BATS_TEST_TMPDIR/outside"
  mkdir -p "$outside"
  ln -s "$outside" "$BANK/briefs/linked"
  run --separate-stderr "$BRIEF" create --mb "$BANK" --topic linked --candidate "$c"
  [ "$status" -eq 1 ]
  [ "$output" = "brief=blocked reason=exists" ]
  refute_file "$outside/brief.md"
  refute_file "$outside/linked"
}

@test "brief_cmd: exists-blocks-without-overwrite — a DANGLING symlink blocks too" {
  # A symlink to an existing directory is caught by `-e` alone; a DANGLING one
  # is not — `-e` follows the link and reports false. This is the case that
  # actually requires the separate `-L` test, and `mv` onto a dangling link
  # writes through it, outside the bank.
  local c target
  c="$(cand d.md --inputs '')"
  target="$BATS_TEST_TMPDIR/never-created"
  ln -s "$target" "$BANK/briefs/dangling"
  [ ! -e "$BANK/briefs/dangling" ]
  [ -L "$BANK/briefs/dangling" ]
  run --separate-stderr "$BRIEF" create --mb "$BANK" --topic dangling --candidate "$c"
  [ "$status" -eq 1 ]
  [ "$output" = "brief=blocked reason=exists" ]
  refute_file "$target"
}

@test "brief_cmd: candidate-path-nonexistent-no-line — a SYMLINK candidate is refused" {
  # The candidate must be the file the prompt layer wrote into the bank's tmp/,
  # not a link the helper is pointed at.
  local real link
  real="$(cand real.md --inputs '')"
  link="$BATS_TEST_TMPDIR/link-candidate.md"
  ln -s "$real" "$link"
  run --separate-stderr "$BRIEF" create --mb "$BANK" --topic linkcand --candidate "$link"
  [ "$status" -eq 2 ]
  [ "$output" = "" ]
  assert_substring "$stderr" "error=candidate_unreadable path=$link"
  refute_file "$BANK/briefs/linkcand"
  # The refusal touches neither the link nor its target.
  [ -f "$real" ]
  [ -L "$link" ]
}

@test "brief_cmd: exists-blocks-without-overwrite — there is no --update flag" {
  local c
  c="$(cand u.md --inputs '')"
  run --separate-stderr "$BRIEF" create --mb "$BANK" --topic fresh2 \
    --candidate "$c" --update
  [ "$status" -eq 2 ]
  [ "$output" = "" ]
  assert_substring "$stderr" "error=usage"
  refute_file "$BANK/briefs/fresh2"
}

@test "brief_cmd: concurrent-create-one-wins — two real processes, one created one exists" {
  local c1 c2
  c1="$(cand c1.md --inputs '')"
  c2="$(cand c2.md --inputs '')"
  "$BRIEF" create --mb "$BANK" --topic race --candidate "$c1" \
    > "$BATS_TEST_TMPDIR/o1" 2>"$BATS_TEST_TMPDIR/e1" &
  local p1=$!
  "$BRIEF" create --mb "$BANK" --topic race --candidate "$c2" \
    > "$BATS_TEST_TMPDIR/o2" 2>"$BATS_TEST_TMPDIR/e2" &
  local p2=$!
  local r1=0 r2=0
  wait $p1 || r1=$?
  wait $p2 || r2=$?

  local both
  both="$(cat "$BATS_TEST_TMPDIR/o1" "$BATS_TEST_TMPDIR/o2")"
  [ "$(printf '%s\n' "$both" | grep -c '^brief=created ')" -eq 1 ]
  [ "$(printf '%s\n' "$both" | grep -c '^brief=blocked reason=exists$')" -eq 1 ]
  [ "$((r1 + r2))" -eq 1 ]
  [ -f "$BANK/briefs/race/brief.md" ]
}

# ─────────────────────────── candidate validation ───────────────────────────

@test "brief_cmd: invalid-candidate-blocked — C1 diagnostics are forwarded verbatim" {
  # Proves the helper really runs scripts/mb-brief-validate.sh before publishing.
  local c
  c="$(cand bad.md --inputs '' --drop-section UX)"
  run --separate-stderr "$BRIEF" create --mb "$BANK" --topic bad --candidate "$c"
  [ "$status" -eq 1 ]
  [ "$output" = "brief=blocked reason=invalid" ]
  assert_substring "$stderr" "error=missing_section section=UX"
  refute_file "$BANK/briefs/bad"
}

@test "brief_cmd: auto-requires-assumptions-note — --auto without the key is blocked" {
  local c
  c="$(cand a.md --inputs '')"
  run --separate-stderr "$BRIEF" create --mb "$BANK" --topic autoless \
    --candidate "$c" --auto
  [ "$status" -eq 1 ]
  [ "$output" = "brief=blocked reason=invalid" ]
  assert_substring "$stderr" "error=assumptions_note_missing"
  refute_file "$BANK/briefs/autoless"
}

@test "brief_cmd: auto-requires-assumptions-note — --auto with the key publishes" {
  local c
  c="$(cand a2.md --inputs '' '--fm-add=assumptions_note=assumed a checkout goal')"
  run --separate-stderr "$BRIEF" create --mb "$BANK" --topic autoed \
    --candidate "$c" --auto
  [ "$status" -eq 0 ]
  [ "$output" = "brief=created path=briefs/autoed/brief.md" ]
}

@test "brief_cmd: no-auto-rejects-assumptions-note — the key without --auto is blocked" {
  local c
  c="$(cand a3.md --inputs '' '--fm-add=assumptions_note=assumed a checkout goal')"
  run --separate-stderr "$BRIEF" create --mb "$BANK" --topic noauto --candidate "$c"
  [ "$status" -eq 1 ]
  [ "$output" = "brief=blocked reason=invalid" ]
  assert_substring "$stderr" "error=assumptions_note_unexpected"
  refute_file "$BANK/briefs/noauto"
}

# ─────────────────────────── inputs invariant (C2) ──────────────────────────

@test "brief_cmd: attachments-encoded-basename — a space and a # round-trip" {
  local c i
  c="$(cand enc.md --inputs 'a b#c.md')"
  # The literal encoding is pinned here, not derived from the implementation.
  # `-e` is required: a pattern starting with `-` is parsed as an option by BSD
  # grep, which returns 2 (usage) rather than 0/1.
  assert_grep -qF -e '- [a b#c.md](inputs/a%20b%23c.md)' "$c"
  i="$(src 'a b#c.md' 'harmless notes')"
  run --separate-stderr "$BRIEF" create --mb "$BANK" --topic enc \
    --candidate "$c" --input "$i"
  [ "$status" -eq 0 ]
  [ "$output" = "brief=created path=briefs/enc/brief.md" ]
  [ -f "$BANK/briefs/enc/inputs/a b#c.md" ]
}

@test "brief_cmd: attachments-encoded-basename — an UNENCODED link is a mismatch" {
  local c i
  c="$(cand raw.md --inputs 'a b.md' \
    '--attachments-raw=- [a b.md](inputs/a b.md)')"
  i="$(src 'a b.md' 'harmless notes')"
  run --separate-stderr "$BRIEF" create --mb "$BANK" --topic rawlink \
    --candidate "$c" --input "$i"
  [ "$status" -eq 1 ]
  [ "$output" = "brief=blocked reason=invalid" ]
  assert_substring "$stderr" "where=attachments"
  refute_file "$BANK/briefs/rawlink"
}

@test "brief_cmd: attachments-encoded-basename — a DUPLICATE link is a mismatch" {
  local c i
  c="$(cand dup.md --inputs 'PRD.md' \
    '--attachments-raw=- [PRD.md](inputs/PRD.md)
- [PRD.md](inputs/PRD.md)')"
  i="$(src PRD.md 'harmless notes')"
  run --separate-stderr "$BRIEF" create --mb "$BANK" --topic duplink \
    --candidate "$c" --input "$i"
  [ "$status" -eq 1 ]
  [ "$output" = "brief=blocked reason=invalid" ]
  assert_substring "$stderr" "where=attachments"
  refute_file "$BANK/briefs/duplink"
}

@test "brief_cmd: inputs-mismatch — frontmatter lists a source that argv does not" {
  local c i
  c="$(cand mm.md --inputs 'PRD.md,EXTRA.md')"
  i="$(src PRD.md 'harmless notes')"
  run --separate-stderr "$BRIEF" create --mb "$BANK" --topic mm \
    --candidate "$c" --input "$i"
  [ "$status" -eq 1 ]
  [ "$output" = "brief=blocked reason=invalid" ]
  assert_substring "$stderr" "error=inputs_mismatch path=inputs/EXTRA.md where=argv"
  refute_file "$BANK/briefs/mm"
}

@test "brief_cmd: inputs-mismatch — argv passes a source the frontmatter omits" {
  local c i j
  c="$(cand mm2.md --inputs 'PRD.md')"
  i="$(src PRD.md 'harmless notes')"
  j="$(src OTHER.md 'harmless notes')"
  run --separate-stderr "$BRIEF" create --mb "$BANK" --topic mm2 \
    --candidate "$c" --input "$i" --input "$j"
  [ "$status" -eq 1 ]
  [ "$output" = "brief=blocked reason=invalid" ]
  assert_substring "$stderr" "error=inputs_mismatch path=inputs/OTHER.md where=frontmatter"
  refute_file "$BANK/briefs/mm2"
}

@test "brief_cmd: inputs-mismatch — a '- None' body with a real input is rejected" {
  local c i
  c="$(cand mm3.md --inputs 'PRD.md' '--attachments-raw=- None')"
  i="$(src PRD.md 'harmless notes')"
  run --separate-stderr "$BRIEF" create --mb "$BANK" --topic mm3 \
    --candidate "$c" --input "$i"
  [ "$status" -eq 1 ]
  [ "$output" = "brief=blocked reason=invalid" ]
  assert_substring "$stderr" "where=attachments"
  refute_file "$BANK/briefs/mm3"
}

# ─────────────────────────── secret-scan gate (C5) ──────────────────────────

@test "brief_cmd: secret-hard-block — nothing is copied and the candidate survives" {
  local c i
  c="$(cand sec.md --inputs 'creds.md')"
  i="$(src creds.md "api key $SK in the doc")"
  run --separate-stderr "$BRIEF" create --mb "$BANK" --topic leaky \
    --candidate "$c" --input "$i"
  [ "$status" -eq 1 ]
  [ "$output" = "brief=blocked reason=secret" ]
  # The scanner's own finding is forwarded verbatim.
  assert_substring "$stderr" "$i:1:api_key"
  # The secret VALUE is never echoed by the helper.
  refute_substring "$stderr" "$SK"
  refute_substring "$output" "$SK"
  refute_file "$BANK/briefs/leaky"
  [ -f "$c" ]
}

@test "brief_cmd: candidate-saved-on-late-failure — candidate= is the LAST stderr line" {
  local c i last
  c="$(cand sec2.md --inputs 'creds.md')"
  i="$(src creds.md "api key $SK in the doc")"
  run --separate-stderr "$BRIEF" create --mb "$BANK" --topic leaky2 \
    --candidate "$c" --input "$i"
  [ "$status" -eq 1 ]
  [ -f "$c" ]
  last="$(printf '%s\n' "$stderr" | tail -1)"
  [ "$last" = "candidate=$c" ]
  # Exactly one such line, never more.
  [ "$(printf '%s\n' "$stderr" | grep -c '^candidate=')" -eq 1 ]
}

@test "brief_cmd: scan-unsupported-aborts — an unreadable input aborts, no override" {
  local c i
  c="$(cand un.md --inputs 'blob.bin')"
  i="$(src blob.bin 'placeholder')"
  printf 'PK\000\001binary\n' > "$i"
  run --separate-stderr "$BRIEF" create --mb "$BANK" --topic unsup \
    --candidate "$c" --input "$i"
  [ "$status" -eq 1 ]
  [ "$output" = "brief=blocked reason=scan_unsupported" ]
  assert_substring "$stderr" "$i:0:binary"
  refute_file "$BANK/briefs/unsup"
  # The candidate= rule holds on THIS refusal path too, not just on the secret
  # one: exactly one such line, and it is the last.
  [ "$(printf '%s\n' "$stderr" | grep -c '^candidate=')" -eq 1 ]
  [ "$(printf '%s\n' "$stderr" | tail -1)" = "candidate=$c" ]
}

@test "brief_cmd: two-unsupported-both-named — every unscannable source is named" {
  local c i j
  c="$(cand un2.md --inputs 'one.bin,two.bin')"
  i="$(src one.bin 'x')"; printf 'a\000b\n' > "$i"
  j="$(src two.bin 'x')"; printf 'c\000d\n' > "$j"
  run --separate-stderr "$BRIEF" create --mb "$BANK" --topic unsup2 \
    --candidate "$c" --input "$i" --input "$j"
  [ "$status" -eq 1 ]
  [ "$output" = "brief=blocked reason=scan_unsupported" ]
  # REQ-010: EVERY unscannable source, not just the first one to fail.
  assert_substring "$stderr" "$i:0:binary"
  assert_substring "$stderr" "$j:0:binary"
  refute_file "$BANK/briefs/unsup2"
}

@test "brief_cmd: mixed-blocked-unsupported — unsupported wins, both are diagnosed" {
  local c i j
  c="$(cand mix.md --inputs 'creds.md,blob.bin')"
  i="$(src creds.md "api key $SK here")"
  j="$(src blob.bin 'x')"; printf 'a\000b\n' > "$j"
  run --separate-stderr "$BRIEF" create --mb "$BANK" --topic mixed \
    --candidate "$c" --input "$i" --input "$j"
  [ "$status" -eq 1 ]
  # Priority per the C5 table: unsupported outranks blocked.
  [ "$output" = "brief=blocked reason=scan_unsupported" ]
  # Diagnostics for BOTH non-clean sources, in argv order.
  local order
  order="$(printf '%s\n' "$stderr" | grep -n -e "$i:1:api_key" -e "$j:0:binary" | cut -d: -f1)"
  [ "$(printf '%s\n' "$order" | head -1)" -lt "$(printf '%s\n' "$order" | tail -1)" ]
  refute_file "$BANK/briefs/mixed"
}

@test "brief_cmd: scan-usage-is-not-clean — a scanner regression never reads as clean" {
  # A scanner that exits 2 with EMPTY stdout is a contract regression, not a
  # verdict. Deriving "clean" from it would copy an unscanned source.
  local d c i
  d="$BATS_TEST_TMPDIR/stub"
  mkdir -p "$d"
  # Every sibling the helper resolves from its own physical directory.
  cp "$BRIEF" "$d/mb-brief.sh"
  cp "$REPO_ROOT/scripts/mb-brief-validate.sh" "$d/mb-brief-validate.sh"
  cp "$REPO_ROOT/scripts/mb_brief_candidate.py" "$d/mb_brief_candidate.py"
  cp "$REPO_ROOT/scripts/_lib.sh" "$d/_lib.sh"
  printf '#!/usr/bin/env bash\nexit 2\n' > "$d/mb-secret-scan.sh"
  chmod +x "$d/mb-brief.sh" "$d/mb-brief-validate.sh" "$d/mb-secret-scan.sh"

  c="$(cand su.md --inputs 'PRD.md')"
  i="$(src PRD.md 'entirely harmless')"
  run --separate-stderr "$d/mb-brief.sh" create --mb "$BANK" --topic scanusage \
    --candidate "$c" --input "$i"
  [ "$status" -eq 2 ]
  [ "$output" = "" ]
  assert_substring "$stderr" "error=scan_usage path=$i"
  refute_file "$BANK/briefs/scanusage"
}

# ─────────────────────────── usage / argument guards ────────────────────────

@test "brief_cmd: basename-collision — two inputs with one basename, before any mkdir" {
  local c i j
  c="$(cand bc.md --inputs 'PRD.md')"
  i="$(src 'one/PRD.md' 'first')"
  j="$(src 'two/PRD.md' 'second')"
  run --separate-stderr "$BRIEF" create --mb "$BANK" --topic collide \
    --candidate "$c" --input "$i" --input "$j"
  [ "$status" -eq 2 ]
  [ "$output" = "" ]
  assert_substring "$stderr" "error=basename_collision basename=PRD.md"
  refute_file "$BANK/briefs/collide"
}

@test "brief_cmd: input-unreadable — a missing source is reported by path" {
  local c
  c="$(cand iu.md --inputs 'ghost.md')"
  run --separate-stderr "$BRIEF" create --mb "$BANK" --topic ghost \
    --candidate "$c" --input "$BATS_TEST_TMPDIR/ghost.md"
  [ "$status" -eq 2 ]
  [ "$output" = "" ]
  assert_substring "$stderr" "error=input_unreadable path=$BATS_TEST_TMPDIR/ghost.md"
  refute_file "$BANK/briefs/ghost"
}

@test "brief_cmd: input-unreadable — a SYMLINK source is refused, not followed" {
  # The scan would inspect the link target while the copy could resolve to a
  # different file; refusing the shape removes the whole question.
  local c target link
  c="$(cand sl.md --inputs 'link.md')"
  target="$(src real.md 'harmless')"
  link="$BATS_TEST_TMPDIR/link.md"
  ln -s "$target" "$link"
  run --separate-stderr "$BRIEF" create --mb "$BANK" --topic linked2 \
    --candidate "$c" --input "$link"
  [ "$status" -eq 2 ]
  [ "$output" = "" ]
  assert_substring "$stderr" "error=input_unreadable path=$link"
  refute_file "$BANK/briefs/linked2"
}

@test "brief_cmd: input-unreadable — a directory is not a source" {
  local c d
  c="$(cand id.md --inputs 'adir')"
  d="$BATS_TEST_TMPDIR/adir"
  mkdir -p "$d"
  run --separate-stderr "$BRIEF" create --mb "$BANK" --topic adir \
    --candidate "$c" --input "$d"
  [ "$status" -eq 2 ]
  [ "$output" = "" ]
  assert_substring "$stderr" "error=input_unreadable path=$d"
}

@test "brief_cmd: input-unreadable — a .. component is refused before any scan" {
  local c i rel
  c="$(cand tv.md --inputs 'PRD.md')"
  i="$(src PRD.md 'harmless')"
  rel="$BATS_TEST_TMPDIR/sub/../PRD.md"
  mkdir -p "$BATS_TEST_TMPDIR/sub"
  run --separate-stderr "$BRIEF" create --mb "$BANK" --topic trav \
    --candidate "$c" --input "$rel"
  [ "$status" -eq 2 ]
  [ "$output" = "" ]
  assert_substring "$stderr" "error=input_unreadable path=$rel"
  refute_file "$BANK/briefs/trav"
}

@test "brief_cmd: candidate-flag-missing-no-line — usage error prints NO candidate= line" {
  run --separate-stderr "$BRIEF" create --mb "$BANK" --topic nocand
  [ "$status" -eq 2 ]
  [ "$output" = "" ]
  assert_substring "$stderr" "error=usage"
  refute_grep -q '^candidate=' <(printf '%s\n' "$stderr")
}

@test "brief_cmd: candidate-path-nonexistent-no-line — still no candidate= line" {
  run --separate-stderr "$BRIEF" create --mb "$BANK" --topic ghostcand \
    --candidate "$BATS_TEST_TMPDIR/nope.md"
  [ "$status" -eq 2 ]
  [ "$output" = "" ]
  refute_grep -q '^candidate=' <(printf '%s\n' "$stderr")
}

@test "brief_cmd: candidate-flag-missing-no-line — a bad topic is refused before any write" {
  local c
  c="$(cand bt.md --inputs '')"
  run --separate-stderr "$BRIEF" create --mb "$BANK" --topic ../escape --candidate "$c"
  [ "$status" -eq 2 ]
  [ "$output" = "" ]
  assert_substring "$stderr" "error=usage"
  refute_file "$BANK/briefs/../escape"
}

# ─────────────────────────── context manifest ───────────────────────────────

@test "brief_cmd: context-absent — no brief means exactly one line" {
  run --separate-stderr "$BRIEF" context --mb "$BANK" --topic nothing
  [ "$status" -eq 0 ]
  [ "$output" = "brief=absent" ]
  [ "$stderr" = "" ]
}

@test "brief_cmd: context-manifest — paths in LC_ALL=C order, body never printed" {
  mkdir -p "$BANK/briefs/m/inputs"
  printf 'the brief body with a MARKER word\n' > "$BANK/briefs/m/brief.md"
  printf 'a\n' > "$BANK/briefs/m/inputs/b.md"
  printf 'b\n' > "$BANK/briefs/m/inputs/a.md"
  printf 'c\n' > "$BANK/briefs/m/inputs/C.md"
  run --separate-stderr "$BRIEF" context --mb "$BANK" --topic m
  [ "$status" -eq 0 ]
  local expected
  expected="$(printf '%s\n%s\n%s\n%s\n%s' \
    'brief=present' \
    'brief_path=briefs/m/brief.md' \
    'input_path=briefs/m/inputs/C.md' \
    'input_path=briefs/m/inputs/a.md' \
    'input_path=briefs/m/inputs/b.md')"
  [ "$output" = "$expected" ]
  # A manifest of paths, not a dump of the brief.
  refute_substring "$output" "MARKER"
}

@test "brief_cmd: context-usage — a missing flag is exit 2 with an empty stdout" {
  run --separate-stderr "$BRIEF" context --mb "$BANK"
  [ "$status" -eq 2 ]
  [ "$output" = "" ]
  [ "$stderr" = "error=usage" ]
}

@test "brief_cmd: context-usage — an unknown subcommand is exit 2" {
  run --separate-stderr "$BRIEF" publish --mb "$BANK" --topic m
  [ "$status" -eq 2 ]
  [ "$output" = "" ]
  [ "$stderr" = "error=usage" ]
}

# ─────────────────────────── prompt contract (C7) ───────────────────────────

@test "brief_cmd: clause-questions-unclear — REQ-003 light-question gate" {
  run assert_clause "$CMD" brief-questions-unclear
  [ "$status" -eq 0 ]
  run assert_clause_load_bearing "$CMD" brief-questions-unclear
  [ "$status" -eq 0 ]
}

@test "brief_cmd: clause-questions-skipped-when-clear — REQ-004 clear intent" {
  run assert_clause "$CMD" brief-questions-skipped-when-clear
  [ "$status" -eq 0 ]
  run assert_clause_load_bearing "$CMD" brief-questions-skipped-when-clear
  [ "$status" -eq 0 ]
}

@test "brief_cmd: clause-auto-skips-questions — REQ-003/004 --auto exception" {
  run assert_clause "$CMD" brief-auto-skips-questions
  [ "$status" -eq 0 ]
  run assert_clause_load_bearing "$CMD" brief-auto-skips-questions
  [ "$status" -eq 0 ]
}

@test "brief_cmd: clause-request-source-xor — REQ-001 request source XOR" {
  run assert_clause "$CMD" brief-request-source-xor
  [ "$status" -eq 0 ]
  run assert_clause_load_bearing "$CMD" brief-request-source-xor
  [ "$status" -eq 0 ]
}

@test "brief_cmd: clause-request-inline-nonempty — REQ-001 whitespace-only --request" {
  run assert_clause "$CMD" brief-request-inline-nonempty
  [ "$status" -eq 0 ]
  run assert_clause_load_bearing "$CMD" brief-request-inline-nonempty
  [ "$status" -eq 0 ]
}

@test "brief_cmd: clause-request-file-guard — REQ-001 --request-file guard" {
  run assert_clause "$CMD" brief-request-file-guard
  [ "$status" -eq 0 ]
  run assert_clause_load_bearing "$CMD" brief-request-file-guard
  [ "$status" -eq 0 ]
}

@test "brief_cmd: clause-candidate-before-helper — REQ-001 candidate precedes the helper" {
  run assert_clause "$CMD" brief-candidate-before-helper
  [ "$status" -eq 0 ]
  run assert_clause_load_bearing "$CMD" brief-candidate-before-helper
  [ "$status" -eq 0 ]
}

@test "brief_cmd: clause-helper-publish — REQ-001 the helper is the only publisher" {
  run assert_clause "$CMD" brief-helper-publish
  [ "$status" -eq 0 ]
  run assert_clause_load_bearing "$CMD" brief-helper-publish
  [ "$status" -eq 0 ]
}

@test "brief_cmd: clause-attachments-links — REQ-008 relative inputs/ links" {
  run assert_clause "$CMD" brief-attachments-links
  [ "$status" -eq 0 ]
  run assert_clause_load_bearing "$CMD" brief-attachments-links
  [ "$status" -eq 0 ]
}

@test "brief_cmd: clause-handoff-line — REQ-005 the final line is the discuss offer" {
  run assert_clause "$CMD" brief-handoff-line
  [ "$status" -eq 0 ]
  run assert_clause_load_bearing "$CMD" brief-handoff-line
  [ "$status" -eq 0 ]
}

@test "brief_cmd: template-validates — the documented one-pager passes C1" {
  # A typo in a section name here would send every user's first brief straight
  # to brief=invalid, and nothing else in the suite reads this file.
  local t="$BATS_TEST_TMPDIR/from-template.md"
  python3 - "$REPO_ROOT/references/templates.md" "$t" <<'PY'
import sys

src, dst = sys.argv[1], sys.argv[2]
lines = open(src, encoding="utf-8").read().split("\n")
start = next(i for i, l in enumerate(lines) if l.startswith("## Brief one-pager"))
open_at = next(i for i in range(start, len(lines)) if lines[i].startswith("```markdown"))
close_at = next(i for i in range(open_at + 1, len(lines)) if lines[i].startswith("```"))
body = "\n".join(lines[open_at + 1:close_at]) + "\n"
for placeholder, real in (
    ("<topic>", "demo"),
    ("YYYY-MM-DD", "2026-07-17"),
    ("inputs/<basename>", "inputs/a.md"),
    ("[<basename>]", "[a.md]"),
    ("inputs/<encoded-basename>", "inputs/a.md"),
):
    body = body.replace(placeholder, real)
open(dst, "w", encoding="utf-8").write(body)
PY
  run --separate-stderr "$REPO_ROOT/scripts/mb-brief-validate.sh" "$t"
  [ "$status" -eq 0 ]
  [ "$output" = "brief=ok" ]
  [ "$stderr" = "" ]
}

@test "brief_cmd: template-validates — the template publishes through the helper" {
  # End to end on the documented shape: the template is not merely parseable,
  # it is publishable.
  local t="$BANK/tmp/from-template.md"
  python3 - "$REPO_ROOT/references/templates.md" "$t" <<'PY'
import sys

src, dst = sys.argv[1], sys.argv[2]
lines = open(src, encoding="utf-8").read().split("\n")
start = next(i for i, l in enumerate(lines) if l.startswith("## Brief one-pager"))
open_at = next(i for i in range(start, len(lines)) if lines[i].startswith("```markdown"))
close_at = next(i for i in range(open_at + 1, len(lines)) if lines[i].startswith("```"))
body = "\n".join(lines[open_at + 1:close_at]) + "\n"
for placeholder, real in (
    ("<topic>", "demo"),
    ("YYYY-MM-DD", "2026-07-17"),
    ("inputs/<basename>", "inputs/a.md"),
    ("[<basename>]", "[a.md]"),
    ("inputs/<encoded-basename>", "inputs/a.md"),
):
    body = body.replace(placeholder, real)
open(dst, "w", encoding="utf-8").write(body)
PY
  local i
  i="$(src a.md 'a harmless source document')"
  run --separate-stderr "$BRIEF" create --mb "$BANK" --topic demo \
    --candidate "$t" --input "$i"
  [ "$status" -eq 0 ]
  [ "$output" = "brief=created path=briefs/demo/brief.md" ]
  [ -f "$BANK/briefs/demo/inputs/a.md" ]
}

@test "brief_cmd: shellcheck and bash -n clean" {
  run shellcheck -x -S error "$BRIEF"
  [ "$status" -eq 0 ]
  run bash -n "$BRIEF"
  [ "$status" -eq 0 ]
}
