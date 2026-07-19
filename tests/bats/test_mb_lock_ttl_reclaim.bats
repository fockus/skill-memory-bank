#!/usr/bin/env bats
# scripts/_lib.sh mb_lock_acquire — owner-less TTL reclaim across processes.
#
# Split out of test_mb_lock_helper.bats to keep both files under the 400-line
# project gate (same precedent as test_mb_roadmap_sync_bootstrap.bats).
#
# Red-anchor: every test name starts with `lock_helper: `.

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

# ── R3-009: the owner-less generation's age must be DURABLE ──────────────────
# `ownerless_since` used to live only inside one acquire call. With the shipped
# mb-backlog-state defaults (timeout=10, ttl=120) every call gave up long before
# ttl and forgot what it had seen, so an hour-old EMPTY lock was permanently
# unreclaimable no matter how many times it was retried. The age now comes from
# the lock dir's own mtime, which survives across processes.

# Age a path so it looks like it went owner-less <seconds> ago (BSD + GNU touch).
age_path() {
  local path="$1" secs="$2" stamp
  stamp="$(date -v-"${secs}"S +%Y%m%d%H%M.%S 2>/dev/null \
    || date -d "@$(( $(date +%s) - secs ))" +%Y%m%d%H%M.%S)"
  touch -t "$stamp" "$path"
}

@test "lock_helper: an already-stale owner-less lock is reclaimed when timeout < ttl" {
  mkdir -p "$LOCK"
  age_path "$LOCK" 3600              # went owner-less an hour ago
  acquire "$LOCK" 1 120              # timeout=1 < ttl=120: the old code timed out forever
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+-[0-9]+$ ]]
  [ -d "$LOCK/owner.$output" ]
}

@test "lock_helper: a stale owner-less lock is reclaimed at the shipped defaults" {
  mkdir -p "$LOCK"
  age_path "$LOCK" 3600
  acquire "$LOCK" 10 120             # exactly mb-backlog-state's defaults
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+-[0-9]+$ ]]
}

@test "lock_helper: a FRESH owner-less lock is still protected until ttl" {
  mkdir -p "$LOCK"                   # just created ⇒ mtime is now
  acquire "$LOCK" 1 120              # ttl not elapsed ⇒ must NOT be reclaimed
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [[ "$stderr" == *"code=lock_timeout"* ]]
  [ -d "$LOCK" ]
}

@test "lock_helper: an aged lock with a LIVE owner is never reclaimed" {
  mkdir -p "$LOCK/owner.$$-9"        # $$ = the bats test PID, alive
  age_path "$LOCK" 3600
  acquire "$LOCK" 1 2                # stale by mtime, but the owner is alive
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"code=lock_timeout"* ]]
  [ -d "$LOCK/owner.$$-9" ]
}

