#!/usr/bin/env bats
# transcript: — svp-interview-upgrade Task 4 prompt contract.
# The Transcript step in `### Write & finalize` (candidate-first, secret-scan
# gate, <private>-is-not-a-bypass, block-on-finding, frontmatter) + the C4
# transcript template in references/templates.md.
#
# Name convention: every @test starts with `transcript: ` (Eval red-anchor).

bats_require_minimum_version 1.5.0
load 'lib/discuss_contract'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  DISCUSS="$REPO_ROOT/commands/discuss.md"
  TEMPLATES="$REPO_ROOT/references/templates.md"
  MB_DISCUSS_CLAUSES=()
  MB_DISCUSS_CLAUSES+=("transcript-candidate-first|mb_section|Transcript|scratch dir\.\*\* Write the candidate to .*before any git-tracked path|candidate|s/\*\* Write the candidate/** Do not write the candidate/|REQ-005")
  # r3 review [3]: the scan must be INSIDE publish-transcript, never a separate
  # read-only pre-scan the agent stops on (that strands the raw credential).
  MB_DISCUSS_CLAUSES+=("transcript-scan-in-writer|mb_section|Transcript|publish-transcript. runs the secret scan|secret scan|s/runs the secret scan/skips the secret scan/|REQ-007")
  MB_DISCUSS_CLAUSES+=("transcript-no-self-scan|mb_section|Transcript|never scan the candidate yourself|scan the candidate|s/never scan the candidate yourself/scan the candidate yourself first/|REQ-007")
  MB_DISCUSS_CLAUSES+=("transcript-private-not-clean|mb_section|Transcript|raw text including content inside|raw text|s/ including content inside .<private>.//|REQ-007")
  MB_DISCUSS_CLAUSES+=("transcript-block-on-finding|mb_section|Transcript|git target is not created|finding|s/the git target is not created/the git target is overwritten/|REQ-007")
  MB_DISCUSS_CLAUSES+=("transcript-frontmatter|mb_section|Transcript|frontmatter records .interview_transcript:|frontmatter|s/ records .interview_transcript:.*//|REQ-005")
  MB_DISCUSS_CLAUSES+=("template-c4-grammar|mb_section|Interview transcript template|\\*\\*Финальный гейт|Interview transcript|/\\*\\*Финальный гейт/d|REQ-005")
  # REQ-007 candidate hygiene: verify-then-publish ordering and the guarantee
  # that the raw credential never lingers on disk.
  MB_DISCUSS_CLAUSES+=("transcript-verify-then-publish|mb_section|Transcript|order is .*verify, then publish.* — never publish, then verify|order|s/never publish, then verify/either order works/|REQ-007")
  MB_DISCUSS_CLAUSES+=("transcript-candidate-gitignored|mb_section|Transcript|tmp/. is gitignored|candidate|s/is gitignored/is a normal tracked directory/|REQ-007")
  MB_DISCUSS_CLAUSES+=("transcript-no-inplace-edit|mb_section|Transcript|[Nn]ever edit the candidate in place after a finding|candidate|s/Never edit the candidate in place/Edit the candidate in place/|REQ-007")
  MB_DISCUSS_CLAUSES+=("transcript-candidate-consumed|mb_section|Transcript|removes the candidate on every exit path|candidate|s/on every exit path/on success/|REQ-007")
}

# The template block is the fenced markdown under "## Interview transcript
# template"; sliced out so the validator sees exactly what the doc promises.
_c4_template_block() {
  local slice="$BATS_TEST_TMPDIR/c4block.md"
  awk '/^## Interview transcript template$/{f=1} f' "$TEMPLATES" > "$slice"
  printf '%s' "$slice"
}

_pair() {
  run assert_clause "$1" "$2"
  [ "$status" -eq 0 ]
  run assert_clause_load_bearing "$1" "$2"
  [ "$status" -eq 0 ]
}

@test "transcript: candidate is written before any git-tracked path" { _pair "$DISCUSS" transcript-candidate-first; }
@test "transcript: the secret scan runs INSIDE publish-transcript" { _pair "$DISCUSS" transcript-scan-in-writer; }
@test "transcript: the prompt forbids a standalone pre-scan of the candidate" { _pair "$DISCUSS" transcript-no-self-scan; }
@test "transcript: <private> does not unblock a git write" { _pair "$DISCUSS" transcript-private-not-clean; }
@test "transcript: a finding blocks target creation" { _pair "$DISCUSS" transcript-block-on-finding; }
@test "transcript: context frontmatter records interview_transcript" { _pair "$DISCUSS" transcript-frontmatter; }
@test "transcript: templates.md carries the C4 grammar markers" { _pair "$TEMPLATES" template-c4-grammar; }

@test "transcript: the C4 template actually PASSES the C8 validator" {
  # r4 [11]: the clause above pins one marker (`**Финальный гейт`), so deleting
  # the title, inherited section, Q&A heading, Q/A markers, decision and
  # rejected-alternatives from the template left both C9 checks green while the
  # rendered candidate would be REJECTED by C8. Render the template with its
  # placeholders filled and run the real validator over it — that binds every
  # required marker at once, and to the checker rather than to a word list.
  local rendered="$BATS_TEST_TMPDIR/rendered.md"
  awk '/^```markdown$/{f=1; next} f && /^```$/{exit} f' \
    "$(_c4_template_block)" > "$rendered"
  [ -s "$rendered" ] || { echo "could not extract the C4 template block"; false; }

  # Fill the angle-bracket placeholders with material the grammar accepts.
  python3 - "$rendered" <<'FILL'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("<topic> (<YYYY-MM-DD>[, <free text>])", "demo (2026-07-19)")
s = s.replace("## Унаследовано (не обсуждалось повторно)", "## Унаследовано")
s = s.replace("<inherited decisions — JIT slice interviews only; omit for a root topic>",
              "- D-00 carried from the parent")
s = s.replace("**Q1 (<tag>).** <question>", "**Q1 (scope).** What is the scope?")
s = s.replace("**A1.** <near-verbatim answer> → **D-01**. Отклонено: <none|rejected alternatives>",
              "**A1.** The scope is X → **D-01**. Отклонено: none")
s = s.replace("**Финальный гейт[, круг 1].** Anything to add?", "**Финальный гейт.** Anything to add?")
s = s.replace("**Ответ.** <user answer>", "**Ответ.** No.")
open(p, "w", encoding="utf-8").write(s)
FILL

  run --separate-stderr "$REPO_ROOT/scripts/mb-interview-artifact-check.sh" \
    transcript "$rendered" --require-inherited
  [ "$status" -eq 0 ] || {
    echo "the documented C4 template does not satisfy the C8 validator:"
    echo "$stderr"; cat "$rendered"; false; }
}

# ─── candidate hygiene (review [5], REQ-007) ───

@test "transcript: the order is verify-then-publish, never the reverse" { _pair "$DISCUSS" transcript-verify-then-publish; }
@test "transcript: the candidate lives only in the gitignored scratch dir" { _pair "$DISCUSS" transcript-candidate-gitignored; }
@test "transcript: a finding forbids in-place editing of the candidate" { _pair "$DISCUSS" transcript-no-inplace-edit; }
@test "transcript: the candidate is consumed on every exit path" { _pair "$DISCUSS" transcript-candidate-consumed; }

@test "transcript: the gitignore claim holds in a FRESHLY initialized bank" {
  # This used to assert against the MAINTAINER repo, whose root .gitignore has
  # carried `.memory-bank/tmp/` for ages — so it certified a guarantee that no
  # user actually got. A fresh `git init` + `mb-init-bank.sh` had no ignore rule
  # at all: the raw candidate was stageable by `git add .` (r2 review [8]).
  local proj="$BATS_TEST_TMPDIR/fresh"
  mkdir -p "$proj"
  git -C "$proj" init -q .
  git -C "$proj" config user.email t@example.com
  git -C "$proj" config user.name t
  run bash "$REPO_ROOT/scripts/mb-init-bank.sh" "--project-root=$proj"
  [ "$status" -eq 0 ] || { echo "init failed: $output"; false; }

  mkdir -p "$proj/.memory-bank/tmp"
  printf 'raw\n' > "$proj/.memory-bank/tmp/interview-transcript-x.candidate.md"
  run git -C "$proj" check-ignore -q .memory-bank/tmp/interview-transcript-x.candidate.md
  [ "$status" -eq 0 ] || { echo "fresh bank does not ignore <bank>/tmp/"; false; }
}

@test "transcript: git add . cannot stage a candidate in a fresh bank" {
  # The consequence that matters: raw credentials must not reach the index.
  local proj="$BATS_TEST_TMPDIR/fresh2"
  mkdir -p "$proj"
  git -C "$proj" init -q .
  git -C "$proj" config user.email t@example.com
  git -C "$proj" config user.name t
  bash "$REPO_ROOT/scripts/mb-init-bank.sh" "--project-root=$proj" >/dev/null

  mkdir -p "$proj/.memory-bank/tmp"
  printf 'sk-ant-api03ABCDEFGHIJKLMNOP\n' > "$proj/.memory-bank/tmp/interview-transcript-x.candidate.md"
  git -C "$proj" add . >/dev/null 2>&1 || true
  run git -C "$proj" diff --cached --name-only
  ! echo "$output" | grep -q 'interview-transcript-x.candidate.md' \
    || { echo "candidate was staged: $output"; false; }
}

@test "transcript: an existing bank .gitignore is extended, never clobbered" {
  local proj="$BATS_TEST_TMPDIR/fresh3"
  mkdir -p "$proj/.memory-bank"
  printf '# user rules\n/my-scratch/\n' > "$proj/.memory-bank/.gitignore"
  bash "$REPO_ROOT/scripts/mb-init-bank.sh" "--project-root=$proj" >/dev/null
  grep -q '/my-scratch/' "$proj/.memory-bank/.gitignore"
  grep -qE '^/tmp/$' "$proj/.memory-bank/.gitignore"
  # Idempotent: a second init must not append the rule twice.
  bash "$REPO_ROOT/scripts/mb-init-bank.sh" "--project-root=$proj" >/dev/null
  [ "$(grep -cE '^/tmp/$' "$proj/.memory-bank/.gitignore")" -eq 1 ]
}

@test "transcript: the writer really scrubs the candidate (prompt matches code)" {
  # Binds the prompt promise to the implementation: the claim "removed on every
  # exit path" must be backed by a trap in the writer, not just asserted.
  local w="$REPO_ROOT/scripts/mb-interview-artifact-write.sh"
  grep -q '_scrub_candidate' "$w"
  grep -Eq 'trap .*_scrub_candidate.* EXIT' "$w"
  grep -Eq "trap .*_on_signal 15.* TERM" "$w"
}

@test "transcript: harness rejects a vacuous transcript clause" {
  # Bare word `interview-transcript` matches exactly one line (the candidate
  # path); a real mutation of the normative tail leaves the word → vacuous.
  MB_DISCUSS_CLAUSES+=("bare-it|mb_section|Transcript|interview-transcript|interview-transcript|s/ before any git-tracked path//|REQ-005")
  run assert_clause_load_bearing "$DISCUSS" bare-it
  [ "$status" -ne 0 ]
  echo "$output" | grep -Eq 'reason=(vacuous|mutation_removed_topic)'
}

# ─── bank-ignore write safety (r3 review [18]) ───
# These live beside the [8] guarantee above: the same init step that promises
# `<bank>/tmp/` is ignored must not damage the file it writes that promise into.

@test "transcript: a SYMLINKED bank .gitignore is refused, victim untouched" {
  # init appended through the link, so a symlink planted at <bank>/.gitignore
  # made it write into an arbitrary file outside the bank.
  local proj="$BATS_TEST_TMPDIR/sym" victim="$BATS_TEST_TMPDIR/victim.txt"
  mkdir -p "$proj/.memory-bank"
  printf 'PRECIOUS VICTIM\n' > "$victim"
  local snap="$BATS_TEST_TMPDIR/snap.txt"; cp "$victim" "$snap"
  ln -s "$victim" "$proj/.memory-bank/.gitignore"

  run bash "$REPO_ROOT/scripts/mb-init-bank.sh" "--project-root=$proj"
  cmp -s "$snap" "$victim" || { echo "init wrote through the .gitignore symlink"; false; }
  [ -L "$proj/.memory-bank/.gitignore" ] || { echo "the symlink was replaced"; false; }
}

@test "transcript: an existing .gitignore WITHOUT a terminal LF is not corrupted" {
  # `/secret` with no trailing newline became `/secret# Memory Bank scratch…`,
  # silently disabling the user's own ignore rule.
  local proj="$BATS_TEST_TMPDIR/nolf"
  mkdir -p "$proj/.memory-bank"
  printf '# user rules\n/secret' > "$proj/.memory-bank/.gitignore"
  bash "$REPO_ROOT/scripts/mb-init-bank.sh" "--project-root=$proj" >/dev/null

  grep -qE '^/secret$' "$proj/.memory-bank/.gitignore" \
    || { echo "the /secret rule was corrupted:"; cat "$proj/.memory-bank/.gitignore"; false; }
  grep -qE '^/tmp/$' "$proj/.memory-bank/.gitignore"
}

@test "transcript: the bank .gitignore keeps its mode across the update" {
  local proj="$BATS_TEST_TMPDIR/mode"
  mkdir -p "$proj/.memory-bank"
  printf '# user rules\n/secret\n' > "$proj/.memory-bank/.gitignore"
  chmod 600 "$proj/.memory-bank/.gitignore"
  bash "$REPO_ROOT/scripts/mb-init-bank.sh" "--project-root=$proj" >/dev/null
  local m; m="$(stat -f '%Lp' "$proj/.memory-bank/.gitignore" 2>/dev/null || stat -c '%a' "$proj/.memory-bank/.gitignore")"
  [ "$m" = "600" ] || { echo "mode changed to $m"; false; }
}

@test "transcript: a directory at <bank>/.gitignore is refused, not written into" {
  local proj="$BATS_TEST_TMPDIR/isdir"
  mkdir -p "$proj/.memory-bank/.gitignore"
  run bash "$REPO_ROOT/scripts/mb-init-bank.sh" "--project-root=$proj"
  [ -d "$proj/.memory-bank/.gitignore" ]
}

# ─── init resolves its own helpers through the symlink chain (r3 review [17]) ───

@test "transcript: init through a symlink does not source a forged sibling _lib.sh" {
  # SCRIPT_DIR came from dirname "$0" without walking the link, so a link in an
  # attacker directory made init source that directory's _lib.sh.
  local linkdir="$BATS_TEST_TMPDIR/linkdir" proj="$BATS_TEST_TMPDIR/p17"
  mkdir -p "$linkdir" "$proj"
  ln -s "$REPO_ROOT/scripts/mb-init-bank.sh" "$linkdir/mb-init-bank.sh"
  printf '#!/usr/bin/env bash\necho "FORGED_LIB_SOURCED" >&2\n' > "$linkdir/_lib.sh"

  run bash "$linkdir/mb-init-bank.sh" "--project-root=$proj"
  echo "$output" | grep -q 'FORGED_LIB_SOURCED' && { echo "forged _lib.sh was sourced"; false; }
  [ "$status" -eq 0 ] || { echo "init failed through a symlink: $output"; false; }
  [ -f "$proj/.memory-bank/status.md" ] || { echo "templates did not resolve"; false; }
}

@test "transcript: init through a MULTI-HOP relative symlink still resolves" {
  local d1="$BATS_TEST_TMPDIR/hop1" d2="$BATS_TEST_TMPDIR/hop2" proj="$BATS_TEST_TMPDIR/p17b"
  mkdir -p "$d1" "$d2" "$proj"
  ln -s "$REPO_ROOT/scripts/mb-init-bank.sh" "$d1/mb-init-bank.sh"
  ( cd "$d2" && ln -s "../hop1/mb-init-bank.sh" mb-init-bank.sh )
  run bash "$d2/mb-init-bank.sh" "--project-root=$proj"
  [ "$status" -eq 0 ] || { echo "multi-hop symlink failed: $output"; false; }
  [ -f "$proj/.memory-bank/status.md" ]
}

@test "transcript: a LATER negation does not count as the rule being installed" {
  # r4 [5]: `/tmp/` followed by `!/tmp/` made init exit 0 believing the rule was
  # present, but git applies last-match-wins — check-ignore returned 1 and
  # `git add .` staged the raw candidate. An early match before a later negation
  # is not idempotent success.
  local proj="$BATS_TEST_TMPDIR/neg"
  mkdir -p "$proj/.memory-bank"
  printf '/tmp/\n!/tmp/\n' > "$proj/.memory-bank/.gitignore"
  bash "$REPO_ROOT/scripts/mb-init-bank.sh" "--project-root=$proj" >/dev/null

  git -C "$proj" init -q .
  git -C "$proj" config user.email t@example.com
  git -C "$proj" config user.name t
  mkdir -p "$proj/.memory-bank/tmp"
  printf 'sk-ant-api03ABCDEFGHIJKLMNOP\n' > "$proj/.memory-bank/tmp/interview-transcript-x.candidate.md"

  run git -C "$proj" check-ignore -q .memory-bank/tmp/interview-transcript-x.candidate.md
  [ "$status" -eq 0 ] || { echo "a later negation defeated the rule"; cat "$proj/.memory-bank/.gitignore"; false; }
  git -C "$proj" add . >/dev/null 2>&1 || true
  run git -C "$proj" diff --cached --name-only
  local staged; staged="$(printf '%s\n' "$output" | grep 'candidate' || true)"
  [ -z "$staged" ] || { echo "candidate staged despite the rule: $staged"; false; }
}

@test "transcript: the user's own negation of an unrelated path is preserved" {
  # The repair must be surgical: only the /tmp/ rule is re-asserted.
  local proj="$BATS_TEST_TMPDIR/neg2"
  mkdir -p "$proj/.memory-bank"
  printf '/tmp/\n!/tmp/\n!/keepme/\n' > "$proj/.memory-bank/.gitignore"
  bash "$REPO_ROOT/scripts/mb-init-bank.sh" "--project-root=$proj" >/dev/null
  grep -qx '!/keepme/' "$proj/.memory-bank/.gitignore" \
    || { echo "an unrelated user rule was dropped"; cat "$proj/.memory-bank/.gitignore"; false; }
}

@test "transcript: an already-effective rule is still idempotent" {
  local proj="$BATS_TEST_TMPDIR/neg3"
  mkdir -p "$proj/.memory-bank"
  printf '# user\n/tmp/\n' > "$proj/.memory-bank/.gitignore"
  bash "$REPO_ROOT/scripts/mb-init-bank.sh" "--project-root=$proj" >/dev/null
  bash "$REPO_ROOT/scripts/mb-init-bank.sh" "--project-root=$proj" >/dev/null
  [ "$(grep -cx '/tmp/' "$proj/.memory-bank/.gitignore")" -eq 1 ] \
    || { echo "rule appended more than once"; cat "$proj/.memory-bank/.gitignore"; false; }
}
