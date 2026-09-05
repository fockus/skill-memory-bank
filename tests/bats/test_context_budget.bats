#!/usr/bin/env bats
# Per-file output budget for mb-context.sh (Stage 3, cost diet).
#
# Contract:
#   Each core file (status/roadmap/checklist/research) is trimmed to a byte cap
#   resolved as env MB_CONTEXT_MAX_BYTES -> <bank>/.mb-config context_max_bytes=
#   -> 16384. `--full` and MB_CONTEXT_MAX_BYTES=0 disable the cap entirely.
#   Trimming is semantic: whole `## ` sections for status.md, ✅-first drop for
#   checklist.md, head-by-line for the rest. A trimmed file is followed by one
#   `[context] <file>: shown N of M lines` marker.

load 'lib/assert'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-context.sh"
  FIXTURE="$REPO_ROOT/tests/fixtures/context-budget/.memory-bank"
  EXPECTED="$REPO_ROOT/tests/fixtures/context-budget/expected-full.txt"
  TMPDIR_T="$(mktemp -d)"
  # Small bank, every core file well under any cap.
  SMALLBANK="$TMPDIR_T/small/.memory-bank"
  mkdir -p "$SMALLBANK"
  printf '# Status\n\n## Now\nSmall.\n' > "$SMALLBANK/status.md"
  printf '# Roadmap\n\n- one\n' > "$SMALLBANK/roadmap.md"
  printf '# Checklist\n\n- ✅ a\n- ⬜ b\n' > "$SMALLBANK/checklist.md"
  printf '# Research\n\nnone\n' > "$SMALLBANK/research.md"
}

teardown() {
  [ -n "${TMPDIR_T:-}" ] && rm -rf "$TMPDIR_T"
  rm -f "${FIXTURE:?}/.mb-config"
}

@test "context budget: under cap → output byte-identical to --full" {
  bash "$SCRIPT" "$SMALLBANK" > "$TMPDIR_T/default.txt"
  bash "$SCRIPT" --full "$SMALLBANK" > "$TMPDIR_T/full.txt"
  cmp "$TMPDIR_T/default.txt" "$TMPDIR_T/full.txt"
  refute_grep -q '^\[context\] ' "$TMPDIR_T/default.txt"
}

@test "context budget: status.md over cap → whole sections kept, marker line present" {
  bash "$SCRIPT" "$FIXTURE" > "$TMPDIR_T/out.txt"
  # Section 1 survives intact (its last line is present)...
  assert_grep -q '^## Section 1$' "$TMPDIR_T/out.txt"
  assert_grep -qF -e '- s1 line 115:' "$TMPDIR_T/out.txt"
  # ...and section 2 is dropped WHOLE — a byte cut at 16384 would have kept its
  # heading plus ~7 KB of its body.
  refute_grep -q '^## Section 2$' "$TMPDIR_T/out.txt"
  assert_grep -q '^\[context\] status\.md: shown [0-9]* of 712 lines — full: .* or --full$' "$TMPDIR_T/out.txt"
}

@test "context budget: checklist.md over cap → ✅ lines dropped before ⬜ lines" {
  MB_CONTEXT_MAX_BYTES=4096 bash "$SCRIPT" "$FIXTURE" > "$TMPDIR_T/out.txt"
  refute_grep -qF -e '- ✅ done item' "$TMPDIR_T/out.txt"
  assert_grep -qF -e '- ⬜ open item 001' "$TMPDIR_T/out.txt"
  assert_grep -qF -e '- ⬜ open item 150' "$TMPDIR_T/out.txt"
  assert_grep -q '^\[context\] checklist\.md: shown 150 of 300 lines' "$TMPDIR_T/out.txt"
}

@test "context budget: --full restores unbounded output" {
  bash "$SCRIPT" --full "$FIXTURE" > "$TMPDIR_T/out.txt"
  assert_unchanged "$TMPDIR_T/out.txt" "$EXPECTED"
}

@test "context budget: --full and --deep accepted in either order" {
  bash "$SCRIPT" --deep --full "$FIXTURE" > "$TMPDIR_T/a.txt"
  bash "$SCRIPT" --full --deep "$FIXTURE" > "$TMPDIR_T/b.txt"
  assert_unchanged "$TMPDIR_T/a.txt" "$EXPECTED"
  assert_unchanged "$TMPDIR_T/b.txt" "$EXPECTED"
}

@test "context budget: MB_CONTEXT_MAX_BYTES=0 disables the cap" {
  MB_CONTEXT_MAX_BYTES=0 bash "$SCRIPT" "$FIXTURE" > "$TMPDIR_T/out.txt"
  assert_unchanged "$TMPDIR_T/out.txt" "$EXPECTED"
}

@test "context budget: .mb-config context_max_bytes honoured, env wins over file" {
  echo "context_max_bytes=0" > "$FIXTURE/.mb-config"
  bash "$SCRIPT" "$FIXTURE" > "$TMPDIR_T/cfg.txt"
  assert_unchanged "$TMPDIR_T/cfg.txt" "$EXPECTED"
  # env overrides the file: 4096 trims what `context_max_bytes=0` left whole.
  MB_CONTEXT_MAX_BYTES=4096 bash "$SCRIPT" "$FIXTURE" > "$TMPDIR_T/env.txt"
  assert_grep -q '^\[context\] status\.md: shown ' "$TMPDIR_T/env.txt"
  refute_grep -q '^## Section 1$' "$TMPDIR_T/env.txt"
}

@test "context budget: invalid cap falls back to the default" {
  MB_CONTEXT_MAX_BYTES=not-a-number bash "$SCRIPT" "$FIXTURE" > "$TMPDIR_T/out.txt"
  assert_grep -q '^## Section 1$' "$TMPDIR_T/out.txt"
  refute_grep -q '^## Section 2$' "$TMPDIR_T/out.txt"
}

@test "context budget: symlink and out-of-bank core file still skipped (I-082)" {
  local bank="$TMPDIR_T/sym/.memory-bank"
  mkdir -p "$bank" "$TMPDIR_T/sym/outside"
  printf '# Status\n\nok\n' > "$bank/status.md"
  printf 'SECRET-OUTSIDE\n' > "$TMPDIR_T/sym/outside/roadmap.md"
  ln -s "$TMPDIR_T/sym/outside/roadmap.md" "$bank/roadmap.md"
  bash "$SCRIPT" "$bank" > "$TMPDIR_T/out.txt" 2> "$TMPDIR_T/err.txt"
  refute_grep -q 'SECRET-OUTSIDE' "$TMPDIR_T/out.txt"
  assert_grep -q 'skip symlink' "$TMPDIR_T/err.txt"
}
