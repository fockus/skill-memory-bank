#!/usr/bin/env bats
# Lock release honesty (S4 round-2 findings 3 and 4):
#   [3] scripts/mb-backlog-state.sh must not print a success line when the lock
#       it held could not be released.
#   [4] scripts/_lib.sh mb_lock_release must not treat a lock path that exists
#       as a NON-directory (regular file, dangling symlink) as "already gone".
#
# Red-anchor: every test name starts with `lock_corruption: `.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  TMPROOT="$(mktemp -d)"
  LOCK="$TMPROOT/x.lock"

  cat > "$TMPROOT/lockcli" <<EOF
#!/usr/bin/env bash
source "$REPO_ROOT/scripts/_lib.sh"
"\$@"
EOF
  chmod +x "$TMPROOT/lockcli"
}

teardown() {
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

acquire() { run --separate-stderr bash "$TMPROOT/lockcli" mb_lock_acquire "$@"; }
release() { run --separate-stderr bash "$TMPROOT/lockcli" mb_lock_release "$@"; }

# Build an isolated copy of the scripts a backlog mutation needs, so a stub can
# make mb_lock_release fail deterministically without touching the repo.
# $1 = replacement body for mb_lock_release.
make_faulty_scripts() {
  local body="$1" dir="$TMPROOT/scripts"
  mkdir -p "$dir"
  cp "$REPO_ROOT/scripts/mb-backlog-state.sh" "$dir/"
  cp "$REPO_ROOT/scripts/_lib.sh" "$dir/"
  cp "$REPO_ROOT/scripts/mb_backlog_state_engine.py" "$dir/"
  cp "$REPO_ROOT/scripts/mb_fs_atomic.py" "$dir/"
  cp "$REPO_ROOT/scripts/mb_backlog_validate.py" "$dir/"
  # Append an override AFTER the original definition — last definition wins.
  printf '\n%s\n' "$body" >> "$dir/_lib.sh"
  echo "$dir/mb-backlog-state.sh"
}

mkbank() {
  BANK="$TMPROOT/.memory-bank"
  mkdir -p "$BANK"
  cat > "$BANK/backlog.md" <<'EOF'
# Backlog

## Ideas

### I-001 — alpha idea [MED, NEW, 2026-04-01]

## Out of scope
EOF
}

# ═══════════════════════════════════════════════════════════════
# [4] A lock path that exists but is not a directory is CORRUPT
# ═══════════════════════════════════════════════════════════════

@test "lock_corruption: release on a lock path that is a regular file reports failure" {
  : > "$LOCK"
  release "$LOCK" "123-4"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"code=lock_corrupt"* ]]
  [ -f "$LOCK" ]        # left in place for a human to inspect, not silently removed
}

@test "lock_corruption: release on a dangling symlink lock path reports failure" {
  ln -s "$TMPROOT/no-such-target" "$LOCK"
  release "$LOCK" "123-4"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"code=lock_corrupt"* ]]
  [ -L "$LOCK" ]
}

@test "lock_corruption: a truly absent lock still releases successfully (exit 0)" {
  # The contract's legitimate 0: nothing to release because nothing is there.
  [ ! -e "$LOCK" ]
  release "$LOCK" "123-4"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "lock_corruption: a corrupt lock path is reported at once, not after the timeout" {
  # R4-004 upgraded this contract. acquire used to treat a non-directory lock
  # path as "busy" and burn its whole timeout before failing with lock_timeout,
  # which named the wrong problem. It now fails closed and immediately: the
  # object is not a directory, so we refuse rather than glob into it.
  : > "$LOCK"
  release "$LOCK" "123-4"
  [ "$status" -ne 0 ]
  acquire "$LOCK" 1 100
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"code=lock_corrupt"* ]]
  [ -f "$LOCK" ]   # and the object it refused to touch is still there
}

@test "lock_corruption: normal acquire/release round-trip is unaffected" {
  acquire "$LOCK" 2 100
  [ "$status" -eq 0 ]
  local token="$output"
  release "$LOCK" "$token"
  [ "$status" -eq 0 ]
  [ ! -e "$LOCK" ]
}

# ═══════════════════════════════════════════════════════════════
# [3] A failed release must not be reported as a successful mutation
# ═══════════════════════════════════════════════════════════════

@test "lock_corruption: transition does not print success when release fails" {
  mkbank
  local bs
  bs="$(make_faulty_scripts 'mb_lock_release() { return 1; }')"
  run --separate-stderr bash "$bs" transition I-001 NEEDS-INFO --mb "$BANK"
  [ "$status" -ne 0 ]
  [ -z "$output" ]                                  # no `item=... new_state=...`
  [[ "$stderr" == *"code=lock_release_failed"* ]]
}

@test "lock_corruption: annotate does not print success when release fails" {
  mkbank
  local bs
  bs="$(make_faulty_scripts 'mb_lock_release() { return 1; }')"
  run --separate-stderr bash "$bs" annotate I-001 --brief "the system must retry when the call fails" --mb "$BANK"
  [ "$status" -ne 0 ]
  [ -z "$output" ]                                  # no `item=... annotated`
  [[ "$stderr" == *"code=lock_release_failed"* ]]
}

@test "lock_corruption: the mutation itself is still durable when release fails" {
  # Release failing is a lock-hygiene fault, not a reason to lose the write that
  # already landed — the caller must learn about it, but the data must be intact.
  mkbank
  local bs
  bs="$(make_faulty_scripts 'mb_lock_release() { return 1; }')"
  run bash "$bs" transition I-001 NEEDS-INFO --mb "$BANK"
  [ "$status" -ne 0 ]
  grep -qF '### I-001 — alpha idea [MED, NEEDS-INFO, 2026-04-01]' "$BANK/backlog.md"
}

@test "lock_corruption: a healthy release still yields the normal success line" {
  mkbank
  local bs
  bs="$(make_faulty_scripts '# no override; real mb_lock_release stands')"
  run --separate-stderr bash "$bs" transition I-001 NEEDS-INFO --mb "$BANK"
  [ "$status" -eq 0 ]
  [ "$output" = "item=I-001 old_state=NEW new_state=NEEDS-INFO" ]
  [ ! -e "$BANK/.locks/backlog.lock" ]
}
