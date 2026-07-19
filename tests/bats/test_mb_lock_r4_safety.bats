#!/usr/bin/env bats
# scripts/_lib.sh lock helper — R4 safety: EPERM liveness, token grammar and
# symlinked lock paths.
#
# Red-anchor: every test name starts with `lock_helper: `.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  TMPROOT="$(mktemp -d)"
  LOCK="$TMPROOT/x.lock"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf 'source "%s/scripts/_lib.sh"\n' "$REPO_ROOT"
    printf '%s\n' '"$@"'
  } > "$TMPROOT/lockcli"
  chmod +x "$TMPROOT/lockcli"
}

teardown() {
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

acquire() { run --separate-stderr bash "$TMPROOT/lockcli" mb_lock_acquire "$@"; }
release() { run --separate-stderr bash "$TMPROOT/lockcli" mb_lock_release "$@"; }

# ── R4-001: EPERM means ALIVE, not dead ──────────────────────────────────────
# PID 1 always exists. For an unprivileged user `kill -0 1` fails with EPERM,
# which the old reclaim read as "dead owner" — so in a group-writable bank
# another OS user's live holder was evicted and two writers entered backlog.md.
# Deterministic either way: as root kill -0 succeeds and the owner is alive too.

@test "lock_helper: an owner PID that exists but is not signalable counts as ALIVE" {
  mkdir -p "$LOCK/owner.1-7"          # PID 1: exists, usually not signalable
  acquire "$LOCK" 2 120
  [ "$status" -eq 1 ]                 # refused — the holder is alive
  [[ "$stderr" == *"code=lock_timeout"* ]]
  [ -d "$LOCK/owner.1-7" ]            # and its marker was NOT reclaimed
}

@test "lock_helper: mb_pid_alive reports PID 1 alive and an absurd PID gone" {
  run bash "$TMPROOT/lockcli" mb_pid_alive 1
  [ "$status" -eq 0 ]
  run bash "$TMPROOT/lockcli" mb_pid_alive 99999999
  [ "$status" -eq 1 ]
}

@test "lock_helper: a genuinely dead owner is still reclaimed (no over-correction)" {
  mkdir -p "$LOCK/owner.99999999-7"
  acquire "$LOCK" 3 120
  [ "$status" -eq 0 ]
  [ ! -d "$LOCK/owner.99999999-7" ]
}

# ── R4-003: the token is pasted into a path, so it must BE a token ───────────

@test "lock_helper: a traversal token deletes nothing and fails" {
  mkdir -p "$LOCK/owner.123-4" "$TMPROOT/victim"
  release "$LOCK" "123-4/../../victim"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"code=lock_usage"* ]]
  [ -d "$TMPROOT/victim" ]            # the sibling directory survives
  [ -d "$LOCK/owner.123-4" ]          # and the real owner is untouched
}

@test "lock_helper: other malformed tokens are refused without touching the lock" {
  mkdir -p "$LOCK/owner.123-4"
  for bad in "../x" "a-b" "1-" "-1" "1_2"; do
    release "$LOCK" "$bad"
    [ "$status" -eq 1 ]
  done
  [ -d "$LOCK/owner.123-4" ]
}

@test "lock_helper: a well-formed token still releases normally" {
  acquire "$LOCK" 2 100
  [ "$status" -eq 0 ]
  release "$LOCK" "$output"
  [ "$status" -eq 0 ]
  [ ! -d "$LOCK" ]
}

# ── R4-004: never traverse a symlinked lock path ────────────────────────────

@test "lock_helper: acquire refuses a symlinked lock path without touching the target" {
  mkdir -p "$TMPROOT/external/owner.99999999-7"
  ln -s "$TMPROOT/external" "$LOCK"
  acquire "$LOCK" 1 120
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"code=lock_corrupt"* ]]
  # the dead-looking marker OUTSIDE the lock dir must survive: a reclaim that
  # followed the link deleted an object the lock never owned
  [ -d "$TMPROOT/external/owner.99999999-7" ]
}

@test "lock_helper: release refuses a symlinked lock path without touching the target" {
  mkdir -p "$TMPROOT/external/owner.123-4"
  ln -s "$TMPROOT/external" "$LOCK"
  release "$LOCK" "123-4"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"code=lock_corrupt"* ]]
  [ -d "$TMPROOT/external/owner.123-4" ]
}
