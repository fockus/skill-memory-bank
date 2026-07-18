#!/usr/bin/env bats
# glossary: — svp-interview-upgrade Task 5. Two halves:
#   1. the real `/mb context` writer (scripts/mb-context.sh, C10) prints one
#      `Glossary: glossary.md` pointer iff <bank>/glossary.md is a regular file,
#      never concatenates its content, and stays read-only.
#   2. the rule-13 prompt contract in commands/discuss.md + the glossary template.
#
# Name convention: every @test starts with `glossary: ` (Eval red-anchor).

bats_require_minimum_version 1.5.0
load 'lib/discuss_contract'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  CONTEXT="$REPO_ROOT/scripts/mb-context.sh"
  DISCUSS="$REPO_ROOT/commands/discuss.md"
  TEMPLATES="$REPO_ROOT/references/templates.md"
  BANK="$BATS_TEST_TMPDIR/bank/.memory-bank"
  mkdir -p "$BANK/plans"
  printf 'status line\n' > "$BANK/status.md"
  printf 'roadmap line\n' > "$BANK/roadmap.md"
  printf 'plan body\n' > "$BANK/plans/2026-01-01_feature_x.md"
  MB_DISCUSS_CLAUSES=()
  MB_DISCUSS_CLAUSES+=("rule13-write-immediate|mb_rule|13|record it immediately.*mb-glossary.sh|glossary|s/record it immediately/record it at the end of the interview/|REQ-017")
  MB_DISCUSS_CLAUSES+=("rule13-lazy-create|mb_rule|13|created lazily on the first term|the file|s/created lazily on the first term/preexisting/|REQ-017")
  MB_DISCUSS_CLAUSES+=("rule13-line-format|mb_rule|13|one line per entry as «term|glossary|s/, one line per entry as «term — definition»//|REQ-017")
  MB_DISCUSS_CLAUSES+=("rule13-challenge-conflict|mb_rule|13|challenge the conflict before recording the requirement|conflict|s/before recording the requirement/after recording the requirement/|REQ-018")
  MB_DISCUSS_CLAUSES+=("template-glossary|mb_section|Glossary template|<term> — <definition>|[Gg]lossary|/<term> — <definition>/d|REQ-017")
}

# ── half 1: real writer behaviour ──

@test "glossary: bank without glossary.md prints no Glossary line" {
  run "$CONTEXT" "$BANK"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q '^Glossary:'
}

@test "glossary: bank with glossary.md prints exactly one pointer, content not included" {
  printf 'slice — a child spec of a group\n' > "$BANK/glossary.md"
  run "$CONTEXT" "$BANK"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | grep -c '^Glossary: glossary.md$')" -eq 1 ]
  ! echo "$output" | grep -q 'a child spec of a group'
}

@test "glossary: the pointer sits after core files and before Active plans" {
  printf 'slice — def\n' > "$BANK/glossary.md"
  run "$CONTEXT" "$BANK"
  [ "$status" -eq 0 ]
  local gline pline
  gline="$(echo "$output" | grep -n '^Glossary: glossary.md$' | head -1 | cut -d: -f1)"
  pline="$(echo "$output" | grep -n '^--- Active plans ---$' | head -1 | cut -d: -f1)"
  [ -n "$gline" ] && [ -n "$pline" ]
  [ "$gline" -lt "$pline" ]
}

@test "glossary: non-glossary output is byte-identical apart from the pointer line" {
  run "$CONTEXT" "$BANK"; local without="$output"
  printf 'slice — def\n' > "$BANK/glossary.md"
  run "$CONTEXT" "$BANK"; local with_gloss="$output"
  [ "$(printf '%s\n' "$with_gloss" | grep -v '^Glossary: glossary.md$')" = "$without" ]
}

@test "glossary: symlinked glossary.md is skipped" {
  printf 'slice — def\n' > "$BATS_TEST_TMPDIR/real-gloss.md"
  ln -s "$BATS_TEST_TMPDIR/real-gloss.md" "$BANK/glossary.md"
  run "$CONTEXT" "$BANK"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q '^Glossary:'
}

@test "glossary: the context writer never modifies the bank" {
  printf 'slice — def\n' > "$BANK/glossary.md"
  local snap1 snap2
  snap1="$(cd "$BANK" && find . | sort)"
  run "$CONTEXT" "$BANK"
  snap2="$(cd "$BANK" && find . | sort)"
  [ "$snap1" = "$snap2" ]
}

# ── half 2: rule-13 prompt contract ──

_pair() {
  run assert_clause "$1" "$2"
  [ "$status" -eq 0 ]
  run assert_clause_load_bearing "$1" "$2"
  [ "$status" -eq 0 ]
}

@test "glossary: rule 13 records a resolved term immediately via mb-glossary.sh" { _pair "$DISCUSS" rule13-write-immediate; }
@test "glossary: rule 13 creates the glossary lazily on the first term" { _pair "$DISCUSS" rule13-lazy-create; }
@test "glossary: rule 13 uses the term — definition line format" { _pair "$DISCUSS" rule13-line-format; }
@test "glossary: rule 13 challenges a conflict before recording the requirement" { _pair "$DISCUSS" rule13-challenge-conflict; }
@test "glossary: templates.md carries the glossary line-format template" { _pair "$TEMPLATES" template-glossary; }
