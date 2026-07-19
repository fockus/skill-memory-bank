#!/usr/bin/env bats
# scripts/mb-backlog-state.sh — metadata value hardening (S4 round-2 findings
# 1, 2, 5): the READY brief gate must actually reject file paths (REQ-007),
# single-line metadata must not smuggle newlines into backlog.md, and an atomic
# rewrite must not silently re-permission the file.
#
# Red-anchor: every test name starts with `backlog_meta: `.

bats_require_minimum_version 1.5.0

load lib/assert

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  BS="$REPO_ROOT/scripts/mb-backlog-state.sh"

  TMPROOT="$(mktemp -d)"
  BANK="$TMPROOT/.memory-bank"
  mkdir -p "$BANK"

  cat > "$BANK/backlog.md" <<'EOF'
# Backlog

## Ideas

### I-001 — alpha idea [MED, TRIAGED, 2026-04-01]

### I-002 — ready candidate [MED, TRIAGED, 2026-04-02]

**Brief:** the system must validate the token when the request arrives

### I-003 — running item [MED, IN-PROGRESS, 2026-04-03]

## Out of scope
EOF
  chmod 644 "$BANK/backlog.md"
}

teardown() {
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

# Assert `annotate` refuses $1 as a brief, changing nothing.
refuse_brief() {
  local brief="$1" before
  snapshot "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
  run --separate-stderr bash "$BS" annotate I-001 --brief "$brief" --mb "$BANK"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  assert_unchanged "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
}

# ═══════════════════════════════════════════════════════════════
# REQ-007 — brief must be free of file paths (finding 1)
# ═══════════════════════════════════════════════════════════════
#
# REQ-007 (event-driven): "When a backlog item moves to READY, the system shall
# require an agent brief that is behavioral and FREE OF FILE PATHS and line
# numbers." The pre-fix guard only matched `\S+/\S+\.\w+`, i.e. a path needed a
# slash AND an extension simultaneously — so the most ordinary spellings walked
# straight through.

@test "backlog_meta: brief with a bare filename (README.md) is refused" {
  refuse_brief "the agent must edit README.md"
  [[ "$stderr" == *"contains file path"* ]]
}

@test "backlog_meta: brief with an extensionless path (scripts/runner) is refused" {
  refuse_brief "the agent must edit scripts/runner"
  [[ "$stderr" == *"contains file path"* ]]
}

@test "backlog_meta: brief with a ./relative path is refused" {
  refuse_brief "the agent must edit ./x"
  [[ "$stderr" == *"contains file path"* ]]
}

@test "backlog_meta: brief with a ../parent path is refused" {
  refuse_brief "the agent must edit ../x"
  [[ "$stderr" == *"contains file path"* ]]
}

@test "backlog_meta: brief with an absolute path is refused" {
  refuse_brief "the agent must read /etc/passwd"
  [[ "$stderr" == *"contains file path"* ]]
}

@test "backlog_meta: brief with a Windows path is refused" {
  refuse_brief 'the agent must edit C:\Users\dev\notes.txt'
  [[ "$stderr" == *"contains file path"* ]]
}

@test "backlog_meta: brief with a ~/home path is refused" {
  refuse_brief "the agent must edit ~/.config/app.conf"
  [[ "$stderr" == *"contains file path"* ]]
}

@test "backlog_meta: the pre-existing slash+extension path stays refused" {
  refuse_brief "should update scripts/mb-x.sh handler"
  [[ "$stderr" == *"contains file path"* ]]
}

@test "backlog_meta: brief with a line number stays refused" {
  refuse_brief "must handle the retry at :42 when it fails"
  [[ "$stderr" == *"contains line number"* ]]
}

@test "backlog_meta: READY transition is refused when the brief hides a bare filename" {
  # The gate must hold at the TRANSITION too, not only at annotate — a brief
  # written before the tightening must not become a free pass.
  python3 - "$BANK/backlog.md" <<'PY'
import sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
t = t.replace(
    "**Brief:** the system must validate the token when the request arrives",
    "**Brief:** the system must rewrite README.md when the request arrives",
)
open(p, "w", encoding="utf-8").write(t)
PY
  run --separate-stderr bash "$BS" transition I-002 READY --mb "$BANK"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"contains file path"* ]]
}

# ── Legitimate behavioural briefs must keep working (no over-blocking) ────────

@test "backlog_meta: ordinary behavioural briefs are still accepted" {
  run bash "$BS" annotate I-001 --brief "the system must reject an expired token when the client retries" --mb "$BANK"
  [ "$status" -eq 0 ]
  run bash "$BS" annotate I-001 --brief "the parser should surface a clear error when input is malformed" --mb "$BANK"
  [ "$status" -eq 0 ]
  run bash "$BS" annotate I-001 --brief "если запрос повторяется, система должна вернуть кэшированный ответ" --mb "$BANK"
  [ "$status" -eq 0 ]
}

@test "backlog_meta: a brief ending in a sentence period is not mistaken for a filename" {
  run bash "$BS" annotate I-001 --brief "the queue must drain before shutdown. it should then report done" --mb "$BANK"
  [ "$status" -eq 0 ]
}

@test "backlog_meta: a full READY path stays reachable with a clean brief" {
  run bash "$BS" annotate I-002 --brief "the system must retry the upload when the network drops" --mb "$BANK"
  [ "$status" -eq 0 ]
  run bash "$BS" transition I-002 READY --mb "$BANK"
  [ "$status" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════════
# Newline injection into single-line metadata (finding 2)
# ═══════════════════════════════════════════════════════════════
#
# A brief/reason is written verbatim as `**Brief:** <value>`. With an embedded
# newline the tail of the value lands on its own line and can forge a `### I-NNN`
# header, inventing a backlog entry. The round-1 uniqueness gate then reports
# `duplicate_id` — it catches the SYMPTOM; this is the cause.

@test "backlog_meta: a brief containing a newline is refused, backlog byte-identical" {
  local before
  snapshot "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
  run --separate-stderr bash "$BS" annotate I-001 --brief 'the system must validate input
### I-001 — injected duplicate [MED, NEW, 2026-01-02]' --mb "$BANK"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"code=invalid_metadata"* ]]
  [[ "$stderr" == *"newline"* ]]
  assert_unchanged "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
  # no forged header, and the db stays readable
  [ "$(grep -c '^### I-001' "$BANK/backlog.md")" -eq 1 ]
  run bash "$BS" list --mb "$BANK"
  [ "$status" -eq 0 ]
}

@test "backlog_meta: a transition --reason containing a newline is refused" {
  local before
  snapshot "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
  run --separate-stderr bash "$BS" transition I-003 WONTFIX --reason 'superseded
### I-999 — forged entry [MED, NEW, 2026-01-02]' --mb "$BANK"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"code=invalid_metadata"* ]]
  assert_unchanged "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
  refute_grep -q 'I-999' "$BANK/backlog.md"
}

@test "backlog_meta: a carriage return in a brief is refused too" {
  local before
  snapshot "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
  run --separate-stderr bash "$BS" annotate I-001 --brief "$(printf 'the system must validate input\r### I-001 — forged [MED, NEW, 2026-01-02]')" --mb "$BANK"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"code=invalid_metadata"* ]]
  assert_unchanged "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
}

@test "backlog_meta: a --parent value containing a newline is refused" {
  local before
  snapshot "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
  run --separate-stderr bash "$BS" annotate I-001 --brief "the system must retry when the call fails" --parent 'I-003
### I-998 — forged [MED, NEW, 2026-01-02]' --mb "$BANK"
  [ "$status" -ne 0 ]
  assert_unchanged "$BANK/backlog.md" "$BATS_TEST_TMPDIR/before.snap"
  refute_grep -q 'I-998' "$BANK/backlog.md"
}

# ═══════════════════════════════════════════════════════════════
# Atomic rewrite must not re-permission the backlog (finding 5)
# ═══════════════════════════════════════════════════════════════

@test "backlog_meta: transition preserves the backlog file mode (not 0600)" {
  # mkstemp creates 0600 and os.replace carries that mode onto the target, so a
  # world-readable team bank silently became owner-only after one transition.
  chmod 644 "$BANK/backlog.md"
  run bash "$BS" transition I-001 NEEDS-INFO --mb "$BANK"
  [ "$status" -eq 0 ]
  perms=$(python3 -c 'import os,stat,sys;print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode)))' "$BANK/backlog.md")
  [ "$perms" = "0o644" ]
}

@test "backlog_meta: annotate preserves the backlog file mode" {
  chmod 664 "$BANK/backlog.md"
  run bash "$BS" annotate I-001 --brief "the system must retry when the call fails" --mb "$BANK"
  [ "$status" -eq 0 ]
  perms=$(python3 -c 'import os,stat,sys;print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode)))' "$BANK/backlog.md")
  [ "$perms" = "0o664" ]
}

@test "backlog_meta: a deliberately private backlog stays private" {
  # The inverse guard: preserving the mode must not WIDEN a locked-down file.
  chmod 600 "$BANK/backlog.md"
  run bash "$BS" transition I-001 NEEDS-INFO --mb "$BANK"
  [ "$status" -eq 0 ]
  perms=$(python3 -c 'import os,stat,sys;print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode)))' "$BANK/backlog.md")
  [ "$perms" = "0o600" ]
}
