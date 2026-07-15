#!/usr/bin/env bats
# Tests for hooks/mb-update-notify.sh — SessionStart hook.
#
# The contract is silence: an up-to-date user (or any degraded/disabled path)
# sees NOTHING on stdout — not even a "you're up to date" line. Only an
# "update available" answer produces a short (<=3 line) notice.
#
# The resolver is stubbed via MB_VERSION_CHECK_BIN — the same seam pattern
# mb-version-check.sh itself uses for MB_VERSION_CHECK_FETCH_BIN — so no test
# here ever invokes the real resolver's network path.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  HOOK="$REPO_ROOT/hooks/mb-update-notify.sh"
  TMPDIR="$(mktemp -d)"

  [ -f "$HOOK" ] || skip "hooks/mb-update-notify.sh not implemented yet (TDD red phase)"
}

teardown() {
  [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ] && rm -rf "$TMPDIR"
}

# $1=filename $2=exit-code $3=stdout-body -> path to a chmod+x stub resolver.
# Records every invocation (one line per call) to $TMPDIR/calls.log so tests
# can assert "the resolver was never invoked", not just inspect its output.
fake_checker() {
  local path="$TMPDIR/$1"
  cat > "$path" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TMPDIR/calls.log"
printf '%s\n' '$3'
exit $2
EOF
  chmod +x "$path"
  printf '%s' "$path"
}

call_count() {
  [ -f "$TMPDIR/calls.log" ] || { echo 0; return 0; }
  wc -l < "$TMPDIR/calls.log" | tr -d ' '
}

# $1=filename $2=exit-code [$3=version_file $4=new_version] -> path to a
# chmod+x stub for scripts/mb-upgrade.sh. Records every invocation (one
# line, "$@") to $TMPDIR/upgrade-calls.log so tests can assert "the upgrade
# script was never invoked" (invariants 3/4), not just inspect its exit
# code. Never touches git/network — a pure stub.
#
# $3/$4 are optional: when given, the stub also OVERWRITES $version_file
# with $new_version before exiting — this is what a real `mb-upgrade.sh
# --force` does on a genuine install (git pull advances the checkout's own
# VERSION file). Tests proving the "genuinely advanced" claim (M1) use this;
# tests proving the "exited 0 but changed nothing" case omit it on purpose.
fake_upgrade() {
  local path="$TMPDIR/$1"
  local exit_code="$2"
  local version_file="${3:-}"
  local new_version="${4:-}"
  local bump_line=""
  if [ -n "$version_file" ]; then
    bump_line="printf '%s\n' '$new_version' > '$version_file'"
  fi
  cat > "$path" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TMPDIR/upgrade-calls.log"
$bump_line
exit $exit_code
EOF
  chmod +x "$path"
  printf '%s' "$path"
}

upgrade_call_count() {
  [ -f "$TMPDIR/upgrade-calls.log" ] || { echo 0; return 0; }
  wc -l < "$TMPDIR/upgrade-calls.log" | tr -d ' '
}

# $1=name -> a real, clean git repo under $TMPDIR (a plausible git-flavor
# skill root: VERSION file + a commit, nothing uncommitted). Also carries
# SKILL.md + scripts/mb-upgrade.sh + scripts/_lib.sh so this fixture also
# satisfies the hook's own strong bundle-identity gate (M3) by default —
# tests that need to prove that gate CLOSES build their own weaker root
# instead of using this helper.
make_clean_git_root() {
  local dir="$TMPDIR/$1"
  mkdir -p "$dir/scripts"
  printf '5.3.0\n' > "$dir/VERSION"
  printf '# Memory Bank Skill (test fixture)\n' > "$dir/SKILL.md"
  printf '#!/usr/bin/env bash\ntrue\n' > "$dir/scripts/mb-upgrade.sh"
  chmod +x "$dir/scripts/mb-upgrade.sh"
  printf '#!/usr/bin/env bash\ntrue\n' > "$dir/scripts/_lib.sh"
  (
    cd "$dir" && git init -q && git config user.email "test@test" \
      && git config user.name "Test" \
      && git add VERSION SKILL.md scripts/mb-upgrade.sh scripts/_lib.sh \
      && git commit -q -m init
  ) >/dev/null 2>&1

  # minor#2: prove the setup actually took. A swallowed git init/commit
  # failure (no git on PATH, a broken sandbox, ...) must fail THIS helper
  # loudly rather than silently hand back a directory with no ".git" at
  # all — a negative test asserting "upgrade never invoked" would then pass
  # for the WRONG reason (the hook's own `[ -d "$root/.git" ]` gate failing
  # closed on a non-repo) instead of because the fix under test works. Bats
  # runs test bodies under `set -e`, and a failing command-substitution
  # ASSIGNMENT (`root="$(make_clean_git_root ...)"`) does abort the test at
  # that line — so `return 1` here (before printing a path) is enough to
  # fail the calling test loudly, no per-call-site check needed.
  [ -d "$dir/.git" ] || {
    echo "make_clean_git_root: git init/commit did not create $dir/.git" >&2
    return 1
  }
  git -C "$dir" status >/dev/null 2>&1 || {
    echo "make_clean_git_root: git -C $dir status failed" >&2
    return 1
  }

  printf '%s' "$dir"
}

# Same as make_clean_git_root but with an uncommitted edit (dirty tree).
make_dirty_git_root() {
  local dir
  dir="$(make_clean_git_root "$1")"
  printf 'dirty\n' >> "$dir/VERSION"
  printf '%s' "$dir"
}

# Runs "$@" under the test's OWN hard deadline — no `timeout`/`gtimeout`
# dependency (same hand-rolled, no-orphan technique as the hook itself:
# `set -m` + a background `sleep`+negative-PID `kill`). This exists
# because a watchdog regression inside the hook must fail this suite FAST,
# not wedge it: a plain `run bash "$HOOK"` (or bats' own `run`, which reads
# the command's stdout/stderr to EOF exactly like a real host) blocks for
# as long as ANY process still holds those fds open — including an orphaned
# timer left behind by a broken watchdog — with no bound of its own.
#
# Sets: $capture_status, $capture_out, $capture_err, $capture_elapsed,
# $capture_timed_out (1 if the deadline fired and the whole group was
# killed, 0 if "$@" finished on its own).
run_with_deadline() {
  local deadline="$1"
  shift
  local outfile errfile start end
  outfile="$(mktemp "$TMPDIR/rwd-out.XXXXXX")"
  errfile="$(mktemp "$TMPDIR/rwd-err.XXXXXX")"

  start=$(date +%s)
  set -m
  ("$@" >"$outfile" 2>"$errfile") &
  local pid=$!
  (
    sleep "$deadline"
    kill -KILL -- "-$pid" 2>/dev/null
  ) >/dev/null 2>&1 &
  local watchdog=$!
  set +m

  # bats runs test bodies (and functions they call) under `set -e` — a
  # plain `wait` whose job was reaped via SIGKILL returns 128+9=137, and
  # under errexit that ABORTS THIS FUNCTION right here, before the caller
  # ever sees capture_status/capture_out. Every `wait` below is therefore
  # deliberately paired with `|| ...` so its own non-zero return is
  # "handled" (errexit only fires on an UNHANDLED failure) instead of
  # silently killing the assertions this helper exists to let run.
  capture_status=0
  wait "$pid" 2>/dev/null || capture_status=$?

  kill -KILL -- "-$watchdog" 2>/dev/null || true
  wait "$watchdog" 2>/dev/null || true
  end=$(date +%s)

  capture_elapsed=$((end - start))
  capture_out="$(cat "$outfile" 2>/dev/null)"
  capture_err="$(cat "$errfile" 2>/dev/null)"
  rm -f "$outfile" "$errfile"

  if [ "$capture_elapsed" -ge "$deadline" ]; then
    capture_timed_out=1
  else
    capture_timed_out=0
  fi
}

# ═══ update available ═══

@test "update-notify: update-available answer prints a <=3-line notice naming current -> latest and the exact upgrade_command" {
  local checker
  checker=$(fake_checker checker.sh 0 \
    '{"current": "5.3.0", "latest": "5.4.0", "update_available": true, "flavor": "pipx", "upgrade_command": "pipx upgrade memory-bank-skill", "checked_at": "2026-07-13T00:00:00Z", "source": "github"}')

  run --separate-stderr env MB_VERSION_CHECK_BIN="$checker" bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -le 3 ]
  [[ "$output" == *"5.3.0"* ]]
  [[ "$output" == *"5.4.0"* ]]
  [[ "$output" == *"pipx upgrade memory-bank-skill"* ]]
  [[ "$output" != *"git pull"* ]]
}

@test "update-notify: a pipx user is shown the pipx command, never told to git pull" {
  local checker
  checker=$(fake_checker checker.sh 0 \
    '{"current": "1.0.0", "latest": "1.1.0", "update_available": true, "flavor": "pipx", "upgrade_command": "pipx upgrade memory-bank-skill", "checked_at": "x", "source": "pypi"}')

  run env MB_VERSION_CHECK_BIN="$checker" bash "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pipx upgrade memory-bank-skill"* ]]
  [[ "$output" != *"git pull"* ]]
}

@test "update-notify: a git-flavor update-available answer shows the resolver's own upgrade_command verbatim, not a guessed one" {
  local checker
  checker=$(fake_checker checker.sh 0 \
    '{"current": "5.3.0", "latest": "5.4.0", "update_available": true, "flavor": "git", "upgrade_command": "bash /opt/mb/scripts/mb-upgrade.sh --force", "checked_at": "x", "source": "github"}')

  run env MB_VERSION_CHECK_BIN="$checker" bash "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"bash /opt/mb/scripts/mb-upgrade.sh --force"* ]]
}

# ═══ tolerant parsing (the JSON contract must not be a whitespace coupling) ═══

@test "update-notify: compact JSON (no space after the update_available colon) still produces the notice" {
  local checker
  checker=$(fake_checker checker.sh 0 \
    '{"current":"5.3.0","latest":"5.4.0","update_available":true,"flavor":"pipx","upgrade_command":"pipx upgrade memory-bank-skill","checked_at":"x","source":"github"}')

  run --separate-stderr env MB_VERSION_CHECK_BIN="$checker" bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [[ "$output" == *"5.3.0"* ]]
  [[ "$output" == *"5.4.0"* ]]
  [[ "$output" == *"pipx upgrade memory-bank-skill"* ]]
}

@test "update-notify: extra whitespace around update_available's colon still produces the notice" {
  local checker
  checker=$(fake_checker checker.sh 0 \
    '{"current": "5.3.0", "latest": "5.4.0", "update_available"   :    true, "flavor": "pipx", "upgrade_command": "pipx upgrade memory-bank-skill", "checked_at": "x", "source": "github"}')

  run --separate-stderr env MB_VERSION_CHECK_BIN="$checker" bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [[ "$output" == *"5.3.0"* ]]
  [[ "$output" == *"5.4.0"* ]]
  [[ "$output" == *"pipx upgrade memory-bank-skill"* ]]
}

@test "update-notify: a tab between update_available's colon and value still produces the notice" {
  local tab checker
  tab="$(printf '\t')"
  checker=$(fake_checker checker.sh 0 \
    "{\"current\": \"5.3.0\", \"latest\": \"5.4.0\", \"update_available\":${tab}true, \"flavor\": \"pipx\", \"upgrade_command\": \"pipx upgrade memory-bank-skill\", \"checked_at\": \"x\", \"source\": \"github\"}")

  run --separate-stderr env MB_VERSION_CHECK_BIN="$checker" bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [[ "$output" == *"5.3.0"* ]]
  [[ "$output" == *"5.4.0"* ]]
  [[ "$output" == *"pipx upgrade memory-bank-skill"* ]]
}

@test "update-notify: a tab between a string field's colon and its value is still parsed (current/latest/upgrade_command)" {
  local tab checker
  tab="$(printf '\t')"
  checker=$(fake_checker checker.sh 0 \
    "{\"current\":${tab}\"5.3.0\", \"latest\":${tab}\"5.4.0\", \"update_available\": true, \"flavor\": \"pipx\", \"upgrade_command\":${tab}\"pipx upgrade memory-bank-skill\", \"checked_at\": \"x\", \"source\": \"github\"}")

  run --separate-stderr env MB_VERSION_CHECK_BIN="$checker" bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [[ "$output" == *"5.3.0"* ]]
  [[ "$output" == *"5.4.0"* ]]
  [[ "$output" == *"pipx upgrade memory-bank-skill"* ]]
}

@test "update-notify: update_available false stays silent regardless of spacing (compact, extra-whitespace, tab)" {
  local tab checker
  tab="$(printf '\t')"

  checker=$(fake_checker c1.sh 0 \
    '{"current":"5.4.0","latest":"5.4.0","update_available":false,"flavor":"pipx","upgrade_command":"pipx upgrade memory-bank-skill","checked_at":"x","source":"cache"}')
  run --separate-stderr env MB_VERSION_CHECK_BIN="$checker" bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]

  checker=$(fake_checker c2.sh 0 \
    '{"current": "5.4.0", "latest": "5.4.0", "update_available"   :    false, "flavor": "pipx", "upgrade_command": "pipx upgrade memory-bank-skill", "checked_at": "x", "source": "cache"}')
  run --separate-stderr env MB_VERSION_CHECK_BIN="$checker" bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]

  checker=$(fake_checker c3.sh 0 \
    "{\"current\": \"5.4.0\", \"latest\": \"5.4.0\", \"update_available\":${tab}false, \"flavor\": \"pipx\", \"upgrade_command\": \"pipx upgrade memory-bank-skill\", \"checked_at\": \"x\", \"source\": \"cache\"}")
  run --separate-stderr env MB_VERSION_CHECK_BIN="$checker" bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

# ═══ contract test: real resolver -> hook (the pair that must stay honest) ═══
#
# The hook now calls the resolver with --cache-only (design: a SessionStart
# hook never touches the network — see hooks/mb-update-notify.sh's own
# header). So these contracts pre-warm the cache with ONE direct,
# synchronous resolver call (exactly what the hook's own detached
# background refresh would eventually produce), THEN drive the hook —
# proving the cache-only read path renders a real notice from the real
# resolver's real cache format, not a hand-rolled fixture.

@test "update-notify: contract — a warm cache (real resolver's own format) drives the hook to a real notice via --cache-only" {
  local resolver="$REPO_ROOT/scripts/mb-version-check.sh"
  [ -f "$resolver" ] || skip "scripts/mb-version-check.sh not present"

  local skill_dir fetch_stub cache_file
  skill_dir="$TMPDIR/skill"
  mkdir -p "$skill_dir"
  printf '1.0.0\n' > "$skill_dir/VERSION"
  cache_file="$TMPDIR/cache/.mb-version-check.json"

  fetch_stub="$TMPDIR/fetch.sh"
  cat > "$fetch_stub" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in
    *github*) printf '%s\n' '{"tag_name": "v99.0.0"}'; exit 0 ;;
  esac
done
exit 1
EOF
  chmod +x "$fetch_stub"

  # Warm the cache exactly the way the hook's own background refresh would:
  # a direct, synchronous, normal-mode resolver call.
  MB_SKILL_DIR="$skill_dir" MB_VERSION_CHECK_FETCH_BIN="$fetch_stub" \
    MB_VERSION_CHECK_CACHE="$cache_file" bash "$resolver" >/dev/null

  run --separate-stderr env \
    MB_SKILL_DIR="$skill_dir" \
    MB_VERSION_CHECK_FETCH_BIN="$fetch_stub" \
    MB_VERSION_CHECK_CACHE="$cache_file" \
    MB_VERSION_CHECK_BIN="$resolver" \
    bash "$HOOK"

  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -le 3 ]
  [[ "$output" == *"1.0.0"* ]]
  [[ "$output" == *"99.0.0"* ]]
}

@test "update-notify: contract — the REAL resolver reporting up-to-date (warm cache) drives the hook to zero bytes" {
  local resolver="$REPO_ROOT/scripts/mb-version-check.sh"
  [ -f "$resolver" ] || skip "scripts/mb-version-check.sh not present"

  local skill_dir fetch_stub cache_file
  skill_dir="$TMPDIR/skill"
  mkdir -p "$skill_dir"
  printf '99.0.0\n' > "$skill_dir/VERSION"
  cache_file="$TMPDIR/cache/.mb-version-check.json"

  fetch_stub="$TMPDIR/fetch.sh"
  cat > "$fetch_stub" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in
    *github*) printf '%s\n' '{"tag_name": "v99.0.0"}'; exit 0 ;;
  esac
done
exit 1
EOF
  chmod +x "$fetch_stub"

  MB_SKILL_DIR="$skill_dir" MB_VERSION_CHECK_FETCH_BIN="$fetch_stub" \
    MB_VERSION_CHECK_CACHE="$cache_file" bash "$resolver" >/dev/null

  run --separate-stderr env \
    MB_SKILL_DIR="$skill_dir" \
    MB_VERSION_CHECK_FETCH_BIN="$fetch_stub" \
    MB_VERSION_CHECK_CACHE="$cache_file" \
    MB_VERSION_CHECK_BIN="$resolver" \
    bash "$HOOK"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "update-notify: contract — cold cache with a 5s-sleeping network stub does NOT block; the CAPTURE returns in a small fraction of that 5s" {
  local resolver="$REPO_ROOT/scripts/mb-version-check.sh"
  [ -f "$resolver" ] || skip "scripts/mb-version-check.sh not present"

  local skill_dir fetch_stub cache_file
  skill_dir="$TMPDIR/skill"
  mkdir -p "$skill_dir"
  printf '1.0.0\n' > "$skill_dir/VERSION"
  cache_file="$TMPDIR/cache/.mb-version-check.json"

  # A network stub that sleeps 5s before answering — if the hook's primary
  # path ever fell through to a real (non-cache-only) fetch, this test
  # would take >=5s. It must not: the hook's own resolver call is
  # --cache-only (never runs this stub at all on the foreground path); only
  # the DETACHED background refresh runs it, and this test never waits on
  # that.
  fetch_stub="$TMPDIR/slow-fetch.sh"
  cat > "$fetch_stub" <<'EOF'
#!/usr/bin/env bash
sleep 5
for a in "$@"; do
  case "$a" in
    *github*) printf '%s\n' '{"tag_name": "v99.0.0"}'; exit 0 ;;
  esac
done
exit 1
EOF
  chmod +x "$fetch_stub"

  local start end elapsed_ms out
  start=$(date +%s%N)
  out="$(MB_SKILL_DIR="$skill_dir" MB_VERSION_CHECK_FETCH_BIN="$fetch_stub" \
    MB_VERSION_CHECK_CACHE="$cache_file" MB_VERSION_CHECK_BIN="$resolver" \
    bash "$HOOK" 2>"$TMPDIR/stderr.log")"
  end=$(date +%s%N)
  elapsed_ms=$(( (end - start) / 1000000 ))

  [ -z "$out" ]
  [ ! -s "$TMPDIR/stderr.log" ]
  # 1000ms, not the tighter 200ms first targeted: measured on this dev
  # machine, EVERY `bash script.sh` invocation that forks a real python3
  # costs ~150-190ms just in interpreter startup (`time python3 -c pass`
  # alone measures ~145ms here), and the --cache-only path still forks
  # python once for the PY_AVAILABLE preflight (unconditional, existing
  # behaviour this cycle intentionally left alone — weakening it would
  # touch the pyenv-shim fail-open contract 35 other tests already lock
  # in). The bound that actually matters is proven here regardless: a
  # >=5s-sleeping network stub costs this capture at most a few hundred
  # ms, not >=5000ms — the hook provably never falls through to a real
  # fetch on its foreground path.
  [ "$elapsed_ms" -lt 1000 ]

  # Proof the detached background refresh actually ran (not merely that the
  # hook returned fast): poll for the cache file the slow stub eventually
  # populates, well within the stub's own 5s sleep plus resolver overhead.
  local waited=0
  while [ ! -s "$cache_file" ] && [ "$waited" -lt 10 ]; do
    sleep 1
    waited=$((waited + 1))
  done
  [ -s "$cache_file" ]
  [[ "$(cat "$cache_file")" == *"99.0.0"* ]]
}

# ═══ silence paths ═══

@test "update-notify: an up-to-date answer produces zero bytes of output — no 'you are current' line either" {
  local checker
  checker=$(fake_checker checker.sh 0 \
    '{"current": "5.4.0", "latest": "5.4.0", "update_available": false, "flavor": "pipx", "upgrade_command": "pipx upgrade memory-bank-skill", "checked_at": "x", "source": "cache"}')

  run --separate-stderr env MB_VERSION_CHECK_BIN="$checker" bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "update-notify: a broken checker (non-zero exit) cannot break a session — no output, exit 0" {
  local checker
  checker=$(fake_checker checker.sh 1 'not json')

  run --separate-stderr env MB_VERSION_CHECK_BIN="$checker" bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "update-notify: a checker that returns garbage (non-JSON) produces no output, exit 0" {
  local checker
  checker=$(fake_checker checker.sh 0 'this is not json at all')

  run --separate-stderr env MB_VERSION_CHECK_BIN="$checker" bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "update-notify: a missing/absent resolver binary produces no output, exit 0" {
  run --separate-stderr env MB_VERSION_CHECK_BIN="$TMPDIR/does-not-exist.sh" bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "update-notify: update_available true but a blank upgrade_command stays silent rather than print a broken notice" {
  local checker
  checker=$(fake_checker checker.sh 0 \
    '{"current": "5.3.0", "latest": "5.4.0", "update_available": true, "flavor": "unknown", "upgrade_command": "", "checked_at": "x", "source": "github"}')

  run --separate-stderr env MB_VERSION_CHECK_BIN="$checker" bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

# ═══ watchdog: a resolver that never answers must never hang a session ═══

@test "update-notify: a resolver that hangs forever is killed by the hook's own watchdog — fast, exit 0, zero output, zero stderr" {
  local hanger="$TMPDIR/hanger.sh"
  cat > "$hanger" <<'EOF'
#!/usr/bin/env bash
sleep 30
EOF
  chmod +x "$hanger"

  # Bounded by run_with_deadline (30s outer bound — generous, but finite):
  # a watchdog regression must fail this test in well under a minute, never
  # wedge the suite waiting on an orphan (this is the exact gap that let a
  # prior watchdog regression through un-caught).
  run_with_deadline 30 env MB_VERSION_CHECK_BIN="$hanger" MB_UPDATE_NOTIFY_TIMEOUT=1 bash "$HOOK"

  [ "$capture_timed_out" -eq 0 ]
  [ "$capture_status" -eq 0 ]
  [ -z "$capture_out" ]
  [ -z "$capture_err" ]
  [ "$capture_elapsed" -le 5 ]
}

@test "update-notify: a resolver that never stops writing is capped, killed fast, exit 0, zero output" {
  local firehose="$TMPDIR/firehose.sh"
  cat > "$firehose" <<'EOF'
#!/usr/bin/env bash
while true; do printf '%080d\n' 0; done
EOF
  chmod +x "$firehose"

  run_with_deadline 30 env MB_VERSION_CHECK_BIN="$firehose" MB_UPDATE_NOTIFY_TIMEOUT=1 MB_UPDATE_NOTIFY_MAX_BYTES=4096 bash "$HOOK"

  [ "$capture_timed_out" -eq 0 ]
  [ "$capture_status" -eq 0 ]
  [ -z "$capture_out" ]
  [ -z "$capture_err" ]
  [ "$capture_elapsed" -le 5 ]
}

@test "update-notify: an invalid (non-digit) MB_UPDATE_NOTIFY_MAX_BYTES never leaks head's stderr into a SessionStart, notice is still produced" {
  local checker
  checker=$(fake_checker checker.sh 0 \
    '{"current": "5.3.0", "latest": "5.4.0", "update_available": true, "flavor": "pipx", "upgrade_command": "pipx upgrade memory-bank-skill", "checked_at": "x", "source": "github"}')

  run --separate-stderr env MB_VERSION_CHECK_BIN="$checker" MB_UPDATE_NOTIFY_MAX_BYTES=abc bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [[ "$output" == *"5.3.0"* ]]
  [[ "$output" == *"5.4.0"* ]]
  [[ "$output" == *"pipx upgrade memory-bank-skill"* ]]
}

@test "update-notify: the watchdog leaves no orphaned resolver process behind after killing a hang" {
  local marker="$TMPDIR/orphan-marker"
  local hanger="$TMPDIR/hanger2.sh"
  cat > "$hanger" <<EOF
#!/usr/bin/env bash
echo \$\$ > "$marker"
sleep 30
EOF
  chmod +x "$hanger"

  run_with_deadline 30 env MB_VERSION_CHECK_BIN="$hanger" MB_UPDATE_NOTIFY_TIMEOUT=1 bash "$HOOK"
  [ "$capture_timed_out" -eq 0 ]
  [ "$capture_status" -eq 0 ]

  [ -f "$marker" ]
  local child_pid
  child_pid="$(cat "$marker")"
  sleep 1
  ! kill -0 "$child_pid" 2>/dev/null
}

# ═══ non-blocking invariant: the HOST reads stdout to EOF, not just watches
# the hook process exit — a watchdog timer that outlives the hook (holding
# its inherited stdout fd open) blocks every session even when the hook
# itself already exited printing nothing. Timing `bash "$HOOK"` proves
# nothing here; only timing `$(...)` (the capture reaching EOF) does. ═══

@test "update-notify: the silent up-to-date path's CAPTURE reaches EOF fast — a live watchdog timer must never hold the pipe open" {
  local checker
  checker=$(fake_checker checker.sh 0 \
    '{"current": "5.4.0", "latest": "5.4.0", "update_available": false, "flavor": "pipx", "upgrade_command": "pipx upgrade memory-bank-skill", "checked_at": "x", "source": "cache"}')

  # A generous MB_UPDATE_NOTIFY_TIMEOUT (5s): the resolver answers
  # instantly, so a correct hook returns in well under 1s regardless of the
  # timeout. If the watchdog's own timer subshell is left running as an
  # orphan (holding this process substitution's stdout fd open), the
  # capture below blocks for ~5s instead — that is the exact regression
  # this test exists to catch, and it must show up as a slow capture, not
  # merely a slow hook-process-exit (see run_with_deadline's own comment).
  local start end elapsed out
  start=$(date +%s.%N)
  out="$(MB_VERSION_CHECK_BIN="$checker" MB_UPDATE_NOTIFY_TIMEOUT=5 bash "$HOOK" 2>"$TMPDIR/stderr.log")"
  end=$(date +%s.%N)
  elapsed="$(awk -v s="$start" -v e="$end" 'BEGIN { printf "%.3f", (e - s) }')"

  [ -z "$out" ]
  [ ! -s "$TMPDIR/stderr.log" ]
  # Integer-seconds compare (portable, no bc/awk dependency for the assert
  # itself): a live orphan timer would make this take >=1s (it's a 5s
  # timer), a correct hook takes a small fraction of a second.
  local elapsed_int
  elapsed_int="${elapsed%.*}"
  [ "$elapsed_int" -lt 1 ]
}

@test "update-notify: the notice path's CAPTURE is fast and byte-identical — no watchdog-fd stall on the 'update available' branch either" {
  local checker
  checker=$(fake_checker checker.sh 0 \
    '{"current": "5.3.0", "latest": "5.4.0", "update_available": true, "flavor": "pipx", "upgrade_command": "pipx upgrade memory-bank-skill", "checked_at": "x", "source": "github"}')

  local start end elapsed out
  start=$(date +%s.%N)
  out="$(MB_VERSION_CHECK_BIN="$checker" MB_UPDATE_NOTIFY_TIMEOUT=5 bash "$HOOK" 2>"$TMPDIR/stderr.log")"
  end=$(date +%s.%N)
  elapsed="$(awk -v s="$start" -v e="$end" 'BEGIN { printf "%.3f", (e - s) }')"

  [[ "$out" == *"5.3.0"* ]]
  [[ "$out" == *"5.4.0"* ]]
  [[ "$out" == *"pipx upgrade memory-bank-skill"* ]]
  [ ! -s "$TMPDIR/stderr.log" ]
  local elapsed_int
  elapsed_int="${elapsed%.*}"
  [ "$elapsed_int" -lt 1 ]
}

@test "update-notify: no watchdog timer survives the hook's own exit on the silent path (ps proof, not just fast capture)" {
  # A large, distinctive duration so a `sleep <N>` match in a process
  # listing can only be this test's own watchdog timer, never an unrelated
  # process that happens to share a small/common sleep duration.
  local distinctive_timeout=8237
  local checker
  checker=$(fake_checker checker.sh 0 \
    '{"current": "5.4.0", "latest": "5.4.0", "update_available": false, "flavor": "pipx", "upgrade_command": "pipx upgrade memory-bank-skill", "checked_at": "x", "source": "cache"}')

  run --separate-stderr env MB_VERSION_CHECK_BIN="$checker" MB_UPDATE_NOTIFY_TIMEOUT="$distinctive_timeout" bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]

  ! ps -Ao args 2>/dev/null | grep -q "sleep $distinctive_timeout\$"
}

# ═══ NUL / control bytes must never leak to the parent shell's stderr ═══

@test "update-notify: a checker emitting a NUL byte produces zero stderr bytes, not bash's 'ignored null byte' warning" {
  local checker="$TMPDIR/nul-checker.sh"
  printf '#!/usr/bin/env bash\nprintf %%s "not\\0json"\n' > "$checker"
  chmod +x "$checker"

  run --separate-stderr env MB_VERSION_CHECK_BIN="$checker" bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(printf '%s' "$stderr" | wc -c | tr -d ' ')" -eq 0 ]
}

# ═══ hardening: multi-line / control-byte resolver output cannot fake or corrupt a notice ═══

@test "update-notify: a multi-line resolver answer (embedded newline in a JSON value) is rejected outright — zero output" {
  local checker
  checker=$(fake_checker checker.sh 0 \
    "$(printf '{"current": "5.3.0", "latest": "5.4.0\n[fake] second notice", "update_available": true, "flavor": "pipx", "upgrade_command": "pipx upgrade memory-bank-skill", "checked_at": "x", "source": "github"}')")

  run --separate-stderr env MB_VERSION_CHECK_BIN="$checker" bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "update-notify: an upgrade_command containing an escaped quote (\\\") is rejected outright — silence, never a truncated command" {
  local checker
  checker=$(fake_checker checker.sh 0 '{"current": "5.3.0", "latest": "5.4.0", "update_available": true, "flavor": "source", "upgrade_command": "cd \"/opt/my app\" && upgrade", "checked_at": "x", "source": "github"}')

  run --separate-stderr env MB_VERSION_CHECK_BIN="$checker" bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "update-notify: an ANSI/control-byte payload in a resolver field is stripped before it ever reaches the terminal" {
  local esc checker
  esc="$(printf '\033')"
  checker=$(fake_checker checker.sh 0 \
    "{\"current\": \"5.3.0\", \"latest\": \"5.4.0\", \"update_available\": true, \"flavor\": \"pipx\", \"upgrade_command\": \"pipx upgrade ${esc}[31mmemory-bank-skill${esc}[0m\", \"checked_at\": \"x\", \"source\": \"github\"}")

  run --separate-stderr env MB_VERSION_CHECK_BIN="$checker" bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [[ "$output" != *$'\033'* ]]
  [[ "$output" == *"pipx upgrade"*"memory-bank-skill"* ]]
}

@test "update-notify: MB_UPDATE_CHECK=off produces no output, exit 0, and NEVER invokes the resolver" {
  local checker
  checker=$(fake_checker checker.sh 0 \
    '{"current": "5.3.0", "latest": "5.4.0", "update_available": true, "flavor": "pipx", "upgrade_command": "pipx upgrade memory-bank-skill", "checked_at": "x", "source": "github"}')

  run --separate-stderr env MB_UPDATE_CHECK=off MB_VERSION_CHECK_BIN="$checker" bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
  [ "$(call_count)" -eq 0 ]

  # Give a wrongly-spawned detached background refresh a moment to have
  # shown up in the call log before re-asserting — this must stay zero,
  # not just "zero at the instant `run` returned".
  sleep 0.3
  [ "$(call_count)" -eq 0 ]
}

# ═══ detached background refresh: a stale/absent cache must not block THIS
# session, and must not spawn a duplicate refresh once the cache is warm ═══

@test "update-notify: a cache-miss answer spawns a detached background refresh (call counter proves it, not just cache contents)" {
  local checker
  checker=$(fake_checker checker.sh 0 \
    '{"current": "1.0.0", "latest": "", "update_available": false, "flavor": "pipx", "upgrade_command": "pipx upgrade memory-bank-skill", "checked_at": "x", "source": "cache-miss"}')

  run --separate-stderr env MB_VERSION_CHECK_BIN="$checker" bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]

  # First call is this run's own --cache-only lookup; the background
  # refresh is a SECOND, detached invocation of the same stub.
  local waited=0
  while [ "$(call_count)" -lt 2 ] && [ "$waited" -lt 10 ]; do
    sleep 0.2
    waited=$((waited + 1))
  done
  [ "$(call_count)" -ge 2 ]
  grep -q -- '--cache-only' "$TMPDIR/calls.log"
  # The background call must NOT carry --cache-only (it exists to refresh
  # the cache from the network, which --cache-only forbids by design).
  grep -qv -- '--cache-only' "$TMPDIR/calls.log"
}

@test "update-notify: a fresh cache-hit answer (source != cache-miss) never spawns a background refresh" {
  local checker
  checker=$(fake_checker checker.sh 0 \
    '{"current": "5.4.0", "latest": "5.4.0", "update_available": false, "flavor": "pipx", "upgrade_command": "pipx upgrade memory-bank-skill", "checked_at": "x", "source": "cache"}')

  run --separate-stderr env MB_VERSION_CHECK_BIN="$checker" bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]

  sleep 0.3
  [ "$(call_count)" -eq 1 ]
}

@test "update-notify: warm cache reporting an update renders the notice in well under 100ms" {
  local checker
  checker=$(fake_checker checker.sh 0 \
    '{"current": "5.3.0", "latest": "5.4.0", "update_available": true, "flavor": "pipx", "upgrade_command": "pipx upgrade memory-bank-skill", "checked_at": "x", "source": "cache"}')

  local start end elapsed_ms out
  start=$(date +%s%N)
  out="$(MB_VERSION_CHECK_BIN="$checker" bash "$HOOK" 2>"$TMPDIR/stderr.log")"
  end=$(date +%s%N)
  elapsed_ms=$(( (end - start) / 1000000 ))

  [[ "$out" == *"5.3.0"* ]]
  [[ "$out" == *"5.4.0"* ]]
  [ ! -s "$TMPDIR/stderr.log" ]
  [ "$elapsed_ms" -lt 100 ]
}

@test "update-notify: contract — a real 'unknown' flavor notice never leaks a \\u escape (real resolver, warm cache)" {
  local resolver="$REPO_ROOT/scripts/mb-version-check.sh"
  [ -f "$resolver" ] || skip "scripts/mb-version-check.sh not present"

  local skill_dir fetch_stub cache_file
  skill_dir="$TMPDIR/unrecognizable-install-dir"
  mkdir -p "$skill_dir"
  printf '1.0.0\n' > "$skill_dir/VERSION"
  cache_file="$TMPDIR/cache/.mb-version-check.json"

  fetch_stub="$TMPDIR/fetch.sh"
  cat > "$fetch_stub" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in
    *github*) printf '%s\n' '{"tag_name": "v99.0.0"}'; exit 0 ;;
  esac
done
exit 1
EOF
  chmod +x "$fetch_stub"

  MB_SKILL_DIR="$skill_dir" MB_VERSION_CHECK_FETCH_BIN="$fetch_stub" \
    MB_VERSION_CHECK_CACHE="$cache_file" bash "$resolver" >/dev/null

  run --separate-stderr env \
    MB_SKILL_DIR="$skill_dir" \
    MB_VERSION_CHECK_FETCH_BIN="$fetch_stub" \
    MB_VERSION_CHECK_CACHE="$cache_file" \
    MB_VERSION_CHECK_BIN="$resolver" \
    bash "$HOOK"

  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [[ "$output" == *"1.0.0"* ]]
  case "$output" in
    *'\u'*) false ;;
    *) true ;;
  esac
  [[ "$output" == *"—"* ]]
}

# ═══ opt-in auto-update (Stage 4) — safety matrix ═══
#
# MB_AUTO_UPDATE is opt-in (default off): even when an update IS available,
# this hook stays notice-only unless the user explicitly turns this on, and
# even then only ever touches a git-clone install with a clean tree — never
# a package manager, never a dirty tree. scripts/mb-upgrade.sh is stubbed
# via MB_UPGRADE_BIN (the same override-seam pattern as MB_VERSION_CHECK_BIN)
# so no test here ever touches the real git remote.

@test "auto-update: row 1 — MB_AUTO_UPDATE unset/default never upgrades, notice-only, upgrade script never invoked" {
  local checker upgrade root
  root="$(make_clean_git_root gitroot)"
  checker=$(fake_checker checker.sh 0 \
    "{\"current\": \"5.3.0\", \"latest\": \"5.4.0\", \"update_available\": true, \"flavor\": \"git\", \"upgrade_command\": \"bash $root/scripts/mb-upgrade.sh --force\", \"checked_at\": \"x\", \"source\": \"github\"}")
  upgrade=$(fake_upgrade upgrade.sh 0)

  run --separate-stderr env MB_VERSION_CHECK_BIN="$checker" MB_SKILL_ROOT="$root" MB_UPGRADE_BIN="$upgrade" bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [[ "$output" == *"5.3.0"* ]]
  [[ "$output" == *"5.4.0"* ]]
  [[ "$output" != *"auto-updated"* ]]
  [ "$(upgrade_call_count)" -eq 0 ]
}

@test "auto-update: row 1b — MB_AUTO_UPDATE=off explicitly never upgrades either" {
  local checker upgrade root
  root="$(make_clean_git_root gitroot)"
  checker=$(fake_checker checker.sh 0 \
    "{\"current\": \"5.3.0\", \"latest\": \"5.4.0\", \"update_available\": true, \"flavor\": \"git\", \"upgrade_command\": \"bash $root/scripts/mb-upgrade.sh --force\", \"checked_at\": \"x\", \"source\": \"github\"}")
  upgrade=$(fake_upgrade upgrade.sh 0)

  run --separate-stderr env MB_AUTO_UPDATE=off MB_VERSION_CHECK_BIN="$checker" MB_SKILL_ROOT="$root" MB_UPGRADE_BIN="$upgrade" bash "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" != *"auto-updated"* ]]
  [ "$(upgrade_call_count)" -eq 0 ]
}

@test "auto-update: row 2 — MB_AUTO_UPDATE=on + git flavor + clean tree + update available runs mb-upgrade.sh --force and records current -> latest" {
  local checker upgrade root
  root="$(make_clean_git_root gitroot)"
  checker=$(fake_checker checker.sh 0 \
    "{\"current\": \"5.3.0\", \"latest\": \"5.4.0\", \"update_available\": true, \"flavor\": \"git\", \"upgrade_command\": \"bash $root/scripts/mb-upgrade.sh --force\", \"checked_at\": \"x\", \"source\": \"github\"}")
  # The stub genuinely advances the checkout's own VERSION file, exactly
  # like a real `mb-upgrade.sh --force` git-pull would — the hook's claim
  # is gated on that (M1), not on exit code alone.
  upgrade=$(fake_upgrade upgrade.sh 0 "$root/VERSION" "5.4.0")

  run --separate-stderr env MB_AUTO_UPDATE=on MB_VERSION_CHECK_BIN="$checker" MB_SKILL_ROOT="$root" MB_UPGRADE_BIN="$upgrade" bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [[ "$output" == *"auto-updated: 5.3.0 -> 5.4.0"* ]]
  [ "$(upgrade_call_count)" -eq 1 ]
  grep -q -- '--force' "$TMPDIR/upgrade-calls.log"
}

@test "auto-update: row 2b — the upgrade exits 0 but VERSION did not actually change: no false 'auto-updated' claim (M1)" {
  local checker upgrade root
  root="$(make_clean_git_root gitroot)"
  checker=$(fake_checker checker.sh 0 \
    "{\"current\": \"5.3.0\", \"latest\": \"5.4.0\", \"update_available\": true, \"flavor\": \"git\", \"upgrade_command\": \"bash $root/scripts/mb-upgrade.sh --force\", \"checked_at\": \"x\", \"source\": \"github\"}")
  # scripts/mb-upgrade.sh:218 exits 0 with "[✓] Up to date" when behind==0 —
  # i.e. it applied NOTHING and still succeeds (a race with a concurrent
  # update, a stale resolver cache, a branch/tag mismatch). This stub
  # reproduces exactly that: exit 0, VERSION untouched.
  upgrade=$(fake_upgrade upgrade.sh 0)

  run --separate-stderr env MB_AUTO_UPDATE=on MB_VERSION_CHECK_BIN="$checker" MB_SKILL_ROOT="$root" MB_UPGRADE_BIN="$upgrade" bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [[ "$output" == *"5.3.0"* ]]
  [[ "$output" != *"auto-updated"* ]]
  [ "$(upgrade_call_count)" -eq 1 ]
}

@test "auto-update: row 2d — the upgrade exits 0 and VERSION genuinely changed but NOT to the resolver's own latest: no false claim (minor#1)" {
  local checker upgrade root
  root="$(make_clean_git_root gitroot)"
  checker=$(fake_checker checker.sh 0 \
    "{\"current\": \"5.3.0\", \"latest\": \"5.4.0\", \"update_available\": true, \"flavor\": \"git\", \"upgrade_command\": \"bash $root/scripts/mb-upgrade.sh --force\", \"checked_at\": \"x\", \"source\": \"github\"}")
  # VERSION genuinely changed (rc==0, before != after) but to something
  # OTHER than the resolver's own "latest" (5.4.0) — e.g. a concurrent,
  # unrelated local VERSION write racing the upgrade window. Must NOT be
  # claimed as a successful auto-update to 5.4.0: string-equality against
  # $latest is required, not merely "changed from before".
  upgrade=$(fake_upgrade upgrade.sh 0 "$root/VERSION" "9.9.9")

  run --separate-stderr env MB_AUTO_UPDATE=on MB_VERSION_CHECK_BIN="$checker" MB_SKILL_ROOT="$root" MB_UPGRADE_BIN="$upgrade" bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [[ "$output" == *"5.3.0"* ]]
  [[ "$output" != *"auto-updated"* ]]
  [ "$(upgrade_call_count)" -eq 1 ]
}

@test "auto-update: row 2e — a missing VERSION baseline before the upgrade is inconclusive, never claimed, even if VERSION == latest after (minor#1)" {
  local checker upgrade root
  root="$TMPDIR/gitroot-no-baseline"
  mkdir -p "$root/scripts"
  # Deliberately NO VERSION file at all (no baseline to compare against) —
  # SKILL.md alone satisfies both the resolver's MB_SKILL_ROOT candidate
  # gate and the hook's own strong bundle-identity gate (M3).
  printf '# Memory Bank Skill (test fixture)\n' > "$root/SKILL.md"
  printf '#!/usr/bin/env bash\ntrue\n' > "$root/scripts/mb-upgrade.sh"
  chmod +x "$root/scripts/mb-upgrade.sh"
  printf '#!/usr/bin/env bash\ntrue\n' > "$root/scripts/_lib.sh"
  (
    cd "$root" && git init -q && git config user.email "test@test" \
      && git config user.name "Test" \
      && git add SKILL.md scripts/mb-upgrade.sh scripts/_lib.sh \
      && git commit -q -m init
  ) >/dev/null 2>&1
  [ -d "$root/.git" ]
  git -C "$root" status >/dev/null 2>&1

  checker=$(fake_checker checker.sh 0 \
    "{\"current\": \"unknown\", \"latest\": \"5.4.0\", \"update_available\": true, \"flavor\": \"git\", \"upgrade_command\": \"bash $root/scripts/mb-upgrade.sh --force\", \"checked_at\": \"x\", \"source\": \"github\"}")
  # The stub writes VERSION == latest for the FIRST time — rc==0, after is
  # non-empty and equals $latest, but BEFORE was never readable (the file
  # didn't exist). A missing baseline must be treated as inconclusive, not
  # as proof of a genuine transition.
  upgrade=$(fake_upgrade upgrade.sh 0 "$root/VERSION" "5.4.0")

  run --separate-stderr env MB_AUTO_UPDATE=on MB_VERSION_CHECK_BIN="$checker" MB_SKILL_ROOT="$root" MB_UPGRADE_BIN="$upgrade" bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [[ "$output" != *"auto-updated"* ]]
  [ "$(upgrade_call_count)" -eq 1 ]
}

@test "auto-update: git flavor + clean tree but root missing scripts/_lib.sh (weak bundle identity) refuses to upgrade — M3 residual" {
  local checker upgrade root
  root="$TMPDIR/gitroot-weak"
  mkdir -p "$root/scripts"
  printf '5.3.0\n' > "$root/VERSION"
  printf '# Memory Bank Skill (test fixture)\n' > "$root/SKILL.md"
  printf '#!/usr/bin/env bash\ntrue\n' > "$root/scripts/mb-upgrade.sh"
  chmod +x "$root/scripts/mb-upgrade.sh"
  # Deliberately NO scripts/_lib.sh — a clean git repo with a VERSION,
  # SKILL.md and mb-upgrade.sh alone is not (per the residual M3 finding)
  # strong enough evidence of a genuine skill bundle to justify running a
  # destructive --force upgrade against it: an arbitrary git repo that
  # happens to carry a stray VERSION/SKILL.md and a script NAMED
  # mb-upgrade.sh would otherwise still pass.
  (
    cd "$root" && git init -q && git config user.email "test@test" \
      && git config user.name "Test" \
      && git add VERSION SKILL.md scripts/mb-upgrade.sh \
      && git commit -q -m init
  ) >/dev/null 2>&1
  [ -d "$root/.git" ]
  git -C "$root" status >/dev/null 2>&1

  checker=$(fake_checker checker.sh 0 \
    "{\"current\": \"5.3.0\", \"latest\": \"5.4.0\", \"update_available\": true, \"flavor\": \"git\", \"upgrade_command\": \"bash $root/scripts/mb-upgrade.sh --force\", \"checked_at\": \"x\", \"source\": \"github\"}")
  upgrade=$(fake_upgrade upgrade.sh 0 "$root/VERSION" "5.4.0")

  run --separate-stderr env MB_AUTO_UPDATE=on MB_VERSION_CHECK_BIN="$checker" MB_SKILL_ROOT="$root" MB_UPGRADE_BIN="$upgrade" bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [[ "$output" == *"5.3.0"* ]]
  [[ "$output" != *"auto-updated"* ]]
  [ "$(upgrade_call_count)" -eq 0 ]
}

@test "auto-update: row 3 — MB_AUTO_UPDATE=on + git flavor + DIRTY tree refuses to upgrade, notice-only, upgrade script never invoked" {
  local checker upgrade root
  root="$(make_dirty_git_root gitroot)"
  checker=$(fake_checker checker.sh 0 \
    "{\"current\": \"5.3.0\", \"latest\": \"5.4.0\", \"update_available\": true, \"flavor\": \"git\", \"upgrade_command\": \"bash $root/scripts/mb-upgrade.sh --force\", \"checked_at\": \"x\", \"source\": \"github\"}")
  upgrade=$(fake_upgrade upgrade.sh 0)

  run --separate-stderr env MB_AUTO_UPDATE=on MB_VERSION_CHECK_BIN="$checker" MB_SKILL_ROOT="$root" MB_UPGRADE_BIN="$upgrade" bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [[ "$output" == *"5.3.0"* ]]
  [[ "$output" != *"auto-updated"* ]]
  [ "$(upgrade_call_count)" -eq 0 ]
}

@test "auto-update: row 3b — a config-widened clean check (status.showUntrackedFiles=no) with an untracked file still refuses (M2)" {
  local checker upgrade root
  root="$(make_clean_git_root gitroot)"
  # A repo configured this way hides untracked files from a plain
  # `git status --short` — the defense-in-depth clean-tree gate must not be
  # foolable by user/repo config; it has to see the untracked file anyway.
  git -C "$root" config status.showUntrackedFiles no
  printf 'stray\n' > "$root/untracked.txt"
  checker=$(fake_checker checker.sh 0 \
    "{\"current\": \"5.3.0\", \"latest\": \"5.4.0\", \"update_available\": true, \"flavor\": \"git\", \"upgrade_command\": \"bash $root/scripts/mb-upgrade.sh --force\", \"checked_at\": \"x\", \"source\": \"github\"}")
  upgrade=$(fake_upgrade upgrade.sh 0)

  run --separate-stderr env MB_AUTO_UPDATE=on MB_VERSION_CHECK_BIN="$checker" MB_SKILL_ROOT="$root" MB_UPGRADE_BIN="$upgrade" bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [[ "$output" == *"5.3.0"* ]]
  [[ "$output" != *"auto-updated"* ]]
  [ "$(upgrade_call_count)" -eq 0 ]
}

@test "auto-update: row 4 — MB_AUTO_UPDATE=on + pipx/pip/brew flavor NEVER invokes a package manager, notice-only" {
  local flavor checker upgrade root
  for flavor in pipx pip brew; do
    root="$(make_clean_git_root "gitroot-$flavor")"
    checker=$(fake_checker "checker-$flavor.sh" 0 \
      "{\"current\": \"5.3.0\", \"latest\": \"5.4.0\", \"update_available\": true, \"flavor\": \"$flavor\", \"upgrade_command\": \"$flavor upgrade memory-bank-skill\", \"checked_at\": \"x\", \"source\": \"github\"}")
    upgrade=$(fake_upgrade "upgrade-$flavor.sh" 0)

    run --separate-stderr env MB_AUTO_UPDATE=on MB_VERSION_CHECK_BIN="$checker" MB_SKILL_ROOT="$root" MB_UPGRADE_BIN="$upgrade" bash "$HOOK"
    [ "$status" -eq 0 ]
    [ -z "$stderr" ]
    [[ "$output" == *"$flavor upgrade memory-bank-skill"* ]]
    [[ "$output" != *"auto-updated"* ]]
    [ "$(upgrade_call_count)" -eq 0 ]
  done
}

@test "auto-update: row 4b — MB_AUTO_UPDATE=on + 'unknown' flavor NEVER invokes an upgrade either, notice-only (m1)" {
  local checker upgrade root
  root="$(make_clean_git_root gitroot-unknown)"
  checker=$(fake_checker checker.sh 0 \
    "{\"current\": \"5.3.0\", \"latest\": \"5.4.0\", \"update_available\": true, \"flavor\": \"unknown\", \"upgrade_command\": \"see release notes\", \"checked_at\": \"x\", \"source\": \"github\"}")
  upgrade=$(fake_upgrade upgrade.sh 0)

  run --separate-stderr env MB_AUTO_UPDATE=on MB_VERSION_CHECK_BIN="$checker" MB_SKILL_ROOT="$root" MB_UPGRADE_BIN="$upgrade" bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [[ "$output" == *"see release notes"* ]]
  [[ "$output" != *"auto-updated"* ]]
  [ "$(upgrade_call_count)" -eq 0 ]
}

@test "auto-update: row 5 — MB_AUTO_UPDATE=on + git flavor + clean tree but the upgrade command FAILS: session still starts, exit 0, no false 'auto-updated' claim" {
  local checker upgrade root
  root="$(make_clean_git_root gitroot)"
  checker=$(fake_checker checker.sh 0 \
    "{\"current\": \"5.3.0\", \"latest\": \"5.4.0\", \"update_available\": true, \"flavor\": \"git\", \"upgrade_command\": \"bash $root/scripts/mb-upgrade.sh --force\", \"checked_at\": \"x\", \"source\": \"github\"}")
  upgrade=$(fake_upgrade upgrade.sh 1)

  run --separate-stderr env MB_AUTO_UPDATE=on MB_VERSION_CHECK_BIN="$checker" MB_SKILL_ROOT="$root" MB_UPGRADE_BIN="$upgrade" bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [[ "$output" == *"5.3.0"* ]]
  [[ "$output" != *"auto-updated"* ]]
  [ "$(upgrade_call_count)" -eq 1 ]
}

@test "auto-update: row 2c — production default MB_UPGRADE_BIN path (no override) is exercised (m2)" {
  local checker root upgrade_stub
  root="$(make_clean_git_root gitroot-default)"
  mkdir -p "$root/scripts"
  upgrade_stub="$root/scripts/mb-upgrade.sh"
  cat > "$upgrade_stub" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TMPDIR/upgrade-calls.log"
printf '5.4.0\n' > "$root/VERSION"
exit 0
EOF
  chmod +x "$upgrade_stub"
  # Commit the stub so the clean-tree gate still passes — this test proves
  # the PRODUCTION default resolution ($root/scripts/mb-upgrade.sh with NO
  # MB_UPGRADE_BIN override), which the row-2 positive test above never
  # exercises (it always overrides MB_UPGRADE_BIN).
  (cd "$root" && git add scripts/mb-upgrade.sh && git commit -q -m "add upgrade stub") >/dev/null 2>&1

  checker=$(fake_checker checker.sh 0 \
    "{\"current\": \"5.3.0\", \"latest\": \"5.4.0\", \"update_available\": true, \"flavor\": \"git\", \"upgrade_command\": \"bash $root/scripts/mb-upgrade.sh --force\", \"checked_at\": \"x\", \"source\": \"github\"}")

  run --separate-stderr env MB_AUTO_UPDATE=on MB_VERSION_CHECK_BIN="$checker" MB_SKILL_ROOT="$root" bash "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [[ "$output" == *"auto-updated: 5.3.0 -> 5.4.0"* ]]
  [ "$(upgrade_call_count)" -eq 1 ]
}

@test "auto-update: a hanging upgrade command is killed by its own watchdog — fail-open, exit 0, no false claim, fast" {
  local checker hanger root
  root="$(make_clean_git_root gitroot)"
  checker=$(fake_checker checker.sh 0 \
    "{\"current\": \"5.3.0\", \"latest\": \"5.4.0\", \"update_available\": true, \"flavor\": \"git\", \"upgrade_command\": \"bash $root/scripts/mb-upgrade.sh --force\", \"checked_at\": \"x\", \"source\": \"github\"}")
  hanger="$TMPDIR/hang-upgrade.sh"
  cat > "$hanger" <<'EOF'
#!/usr/bin/env bash
sleep 30
EOF
  chmod +x "$hanger"

  run_with_deadline 30 env MB_AUTO_UPDATE=on MB_VERSION_CHECK_BIN="$checker" MB_SKILL_ROOT="$root" \
    MB_UPGRADE_BIN="$hanger" MB_AUTO_UPDATE_TIMEOUT=1 bash "$HOOK"
  [ "$capture_timed_out" -eq 0 ]
  [ "$capture_status" -eq 0 ]
  [[ "$capture_out" == *"5.3.0"* ]]
  [[ "$capture_out" != *"auto-updated"* ]]
  [ -z "$capture_err" ]
  [ "$capture_elapsed" -le 5 ]
}

# ═══ registration ═══

@test "update-notify: registered under settings/hooks.json SessionStart" {
  python3 - "$REPO_ROOT/settings/hooks.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
cmds = []
for entry in data.get("SessionStart", []):
    for h in entry.get("hooks", []):
        cmds.append(h.get("command", ""))
assert any("mb-update-notify.sh" in c for c in cmds), cmds
PY
}

@test "update-notify: registered as Cursor's sessionStart binding (the only other host with a SessionStart transport)" {
  grep -q "mb-update-notify.sh" "$REPO_ROOT/adapters/cursor.sh"
  grep -q "sessionStart:mb-update-notify.sh" "$REPO_ROOT/adapters/cursor.sh"
}

@test "update-notify: no adapter SHELL SCRIPT fabricates a registration for a host with no SessionStart transport" {
  # adapter-parity T3: Pi's update-notify wiring now genuinely exists, but it
  # lives INSIDE adapters/pi_session_memory_extension.ts (the installed
  # accept-path artifact), never as a literal string in adapters/pi.sh
  # itself — pi.sh only copies the template, it never calls the hook
  # directly. This grep therefore still correctly reads "false" for pi.sh;
  # see test_cross_agent_runtime_parity.bats for the real Pi assertion.
  #
  # adapter-parity T6: codex.sh is EXCLUDED from this loop — its before-prompt
  # (userpromptsubmit) hook legitimately renders the notice via
  # hooks/mb-update-notify.sh (REQ-014, the honest Codex tier). That is a real
  # before-prompt use, NOT a fabricated SessionStart registration, so codex.sh
  # is expected to reference the hook. Its behavior is asserted in
  # test_codex_adapter.bats (TTL gate, off-switch, fail-open, danger-block).
  for adapter in windsurf.sh cline.sh kilo.sh opencode.sh pi.sh; do
    ! grep -q "mb-update-notify.sh" "$REPO_ROOT/adapters/$adapter"
  done
}

@test "update-notify: Windsurf/Cline/Kilo/OpenCode/Codex have no INSTALLED SessionStart transport for this notice — documented gap, not silent" {
  # Same platform-limit contract as test_cross_agent_runtime_parity.bats: a
  # host with no equivalent lifecycle event is explicitly SKIPPED with its
  # reason, never silently asserted as if it worked. The gap is already
  # recorded in docs/cross-agent-setup.md's hook matrix ("SessionStart
  # context injection" row reads "—" for every column but Cursor/Pi).
  #
  # Pi is EXCLUDED from this skip as of adapter-parity T3: its session_start
  # extension now calls hooks/mb-update-notify.sh itself and install.sh's
  # opt-in accept path (mb_install_host_extensions "pi") genuinely installs
  # it to ~/.pi/agent/extensions/ — see
  # test_cross_agent_runtime_parity.bats's Pi update-notify wiring test for
  # the real (non-skipped) assertion.
  skip "Windsurf/Cline/Kilo/OpenCode/Codex have no CC-compatible SessionStart transport to register this notice on"
}
