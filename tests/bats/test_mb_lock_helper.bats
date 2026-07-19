#!/usr/bin/env bats
# Tests for scripts/_lib.sh lock helper — S4 Task 2 (design.md C6, R3-001).
#
# Contract:
#   mb_lock_acquire <lock_dir> <timeout> <ttl>
#     acquire: stdout EXACTLY `<PID>-<RANDOM>` + \n, exit 0
#     timeout: stdout empty, stderr `code=lock_timeout lock=<JSON>`, exit 1
#     bad args: stdout empty, stderr `code=lock_usage`, exit 2
#   mb_lock_release <lock_dir> <token>
#     stdout empty; removes only <lock_dir>/owner.<token> then empty <lock_dir>;
#     exit 0 (own owner OR lock absent), exit 1 (foreign token, deletes nothing)
#   Reclaim: owner-marker + targeted rmdir keyed on kill -0 liveness — no mv/rm -rf.
#
# Red-anchor: every test name starts with `lock_helper: `.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  TMPROOT="$(mktemp -d)"
  LOCK="$TMPROOT/x.lock"
  DEAD="99999999-7"   # kill -0 on this PID fails ⇒ treated as dead owner

  # Dispatcher runs a helper (or the extracted mb-agree private lock) in its own
  # process, so the bats test shell keeps normal set -e failure detection.
  sed -n '117,176p' "$REPO_ROOT/scripts/mb-agree.sh" > "$TMPROOT/agree_lock.sh"
  cat > "$TMPROOT/lockcli" <<EOF
#!/usr/bin/env bash
source "$REPO_ROOT/scripts/_lib.sh"
source "$TMPROOT/agree_lock.sh"
"\$@"
EOF
  chmod +x "$TMPROOT/lockcli"
}

teardown() {
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

acquire() { run --separate-stderr bash "$TMPROOT/lockcli" mb_lock_acquire "$@"; }
release() { run --separate-stderr bash "$TMPROOT/lockcli" mb_lock_release "$@"; }

# ═══════════════════════════════════════════════════════════════
# Acquire / release contract
# ═══════════════════════════════════════════════════════════════

@test "lock_helper: acquire on a free lock prints PID-RANDOM and exit 0" {
  acquire "$LOCK" 2 100
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+-[0-9]+$ ]]
  [ -d "$LOCK" ]
  [ -d "$LOCK/owner.$output" ]
}

@test "lock_helper: acquire refuses (timeout) when a live owner holds the lock" {
  mkdir -p "$LOCK/owner.$$-1"   # $$ = the bats test PID, alive
  acquire "$LOCK" 1 100
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [[ "$stderr" == *"code=lock_timeout"* ]]
  [[ "$stderr" == *"lock="* ]]
}

@test "lock_helper: reclaims a dead owner marker and acquires" {
  mkdir -p "$LOCK/owner.$DEAD"
  acquire "$LOCK" 3 100
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+-[0-9]+$ ]]
  [ ! -d "$LOCK/owner.$DEAD" ]
}

@test "lock_helper: release with own token removes owner marker and empty lock" {
  acquire "$LOCK" 2 100
  token="$output"
  # re-create the marker the acquire's short-lived process left (it removed
  # nothing; the dir persists) — assert release removes it and the empty lock.
  [ -d "$LOCK/owner.$token" ]
  release "$LOCK" "$token"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -d "$LOCK" ]
}

@test "lock_helper: release is idempotent when the lock is absent (exit 0)" {
  release "$LOCK" "1234-5"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "lock_helper: release with a foreign token deletes nothing and exits 1" {
  mkdir -p "$LOCK/owner.$$-9"    # someone else's live marker
  release "$LOCK" "4242-4"
  [ "$status" -eq 1 ]
  [ -d "$LOCK/owner.$$-9" ]      # untouched
  [ -d "$LOCK" ]
}

# ═══════════════════════════════════════════════════════════════
# Argument validation
# ═══════════════════════════════════════════════════════════════

@test "lock_helper: empty lock dir arg exits 2 with code=lock_usage" {
  acquire "" 2 100
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == *"code=lock_usage"* ]]
}

@test "lock_helper: non-numeric timeout exits 2 with code=lock_usage" {
  acquire "$LOCK" abc 100
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"code=lock_usage"* ]]
}

@test "lock_helper: non-numeric ttl exits 2 with code=lock_usage" {
  acquire "$LOCK" 2 xyz
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"code=lock_usage"* ]]
}

# ═══════════════════════════════════════════════════════════════
# Divergence protocol (R3-001) — targeted rmdir, never mv/rm -rf
# ═══════════════════════════════════════════════════════════════

@test "lock_helper: targeted rmdir of dead marker leaves a fresh sibling owner" {
  mkdir -p "$LOCK/owner.$$-Z"        # fresh live holder Z
  # X's already-decided reclaim of the dead token D:
  rmdir "$LOCK/owner.$DEAD" 2>/dev/null || true   # ENOENT — harmless
  rmdir "$LOCK" 2>/dev/null || true               # ENOTEMPTY — refused
  [ -d "$LOCK/owner.$$-Z" ]          # survivor: single holder preserved
  [ -d "$LOCK" ]
}

@test "lock_helper: PID-reuse safe — a live-PID owner is never reclaimed" {
  mkdir -p "$LOCK/owner.$$-2"        # PID $$ is alive (models a reused PID)
  acquire "$LOCK" 1 1
  [ "$status" -eq 1 ]               # conservative non-reclaim ⇒ loud timeout
  [ -d "$LOCK/owner.$$-2" ]
}

@test "lock_helper: owner-less lock is reclaimed only after ttl seconds" {
  mkdir -p "$LOCK"                   # lock dir with NO owner.* marker
  acquire "$LOCK" 5 1                # ttl=1 < timeout=5 ⇒ reclaim then acquire
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+-[0-9]+$ ]]
}

# ═══════════════════════════════════════════════════════════════
# Real-concurrency mutual exclusion (subprocess/barrier — R3-001)
# ═══════════════════════════════════════════════════════════════
# The manual-replay divergence cases above assert the SHAPE of a single
# already-decided reclaim step; they never launch competing acquire/reclaim
# processes, so a live C6 race passes them. These cases run real subprocesses
# through a barrier and assert AT MOST ONE holder survives.

# Contender: source _lib.sh, wait on the barrier, try one acquire, record the
# outcome. With held/rel set, the winner KEEPS ITS PID ALIVE while holding (so
# its liveness marker is not reclaimable mid-check) until released or timed out.
_write_contender() {
  cat > "$TMPROOT/contender" <<EOF
#!/usr/bin/env bash
source "$REPO_ROOT/scripts/_lib.sh"
go="\$1"; res="\$2"; lock="\$3"; to="\$4"; ttl="\$5"; held="\${6:-}"; rel="\${7:-}"
while [ ! -e "\$go" ]; do :; done
if tok="\$(mb_lock_acquire "\$lock" "\$to" "\$ttl" 2>/dev/null)"; then
  printf 'win %s\n' "\$tok" > "\$res"
  if [ -n "\$held" ]; then
    : > "\$held"
    n=0
    while [ ! -e "\$rel" ] && [ "\$n" -lt 400 ]; do sleep 0.01; n=\$((n + 1)); done
  fi
else
  printf 'lose\n' > "\$res"
fi
EOF
}

@test "lock_helper: two concurrent acquires — at most one holder at any instant" {
  _write_contender
  local go="$TMPROOT/go" r1="$TMPROOT/r1" r2="$TMPROOT/r2"
  local held="$TMPROOT/held" rel="$TMPROOT/rel"
  bash "$TMPROOT/contender" "$go" "$r1" "$LOCK" 3 100 "$held" "$rel" & local p1=$!
  bash "$TMPROOT/contender" "$go" "$r2" "$LOCK" 3 100 "$held" "$rel" & local p2=$!
  : > "$go"                                # release both simultaneously
  local i=0
  while [ ! -e "$held" ] && [ "$i" -lt 500 ]; do sleep 0.01; i=$((i + 1)); done
  [ -e "$held" ]                           # one contender acquired and holds it
  # While that holder is alive, the loser is locked out ⇒ exactly one marker.
  local owners
  owners=$(find "$LOCK" -maxdepth 1 -name 'owner.*' 2>/dev/null | grep -c . || true)
  [ "$owners" -eq 1 ]
  : > "$rel"                               # release the holder
  wait "$p1" || true; wait "$p2" || true
}

@test "lock_helper: a lagging reclaimer never deletes a fresh sibling lock (single holder, R3-001)" {
  # Two reclaimers of a dead owner D race a fresh winner Z that is inside its
  # mkdir→owner-marker window (lock dir present, owner.Z not yet). A `kill` seam
  # freezes the LAGGING reclaimer X exactly at its liveness check so the
  # interleaving is deterministic: Y reclaims D + the lock, Z re-wins a fresh
  # (still owner-less) lock, THEN X runs its already-decided reclaim. X must NOT
  # remove Z's fresh lock — on ENOENT of `rmdir owner.D` it must back off, not
  # `rmdir` a dir it never owned. Buggy code deletes Z's empty lock and acquires
  # → two holders; fixed code times out.
  mkdir -p "$LOCK/owner.$DEAD"
  local decided="$TMPROOT/decided" go="$TMPROOT/go"
  cat > "$TMPROOT/xcli" <<EOF
#!/usr/bin/env bash
source "$REPO_ROOT/scripts/_lib.sh"
kill() {
  if [ "\$1" = "-0" ] && [ "\$2" = "${DEAD%%-*}" ]; then
    : > "$decided"
    while [ ! -e "$go" ]; do :; done
    return 1
  fi
  command kill "\$@"
}
mb_lock_acquire "$LOCK" 2 100
EOF
  bash "$TMPROOT/xcli" >/dev/null 2>&1 & local xpid=$!
  local i=0
  while [ ! -e "$decided" ] && [ "$i" -lt 500 ]; do sleep 0.01; i=$((i + 1)); done
  [ -e "$decided" ]                       # X is frozen at its liveness check
  rmdir "$LOCK/owner.$DEAD"                # Y reclaims the dead marker
  rmdir "$LOCK"                            # Y removes the now-empty lock
  command mkdir "$LOCK"                    # Z wins a FRESH, owner-less lock
  : > "$go"                                # release the lagging X
  local xrc=0; wait "$xpid" || xrc=$?
  [ "$xrc" -ne 0 ]                         # X must not have reclaimed Z's lock
  [ -d "$LOCK" ]                           # Z's fresh lock survives
}

@test "lock_helper: acquire never reports success when its owner marker cannot be created" {
  # Model the mkdir→owner window losing the lock dir under the winner: a `mkdir`
  # seam fails exactly the owner-marker creation. The winner of the lock-dir gate
  # has NOT recorded liveness, so it must NOT return a token as success (buggy
  # `|| true` did). It retries and ultimately times out.
  cat > "$TMPROOT/mcli" <<EOF
#!/usr/bin/env bash
source "$REPO_ROOT/scripts/_lib.sh"
mkdir() {
  case "\$1" in
    */owner.*) return 1 ;;               # fresh lock vanished before the marker
    *) command mkdir "\$@" ;;
  esac
}
mb_lock_acquire "$LOCK" 1 100
EOF
  run --separate-stderr bash "$TMPROOT/mcli"
  [ "$status" -ne 0 ]                      # never a false success
  [ -z "$output" ]                         # and never a bare token on stdout
}

@test "lock_helper: owner-less TTL ABA — a stalled winner never co-owns B's generation" {
  # ABA: A wins `mkdir lock` then STALLS before its owner marker; B reclaims the
  # owner-less dir by TTL, recreates it and publishes owner.B (a NEW generation);
  # A finally publishes owner.A INTO B's generation. Both markers would be live
  # and both acquires would report success — the double-owner defect. The fix
  # confirms sole ownership after the owner mkdir: A must see B's sibling marker,
  # drop ONLY its own and back off. Deterministic via an `mkdir` seam that
  # freezes A between `mkdir lock` and `mkdir owner`.
  _write_contender
  local atwin="$TMPROOT/atwin" ago="$TMPROOT/ago"
  local bgo="$TMPROOT/bgo" bheld="$TMPROOT/bheld" brel="$TMPROOT/brel"
  cat > "$TMPROOT/acli" <<EOF
#!/usr/bin/env bash
source "$REPO_ROOT/scripts/_lib.sh"
mkdir() {
  case "\$1" in
    */owner.*)
      : > "$atwin"                         # lock dir already made; freeze here
      while [ ! -e "$ago" ]; do sleep 0.01; done
      command mkdir "\$@" ;;               # then publish owner.A into B's gen
    *) command mkdir "\$@" ;;
  esac
}
mb_lock_acquire "$LOCK" 3 100
EOF
  bash "$TMPROOT/acli" >"$TMPROOT/aout" 2>/dev/null & local apid=$!
  local i=0
  while [ ! -e "$atwin" ] && [ "$i" -lt 500 ]; do sleep 0.01; i=$((i + 1)); done
  [ -e "$atwin" ]                          # A holds an owner-less lock, frozen
  # B reclaims the owner-less dir (ttl=0), recreates it and holds owner.B.
  : > "$bgo"
  bash "$TMPROOT/contender" "$bgo" "$TMPROOT/bres" "$LOCK" 3 0 "$bheld" "$brel" & local bpid=$!
  i=0
  while [ ! -e "$bheld" ] && [ "$i" -lt 500 ]; do sleep 0.01; i=$((i + 1)); done
  [ -e "$bheld" ]                          # B owns the fresh generation
  : > "$ago"                               # release A into B's generation
  local arc=0; wait "$apid" || arc=$?
  [ "$arc" -ne 0 ]                         # A must NOT co-own — ABA rejected
  local owners
  owners=$(find "$LOCK" -maxdepth 1 -name 'owner.*' 2>/dev/null | grep -c . || true)
  [ "$owners" -eq 1 ]                      # exactly one live holder (B)
  : > "$brel"; wait "$bpid" || true
}

# ═══════════════════════════════════════════════════════════════
# Parity + divergence vs mb-agree.sh private lock (design.md C6)
# ═══════════════════════════════════════════════════════════════

@test "lock_helper: parity vs mb-agree — both reclaim dead, both refuse live" {
  H="$TMPROOT/h.lock"; A="$TMPROOT/a.lock"
  mkdir -p "$H/owner.$DEAD"
  mkdir -p "$A"; printf '%s' "$DEAD" > "$A/owner"
  run --separate-stderr bash "$TMPROOT/lockcli" mb_lock_acquire "$H" 3 100
  [ "$status" -eq 0 ]
  run --separate-stderr bash "$TMPROOT/lockcli" _lock_acquire "$A" 3 100
  [ "$status" -eq 0 ]

  H2="$TMPROOT/h2.lock"; A2="$TMPROOT/a2.lock"
  mkdir -p "$H2/owner.$$-5"
  mkdir -p "$A2"; printf '%s' "$$-5" > "$A2/owner"
  run --separate-stderr bash "$TMPROOT/lockcli" mb_lock_acquire "$H2" 1 100
  [ "$status" -eq 1 ]
  run --separate-stderr bash "$TMPROOT/lockcli" _lock_acquire "$A2" 1 100
  [ "$status" -eq 1 ]
}

@test "lock_helper: divergence vs mb-agree — helper preserves fresh owner, agree destroys it" {
  # Helper: targeted rmdir leaves the fresh live owner intact.
  H="$TMPROOT/h.lock"; mkdir -p "$H/owner.$$-Z"
  rmdir "$H/owner.$DEAD" 2>/dev/null || true
  rmdir "$H" 2>/dev/null || true
  [ -d "$H/owner.$$-Z" ]

  # mb-agree: its decided reclaim is a blind rm -rf that WOULD destroy a fresh
  # lock — the documented known defect the helper closes.
  A="$TMPROOT/a.lock"; mkdir -p "$A"; printf '%s' "$$-Z" > "$A/owner"
  rm -rf "$A"                  # agree's reclaim action on a now-fresh lock
  [ ! -d "$A" ]               # destroyed (known defect, not fixed in agree)
}

# ═══════════════════════════════════════════════════════════════
# Portability
# ═══════════════════════════════════════════════════════════════

@test "lock_helper: works when the lock path contains spaces" {
  SPACED="$TMPROOT/with space/n.lock"
  mkdir -p "$TMPROOT/with space"
  acquire "$SPACED" 2 100
  [ "$status" -eq 0 ]
  token="$output"
  [ -d "$SPACED/owner.$token" ]
  release "$SPACED" "$token"
  [ "$status" -eq 0 ]
  [ ! -d "$SPACED" ]
}
