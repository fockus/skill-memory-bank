#!/usr/bin/env bats
# mb-status-rotate.sh — archive dated `## ` sections of status.md into progress.md.
#
# Contract:
#   Dated sections (heading contains YYYY-MM-DD) beyond the first --keep N
#   (default 3, file order) move verbatim into progress.md as
#   `## [status archive] <heading text>` blocks, written through the locked
#   append-only helper. Undated sections never move and the order of what
#   remains is unchanged. --dry-run (default) writes nothing; --apply leaves a
#   `.status.md.bak.<ts>` and is idempotent. A failed append aborts before
#   status.md is touched — no section is ever lost.

load 'lib/assert'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-status-rotate.sh"
  TMPDIR_T="$(mktemp -d)"
  BANK="$TMPDIR_T/bank/.memory-bank"
  mkdir -p "$BANK"
  # 6 dated sections (newest first) interleaved with 3 undated ones.
  cat > "$BANK/status.md" <<'EOF'
# Status

Preamble line before the first section.

## Current phase
Working on rotation.

## 🟡 2026-09-06 — d1
- d1 body

## ✅ 2026-09-05 — d2
- d2 body

## ⏭ Следующий шаг
- next thing

## ✅ 2026-09-04 — d3
- d3 body

## ⏸ PAUSE 2026-09-03 — d4
- d4 body

## Open backlog
- b1

## ✅ 2026-09-02 — d5
- d5 body

## ✅ 2026-09-01 — d6
- d6 body
EOF
  printf '# Progress\n\n## 2026-01-01 — seed\n- seed entry\n' > "$BANK/progress.md"
}

teardown() {
  [ -n "${TMPDIR_T:-}" ] && rm -rf "$TMPDIR_T"
}

@test "status rotate: dated sections beyond --keep are moved to progress.md verbatim" {
  run bash "$SCRIPT" --apply --mb "$BANK"
  [ "$status" -eq 0 ]

  # d4, d5, d6 archived; d1..d3 stay.
  assert_grep -qxF -e '## [status archive] ⏸ PAUSE 2026-09-03 — d4' "$BANK/progress.md"
  assert_grep -qxF -e '## [status archive] ✅ 2026-09-02 — d5' "$BANK/progress.md"
  assert_grep -qxF -e '## [status archive] ✅ 2026-09-01 — d6' "$BANK/progress.md"
  assert_grep -qxF -e '- d6 body' "$BANK/progress.md"
  refute_grep -qxF -e '## [status archive] 🟡 2026-09-06 — d1' "$BANK/progress.md"

  refute_grep -qxF -e '## ✅ 2026-09-01 — d6' "$BANK/status.md"
  refute_grep -qxF -e '- d6 body' "$BANK/status.md"
  assert_grep -qxF -e '## 🟡 2026-09-06 — d1' "$BANK/status.md"

  # Seed entry survived (append-only), order of survivors unchanged.
  assert_grep -qxF -e '## 2026-01-01 — seed' "$BANK/progress.md"
  run bash -c "awk '/^## /{print}' '$BANK/status.md'"
  [ "${lines[0]}" = '## Current phase' ]
  [ "${lines[1]}" = '## 🟡 2026-09-06 — d1' ]
  [ "${lines[2]}" = '## ✅ 2026-09-05 — d2' ]
  [ "${lines[3]}" = '## ⏭ Следующий шаг' ]
  [ "${lines[4]}" = '## ✅ 2026-09-04 — d3' ]
  [ "${lines[5]}" = '## Open backlog' ]
  [ "${#lines[@]}" -eq 6 ]
}

@test "status rotate: undated sections are never moved" {
  run bash "$SCRIPT" --apply --keep 0 --mb "$BANK"
  [ "$status" -eq 0 ]

  # All six dated sections archived...
  run bash -c "awk '/^## \\[status archive\\]/' '$BANK/progress.md' | wc -l"
  [ "$(echo "$output" | tr -d ' ')" -eq 6 ]
  # ...and not one undated heading followed them.
  refute_grep -qF -e '[status archive] Current phase' "$BANK/progress.md"
  refute_grep -qF -e '[status archive] Open backlog' "$BANK/progress.md"
  refute_grep -qF -e '[status archive] ⏭' "$BANK/progress.md"
  assert_grep -qxF -e '## Current phase' "$BANK/status.md"
  assert_grep -qxF -e '## ⏭ Следующий шаг' "$BANK/status.md"
  assert_grep -qxF -e '## Open backlog' "$BANK/status.md"
  assert_grep -qxF -e 'Preamble line before the first section.' "$BANK/status.md"
}

@test "status rotate: --keep 5 keeps five" {
  run bash "$SCRIPT" --apply --keep 5 --mb "$BANK"
  [ "$status" -eq 0 ]

  run bash -c "awk '/^## \\[status archive\\]/' '$BANK/progress.md' | wc -l"
  [ "$(echo "$output" | tr -d ' ')" -eq 1 ]
  assert_grep -qxF -e '## [status archive] ✅ 2026-09-01 — d6' "$BANK/progress.md"
  assert_grep -qxF -e '## ✅ 2026-09-02 — d5' "$BANK/status.md"
}

@test "status rotate: dry-run writes nothing" {
  snapshot "$BANK/status.md" "$TMPDIR_T/status.before"
  snapshot "$BANK/progress.md" "$TMPDIR_T/progress.before"

  run bash "$SCRIPT" --mb "$BANK"
  [ "$status" -eq 0 ]
  assert_substring "$output" '2026-09-01 — d6'

  assert_unchanged "$BANK/status.md" "$TMPDIR_T/status.before"
  assert_unchanged "$BANK/progress.md" "$TMPDIR_T/progress.before"
  refute_cmd bash -c "ls '$BANK'/.status.md.bak.* 2>/dev/null | grep -q ."
}

@test "status rotate: apply writes backup and is idempotent (second run = no-op)" {
  snapshot "$BANK/status.md" "$TMPDIR_T/status.orig"

  run bash "$SCRIPT" --apply --mb "$BANK"
  [ "$status" -eq 0 ]
  # Backup holds the pre-mutation content byte for byte.
  run bash -c "ls '$BANK'/.status.md.bak.* | wc -l"
  [ "$(echo "$output" | tr -d ' ')" -eq 1 ]
  run bash -c "cmp '$TMPDIR_T/status.orig' \"\$(ls '$BANK'/.status.md.bak.*)\""
  [ "$status" -eq 0 ]

  snapshot "$BANK/status.md" "$TMPDIR_T/status.after1"
  snapshot "$BANK/progress.md" "$TMPDIR_T/progress.after1"

  run bash "$SCRIPT" --apply --mb "$BANK"
  [ "$status" -eq 0 ]
  assert_unchanged "$BANK/status.md" "$TMPDIR_T/status.after1"
  assert_unchanged "$BANK/progress.md" "$TMPDIR_T/progress.after1"
  # No-op does not leave a second backup behind.
  run bash -c "ls '$BANK'/.status.md.bak.* | wc -l"
  [ "$(echo "$output" | tr -d ' ')" -eq 1 ]
}

@test "status rotate: progress.md append goes through the locked helper (lock file respected)" {
  snapshot "$BANK/status.md" "$TMPDIR_T/status.before"
  snapshot "$BANK/progress.md" "$TMPDIR_T/progress.before"

  # Live foreign owner of the append lock — the helper fail-safes to exit 0
  # WITHOUT appending, so rotate must notice the missing block and abort.
  mkdir -p "$BANK/.work-progress.lock"
  printf '%s' "99999-foreign" > "$BANK/.work-progress.lock/owner"

  MB_PROGRESS_APPEND_LOCK_TIMEOUT=1 run bash "$SCRIPT" --apply --mb "$BANK"
  [ "$status" -ne 0 ]

  assert_unchanged "$BANK/status.md" "$TMPDIR_T/status.before"
  assert_unchanged "$BANK/progress.md" "$TMPDIR_T/progress.before"
  refute_grep -qF -e '[status archive]' "$BANK/progress.md"
  refute_cmd bash -c "ls '$BANK'/.status.md.bak.* 2>/dev/null | grep -q ."
}

@test "status rotate: status.md with fewer than N dated sections is untouched byte-for-byte" {
  small="$TMPDIR_T/small/.memory-bank"
  mkdir -p "$small"
  printf '# Status\n\n## Current phase\nx\n\n## ✅ 2026-09-05 — only one\n- body\n' > "$small/status.md"
  printf '# Progress\n' > "$small/progress.md"
  snapshot "$small/status.md" "$TMPDIR_T/small.status"
  snapshot "$small/progress.md" "$TMPDIR_T/small.progress"

  run bash "$SCRIPT" --apply --mb "$small"
  [ "$status" -eq 0 ]
  assert_unchanged "$small/status.md" "$TMPDIR_T/small.status"
  assert_unchanged "$small/progress.md" "$TMPDIR_T/small.progress"
}

@test "status rotate: real bank snapshot — keep 3 leaves 3 dated + 9 undated, 6 archived" {
  real="$TMPDIR_T/real/.memory-bank"
  mkdir -p "$real"
  cp "$REPO_ROOT/tests/fixtures/status-rotate/status.md" "$real/status.md"
  printf '# Progress\n' > "$real/progress.md"

  run bash "$SCRIPT" --apply --keep 3 --mb "$real"
  [ "$status" -eq 0 ]

  run bash -c "awk '/^## /{ if (\$0 ~ /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) d++; else u++ } END{print d, u}' '$real/status.md'"
  [ "$output" = "3 9" ]
  run bash -c "awk '/^## \\[status archive\\]/' '$real/progress.md' | wc -l"
  [ "$(echo "$output" | tr -d ' ')" -eq 6 ]
}
