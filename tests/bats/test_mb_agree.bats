#!/usr/bin/env bats
# Tests for scripts/mb-agree.sh — the "Running List of Agreements" CLI.
#
# Spec: .memory-bank/specs/agreements/{requirements,design,tasks}.md
# Covers REQ-001..016 and GIVEN/WHEN/THEN scenarios 1-9 from requirements.md
# (scenario 8 — verify agreement-compliance — is out of scope for this suite;
# it belongs to the plan-verifier integration, task 7).
#
# TDD RED phase: every test skips (not fails) when the script does not exist
# yet, so `bats tests/bats/test_mb_agree.bats` cleanly reports the red state.

bats_require_minimum_version 1.5.0

MARKER_START='<!-- mb-agreements:start -->'
MARKER_END='<!-- mb-agreements:end -->'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-agree.sh"

  [ -f "$SCRIPT" ] || skip "scripts/mb-agree.sh not implemented yet (TDD red phase)"

  TMPROOT="$(mktemp -d)"
  PROJECT_ROOT="$TMPROOT/project"
  BANK="$PROJECT_ROOT/.memory-bank"
  mkdir -p "$BANK"

  export MB_PATH="$BANK"
  export MB_AGREEMENTS_PROJECT_ROOT="$PROJECT_ROOT"
  # Fast lock timing for the tests that exercise it explicitly.
  export MB_AGREEMENTS_LOCK_TIMEOUT=2
  export MB_AGREEMENTS_LOCK_TTL=120
  unset MB_AGREEMENTS || true
}

teardown() {
  if [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ]; then
    rm -rf "$TMPROOT"
  fi
}

run_agree() {
  run bash "$SCRIPT" "$@"
}

extract_id() {
  printf '%s\n' "$1" | grep -Eo 'AGR-[0-9]{3}' | head -n1
}

extract_num() {
  extract_id "$1" | grep -Eo '[0-9]{3}'
}

sha() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

today() {
  date +%F
}

# ═══════════════════════════════════════════════════════════════
# Existence
# ═══════════════════════════════════════════════════════════════

@test "mb-agree.sh exists and is executable" {
  [ -f "$SCRIPT" ]
  [ -x "$SCRIPT" ]
}

# ═══════════════════════════════════════════════════════════════
# Task 1 — registry core: template, add, list, lazy init
# Scenario 1: first add lazily activates the feature
# ═══════════════════════════════════════════════════════════════

@test "scenario 1: first add lazily creates agreements.md with all 4 sections" {
  [ ! -f "$BANK/agreements.md" ]
  run_agree add "Memory Bank is the canonical project state store"
  [ "$status" -eq 0 ]

  [ -f "$BANK/agreements.md" ]
  grep -qE '^## Active$' "$BANK/agreements.md"
  grep -qE '^## Deferred$' "$BANK/agreements.md"
  grep -qE '^## Open Questions$' "$BANK/agreements.md"
  grep -qE '^## Archive$' "$BANK/agreements.md"

  local d; d="$(today)"
  grep -qE "^- AGR-001 \($d, user-confirmed\): Memory Bank is the canonical project state store\$" "$BANK/agreements.md"
}

@test "scenario 1: first add creates AGENTS.md (not CLAUDE.md) with only the managed block" {
  [ ! -f "$PROJECT_ROOT/CLAUDE.md" ]
  [ ! -f "$PROJECT_ROOT/AGENTS.md" ]
  run_agree add "Memory Bank is the canonical project state store"
  [ "$status" -eq 0 ]

  [ -f "$PROJECT_ROOT/AGENTS.md" ]
  [ ! -f "$PROJECT_ROOT/CLAUDE.md" ]
  grep -qF "$MARKER_START" "$PROJECT_ROOT/AGENTS.md"
  grep -qF "$MARKER_END" "$PROJECT_ROOT/AGENTS.md"
  grep -qF "AGR-001: Memory Bank is the canonical project state store" "$PROJECT_ROOT/AGENTS.md"
  grep -qF ".memory-bank/agreements.md" "$PROJECT_ROOT/AGENTS.md"
}

@test "add: second add issues AGR-002 (monotonic)" {
  run_agree add "First decision"
  [ "$status" -eq 0 ]
  run_agree add "Second decision"
  [ "$status" -eq 0 ]
  grep -qE '^- AGR-002 ' "$BANK/agreements.md"
}

@test "add: --adr NNN appends the ADR back-reference" {
  run_agree add "Big architectural call" --adr 12
  [ "$status" -eq 0 ]
  grep -qF '→ ADR-012' "$BANK/agreements.md"
}

@test "add: --source overrides the default user-confirmed source" {
  run_agree add "Interview decision" --source interview
  [ "$status" -eq 0 ]
  grep -qE '^- AGR-001 \([0-9-]+, interview\):' "$BANK/agreements.md"
}

@test "add: statement containing a newline exits 2 with usage, no write" {
  run bash "$SCRIPT" add "$(printf 'line one\nline two')"
  [ "$status" -eq 2 ]
  [ ! -f "$BANK/agreements.md" ]
}

@test "add: max ID counts Archive entries too (IDs never reused)" {
  run_agree add "Will be rejected"
  [ "$status" -eq 0 ]
  local id; id="$(extract_num "$output")"
  run_agree reject "$id"
  [ "$status" -eq 0 ]
  run_agree add "Fresh decision after a reject"
  [ "$status" -eq 0 ]
  # New id is AGR-002, never reusing the archived AGR-001; the rejected
  # entry stays in Archive (moved, not deleted) but is gone from Active.
  grep -qE '^- AGR-002 ' "$BANK/agreements.md"
  grep -qE '^- AGR-001 .*\[rejected\]$' "$BANK/agreements.md"
  run_agree list
  [[ "$output" != *"AGR-001"* ]]
}

@test "list: default prints only Active entries" {
  run_agree add "Active one"
  [ "$status" -eq 0 ]
  local id; id="$(extract_num "$output")"
  run_agree add "Will become deferred"
  [ "$status" -eq 0 ]
  local id2; id2="$(extract_num "$output")"
  run_agree defer "$id2"
  [ "$status" -eq 0 ]

  run_agree list
  [ "$status" -eq 0 ]
  [[ "$output" == *"Active one"* ]]
  [[ "$output" != *"Will become deferred"* ]]
}

@test "list --all: prints every section including Deferred/Archive" {
  run_agree add "Active one"
  [ "$status" -eq 0 ]
  local id; id="$(extract_num "$output")"
  run_agree add "Will become deferred"
  [ "$status" -eq 0 ]
  local id2; id2="$(extract_num "$output")"
  run_agree defer "$id2"
  [ "$status" -eq 0 ]

  run_agree list --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"Active one"* ]]
  [[ "$output" == *"Will become deferred"* ]]
}

@test "list: on a bank with no agreements.md yet prints a friendly message and exits 0" {
  run_agree list
  [ "$status" -eq 0 ]
  [ ! -f "$BANK/agreements.md" ]
}

# ═══════════════════════════════════════════════════════════════
# Task 2 — lifecycle mutations: supersede, defer, reject
# Scenario 2: supersede replaces atomically
# Scenario 3: supersede of a non-active target changes nothing
# ═══════════════════════════════════════════════════════════════

@test "scenario 2: add --supersedes N atomically archives the old entry and activates the new one" {
  run_agree add "Kanban is part of the MVP"
  [ "$status" -eq 0 ]
  local old; old="$(extract_num "$output")"

  run_agree add "Kanban is postponed until phase 2" --supersedes "$old"
  [ "$status" -eq 0 ]
  local new; new="$(extract_num "$output")"
  [ "$new" != "$old" ]

  # old entry archived with a back-link, new entry active with a forward-link.
  grep -qE "^- AGR-${old} .*\[superseded by AGR-${new}\]\$" "$BANK/agreements.md"
  grep -qE "^- AGR-${new} .*Kanban is postponed until phase 2.*\[supersedes AGR-${old}\]\$" "$BANK/agreements.md"

  # old id no longer has its own line in the Active section (it may still be
  # *mentioned* inside the new entry's lineage marker, which is expected).
  run_agree list
  [[ "$output" != *"- AGR-${old} "* ]]

  # managed block reflects the swap: new statement present, old id's own
  # one-liner entry gone (block lines are rendered as "- AGR-NNN: ...").
  [[ "$(cat "$PROJECT_ROOT/AGENTS.md")" == *"Kanban is postponed until phase 2"* ]]
  [[ "$(cat "$PROJECT_ROOT/AGENTS.md")" != *"- AGR-${old}: "* ]]
}

@test "scenario 3: supersede of an already-superseded target exits 1 and changes nothing" {
  run_agree add "Kanban is part of the MVP"
  [ "$status" -eq 0 ]
  local old; old="$(extract_num "$output")"
  run_agree add "Kanban is postponed" --supersedes "$old"
  [ "$status" -eq 0 ]

  local before_reg before_agents
  before_reg="$(sha "$BANK/agreements.md")"
  before_agents="$(sha "$PROJECT_ROOT/AGENTS.md")"

  run_agree add "Kanban is cancelled" --supersedes "$old"
  [ "$status" -ne 0 ]
  [[ "$output" == *"AGR-${old} is not active"* ]]

  [ "$(sha "$BANK/agreements.md")" = "$before_reg" ]
  [ "$(sha "$PROJECT_ROOT/AGENTS.md")" = "$before_agents" ]
}

@test "supersede of a non-existent AGR-NNN exits 1 with a clear error" {
  run_agree add "Some active decision"
  [ "$status" -eq 0 ]
  run_agree add "New" --supersedes 999
  [ "$status" -ne 0 ]
  [[ "$output" == *"AGR-999 is not active"* ]]
}

@test "defer N moves an active entry to the Deferred section" {
  run_agree add "Deferred candidate"
  [ "$status" -eq 0 ]
  local id; id="$(extract_num "$output")"

  run_agree defer "$id"
  [ "$status" -eq 0 ]

  local content; content="$(cat "$BANK/agreements.md")"
  local active_block deferred_block
  active_block="$(printf '%s\n' "$content" | awk '/^## Active$/{f=1;next} /^## /{f=0} f')"
  deferred_block="$(printf '%s\n' "$content" | awk '/^## Deferred$/{f=1;next} /^## /{f=0} f')"
  [[ "$active_block" != *"AGR-${id}"* ]]
  [[ "$deferred_block" == *"AGR-${id}"* ]]
}

@test "reject N moves an active entry to Archive with a rejected marker" {
  run_agree add "Reject candidate"
  [ "$status" -eq 0 ]
  local id; id="$(extract_num "$output")"

  run_agree reject "$id"
  [ "$status" -eq 0 ]

  grep -qE "^- AGR-${id} .*\[rejected\]\$" "$BANK/agreements.md"
  run_agree list
  [[ "$output" != *"AGR-${id}"* ]]
}

@test "defer of a non-active id exits 1, zero writes" {
  run_agree add "Once active"
  [ "$status" -eq 0 ]
  local id; id="$(extract_num "$output")"
  run_agree reject "$id"
  [ "$status" -eq 0 ]

  local before; before="$(sha "$BANK/agreements.md")"
  run_agree defer "$id"
  [ "$status" -ne 0 ]
  [[ "$output" == *"is not active"* ]]
  [ "$(sha "$BANK/agreements.md")" = "$before" ]
}

# ═══════════════════════════════════════════════════════════════
# Task 3 — Open Questions: question, resolve
# ═══════════════════════════════════════════════════════════════

@test "question appends to Open Questions with its own Q-NNN counter" {
  run_agree question "Should we support a YAML mirror?"
  [ "$status" -eq 0 ]
  grep -qE '^- Q-001: Should we support a YAML mirror\?$' "$BANK/agreements.md"

  run_agree question "Should conflicts get their own registry?"
  [ "$status" -eq 0 ]
  grep -qE '^- Q-002: ' "$BANK/agreements.md"
}

@test "resolve N closes the open question" {
  run_agree question "Temporary hypothesis"
  [ "$status" -eq 0 ]
  run_agree resolve 1
  [ "$status" -eq 0 ]
  ! grep -qE '^- Q-001: Temporary hypothesis$' "$BANK/agreements.md"
  grep -q 'Q-001' "$BANK/agreements.md"
}

@test "resolve of a missing question id exits 1" {
  run_agree question "Only question"
  [ "$status" -eq 0 ]
  run_agree resolve 99
  [ "$status" -ne 0 ]
}

@test "MAJOR (re-review): resolve does not free up its Q id for reuse (REQ-001 never-reused)" {
  run_agree question "First question"
  [ "$status" -eq 0 ]
  run_agree resolve 1
  [ "$status" -eq 0 ]
  # The resolved line must keep a BARE leading "- Q-001" token (only the
  # text is struck through) so next_id's line-anchored scan still counts
  # it — striking the whole line (including the id) made the id invisible
  # to the counter and the next `question` silently reissued it.
  grep -qE '^- Q-001: ' "$BANK/agreements.md"

  run_agree question "Second question"
  [ "$status" -eq 0 ]
  grep -qE '^- Q-002: Second question$' "$BANK/agreements.md"
  ! grep -qE '^- Q-001: Second question' "$BANK/agreements.md"
}

@test "question/resolve never touch the managed block (CLAUDE.md/AGENTS.md untouched)" {
  run_agree add "Seed the managed block"
  [ "$status" -eq 0 ]
  local before; before="$(sha "$PROJECT_ROOT/AGENTS.md")"

  run_agree question "Hypothesis, not a decision"
  [ "$status" -eq 0 ]
  [ "$(sha "$PROJECT_ROOT/AGENTS.md")" = "$before" ]

  run_agree resolve 1
  [ "$status" -eq 0 ]
  [ "$(sha "$PROJECT_ROOT/AGENTS.md")" = "$before" ]
}

# ═══════════════════════════════════════════════════════════════
# Task 4 — managed-block sync engine
# Scenario 5: sync is idempotent and preserves foreign content
# Scenario 6: oversized active list warns but never truncates
# Scenario 9: damaged managed block fails loudly
# ═══════════════════════════════════════════════════════════════

@test "scenario 5: sync is idempotent and byte-preserves foreign content around the block" {
  run_agree add "Tracked decision"
  [ "$status" -eq 0 ]

  cat > "$PROJECT_ROOT/CLAUDE.md" <<EOF
# Project notes

Some user-owned content above.

$MARKER_START
stale placeholder
$MARKER_END

Some user-owned content below.
EOF

  run_agree sync
  [ "$status" -eq 0 ]
  local first; first="$(cat "$PROJECT_ROOT/CLAUDE.md")"
  [[ "$first" == *"Some user-owned content above."* ]]
  [[ "$first" == *"Some user-owned content below."* ]]
  [[ "$first" == *"Tracked decision"* ]]
  [[ "$first" != *"stale placeholder"* ]]

  local sha1; sha1="$(sha "$PROJECT_ROOT/CLAUDE.md")"
  run_agree sync
  [ "$status" -eq 0 ]
  local sha2; sha2="$(sha "$PROJECT_ROOT/CLAUDE.md")"
  [ "$sha1" = "$sha2" ]
}

@test "sync: neither marker present appends a fresh block at EOF, foreign content untouched" {
  run_agree add "Tracked decision"
  [ "$status" -eq 0 ]
  printf 'Line one.\nLine two.\n' > "$PROJECT_ROOT/CLAUDE.md"

  run_agree sync
  [ "$status" -eq 0 ]
  local content; content="$(cat "$PROJECT_ROOT/CLAUDE.md")"
  [[ "$content" == *"Line one."* ]]
  [[ "$content" == *"Line two."* ]]
  [[ "$content" == *"$MARKER_START"* ]]
  [[ "$content" == *"Tracked decision"* ]]
}

@test "scenario 9: start marker without end marker fails loudly, no write" {
  run_agree add "Tracked decision"
  [ "$status" -eq 0 ]
  printf 'above\n%s\nbroken\n' "$MARKER_START" > "$PROJECT_ROOT/CLAUDE.md"
  local before; before="$(sha "$PROJECT_ROOT/CLAUDE.md")"

  run_agree sync
  [ "$status" -ne 0 ]
  [[ "$output" == *"CLAUDE.md"* ]]
  [[ "$output" == *"mb-agreements"* ]]
  [ "$(sha "$PROJECT_ROOT/CLAUDE.md")" = "$before" ]
}

@test "end marker without start marker fails loudly, no write" {
  run_agree add "Tracked decision"
  [ "$status" -eq 0 ]
  printf 'above\n%s\nbroken\n' "$MARKER_END" > "$PROJECT_ROOT/CLAUDE.md"
  local before; before="$(sha "$PROJECT_ROOT/CLAUDE.md")"

  run_agree sync
  [ "$status" -ne 0 ]
  [[ "$output" == *"CLAUDE.md"* ]]
  [ "$(sha "$PROJECT_ROOT/CLAUDE.md")" = "$before" ]
}

@test "MINOR (re-review): duplicate start markers in a sync target are damaged, zero writes" {
  run_agree add "Seed decision"
  [ "$status" -eq 0 ]
  local reg_before; reg_before="$(sha "$BANK/agreements.md")"
  printf '%s\nstuff\n%s\nmore\n%s\n' "$MARKER_START" "$MARKER_START" "$MARKER_END" >"$PROJECT_ROOT/CLAUDE.md"
  local claude_before; claude_before="$(sha "$PROJECT_ROOT/CLAUDE.md")"

  run_agree add "Should never land"
  [ "$status" -ne 0 ]
  [ "$(sha "$BANK/agreements.md")" = "$reg_before" ]
  [ "$(sha "$PROJECT_ROOT/CLAUDE.md")" = "$claude_before" ]
}

@test "MINOR (re-review): duplicate end markers in a sync target are damaged, zero writes" {
  run_agree add "Seed decision"
  [ "$status" -eq 0 ]
  local reg_before; reg_before="$(sha "$BANK/agreements.md")"
  printf '%s\nstuff\n%s\nmore\n%s\n' "$MARKER_START" "$MARKER_END" "$MARKER_END" >"$PROJECT_ROOT/CLAUDE.md"
  local claude_before; claude_before="$(sha "$PROJECT_ROOT/CLAUDE.md")"

  run_agree add "Should never land"
  [ "$status" -ne 0 ]
  [ "$(sha "$BANK/agreements.md")" = "$reg_before" ]
  [ "$(sha "$PROJECT_ROOT/CLAUDE.md")" = "$claude_before" ]
}

@test "scenario 6: more than 25 active agreements warns on stderr but renders all of them" {
  local i
  for i in $(seq 1 26); do
    run_agree add "Active agreement number $i"
    [ "$status" -eq 0 ]
  done
  [[ "$output" == *"prune"* ]] || [[ "$output" == *"26"* ]]

  local count
  count="$(grep -cE '^- AGR-[0-9]{3}: ' "$PROJECT_ROOT/AGENTS.md")"
  [ "$count" -eq 26 ]
}

@test "sync rebuilds the managed block after a manual registry edit (REQ-012)" {
  run_agree add "Original decision"
  [ "$status" -eq 0 ]
  # Simulate a manual (out-of-band) edit: insert a new line directly into the
  # ## Active section, bypassing the CLI.
  awk -v extra="- AGR-002 ($(today), user-confirmed): Hand-added decision" '
    BEGIN{done=0}
    /^## Active$/{print; getline; print; print extra; done=1; next}
    {print}
  ' "$BANK/agreements.md" > "$BANK/agreements.md.tmp"
  mv "$BANK/agreements.md.tmp" "$BANK/agreements.md"

  run_agree sync
  [ "$status" -eq 0 ]
  grep -qF "Hand-added decision" "$PROJECT_ROOT/AGENTS.md"
}

@test "sync coexists with an adapters' memory-bank:start/end block in the same file" {
  run_agree add "Tracked decision"
  [ "$status" -eq 0 ]
  cat > "$PROJECT_ROOT/CLAUDE.md" <<EOF
<!-- memory-bank:start -->
adapter-owned content
<!-- memory-bank:end -->
EOF
  run_agree sync
  [ "$status" -eq 0 ]
  local content; content="$(cat "$PROJECT_ROOT/CLAUDE.md")"
  [[ "$content" == *"<!-- memory-bank:start -->"* ]]
  [[ "$content" == *"adapter-owned content"* ]]
  [[ "$content" == *"<!-- memory-bank:end -->"* ]]
  [[ "$content" == *"$MARKER_START"* ]]
  [[ "$content" == *"Tracked decision"* ]]

  run_agree sync
  [ "$status" -eq 0 ]
  local content2; content2="$(cat "$PROJECT_ROOT/CLAUDE.md")"
  [ "$content" = "$content2" ]
}

@test "REQ-006: when both CLAUDE.md and AGENTS.md exist, sync writes to both" {
  printf '# claude notes\n' > "$PROJECT_ROOT/CLAUDE.md"
  printf '# agents notes\n' > "$PROJECT_ROOT/AGENTS.md"
  run_agree add "Dual-file decision"
  [ "$status" -eq 0 ]
  grep -qF "Dual-file decision" "$PROJECT_ROOT/CLAUDE.md"
  grep -qF "Dual-file decision" "$PROJECT_ROOT/AGENTS.md"
}

# ═══════════════════════════════════════════════════════════════
# Task 5 — lock and kill-switch
# Scenario 4: kill-switch makes every subcommand a no-op
# Scenario 7: parallel adds get unique IDs
# ═══════════════════════════════════════════════════════════════

@test "scenario 4: MB_AGREEMENTS=off (env) makes add a no-op, zero writes" {
  export MB_AGREEMENTS=off
  run_agree add "Should never be written"
  [ "$status" -eq 0 ]
  [[ "$output" == *"disabled"* ]] || [[ "$output" == *"MB_AGREEMENTS"* ]]
  [ ! -f "$BANK/agreements.md" ]
  [ ! -f "$PROJECT_ROOT/CLAUDE.md" ]
  [ ! -f "$PROJECT_ROOT/AGENTS.md" ]
}

@test "scenario 4: MB_AGREEMENTS=off via .mb-config makes add a no-op, zero writes" {
  printf 'MB_AGREEMENTS=off\n' > "$BANK/.mb-config"
  run_agree add "Should never be written"
  [ "$status" -eq 0 ]
  [ ! -f "$BANK/agreements.md" ]
  [ ! -f "$PROJECT_ROOT/CLAUDE.md" ]
  [ ! -f "$PROJECT_ROOT/AGENTS.md" ]
}

@test "kill-switch also short-circuits list as an explained no-op" {
  export MB_AGREEMENTS=off
  run_agree list
  [ "$status" -eq 0 ]
  [[ "$output" == *"disabled"* ]] || [[ "$output" == *"MB_AGREEMENTS"* ]]
}

@test "kill-switch leaves an already-populated registry untouched" {
  run_agree add "Pre-existing decision"
  [ "$status" -eq 0 ]
  local before; before="$(sha "$BANK/agreements.md")"

  export MB_AGREEMENTS=off
  run_agree add "Attempted after disabling"
  [ "$status" -eq 0 ]
  [ "$(sha "$BANK/agreements.md")" = "$before" ]
}

@test "scenario 7: two parallel adds land distinct, consecutive IDs" {
  bash "$SCRIPT" add "Concurrent A" >"$TMPROOT/out_a.txt" 2>&1 &
  local pid_a=$!
  bash "$SCRIPT" add "Concurrent B" >"$TMPROOT/out_b.txt" 2>&1 &
  local pid_b=$!

  # MINOR 6 hardening: both processes must themselves have exited 0 (not just
  # "the file looks okay afterward") — a partial failure that still happened
  # to leave a plausible file behind would otherwise slip through silently.
  local status_a=0 status_b=0
  wait "$pid_a" || status_a=$?
  wait "$pid_b" || status_b=$?
  [ "$status_a" -eq 0 ]
  [ "$status_b" -eq 0 ]

  grep -qF "Concurrent A" "$BANK/agreements.md"
  grep -qF "Concurrent B" "$BANK/agreements.md"

  # MINOR 6 hardening: assert the exact issued-ID set, not just "2 distinct
  # ids" (which would also pass for e.g. {001, 003} with a gap/collision).
  local ids; ids="$(grep -Eo '^- AGR-[0-9]{3}' "$BANK/agreements.md" | grep -Eo '[0-9]{3}' | sort -u | tr '\n' ' ')"
  [ "$ids" = "001 002 " ]
}

@test "BLOCKER 2 regression: N parallel adds racing a pre-staled, foreign-owned lock all land, no loss/corruption" {
  run_agree add "Seed decision"
  [ "$status" -eq 0 ]
  local before_count
  before_count="$(grep -cE '^- AGR-[0-9]{3} ' "$BANK/agreements.md")"
  [ "$before_count" -eq 1 ]

  # Pre-stage a lock whose owner is a well-formed PID-RANDOM token with a
  # CONFIRMED-DEAD pid (spawn + reap, same idiom as the FINDING 1 tests) —
  # the reclaim decision is now keyed on PID liveness, not mtime/TTL, so
  # the fixture must look like a real (crashed) holder's token for the
  # reclaim path to even engage. Every racer's *first* failed mkdir reads
  # the SAME dead-owner lock, so all 5 contend for reclaim at (nearly) the
  # same instant — the exact contention this test exists to stress.
  (exit 0) &
  local dead_pid=$!
  wait "$dead_pid" 2>/dev/null || true
  mkdir "$BANK/.agreements.lock"
  printf '%s-1' "$dead_pid" >"$BANK/.agreements.lock/owner"
  python3 -c "import os,sys,time; os.utime(sys.argv[1], (int(sys.argv[2]), int(sys.argv[2])))" \
    "$BANK/.agreements.lock" "$(($(date +%s) - 3600))"

  # NOTE: LOCK_TIMEOUT stays generous (unlike the suite default of 2s) — 5
  # processes legitimately serialize through the SAME lock afterward, each
  # hold (3 python spawns: preflight, mutate, sync x2 files) taking real
  # wall-clock time, worse under 5-way contention. LOCK_TTL is irrelevant
  # to the actual reclaim here (a dead-PID owner reclaims immediately,
  # not on a TTL timer) but is set well below the old-fashioned 3600s-old
  # mtime anyway so the mtime-fallback branch (unreadable-owner case) would
  # ALSO agree, in case anything about the fixture ever regresses.
  export MB_AGREEMENTS_LOCK_TIMEOUT=30
  export MB_AGREEMENTS_LOCK_TTL=30
  local n=5 i pids=()
  for i in $(seq 1 "$n"); do
    bash "$SCRIPT" add "Racer $i" >"$TMPROOT/racer_$i.out" 2>&1 &
    pids+=("$!")
  done
  local pid rc_all=0
  for pid in "${pids[@]}"; do
    wait "$pid" || rc_all=1
  done
  [ "$rc_all" -eq 0 ]

  local total_count
  total_count="$(grep -cE '^- AGR-[0-9]{3} ' "$BANK/agreements.md")"
  [ "$total_count" -eq $((1 + n)) ]
  local distinct
  distinct="$(grep -Eo '^- AGR-[0-9]{3}' "$BANK/agreements.md" | sort -u | wc -l | tr -d ' ')"
  [ "$distinct" -eq $((1 + n)) ]
  for i in $(seq 1 "$n"); do
    grep -qF "Racer $i" "$BANK/agreements.md"
  done
}

@test "stale lock timeout exits non-zero without corrupting the existing file" {
  run_agree add "Established before the lock contention"
  [ "$status" -eq 0 ]
  local before; before="$(sha "$BANK/agreements.md")"

  mkdir "$BANK/.agreements.lock"
  printf 'external-holder' > "$BANK/.agreements.lock/owner"

  run_agree add "Should never land while the lock is held"
  [ "$status" -ne 0 ]
  [ "$(sha "$BANK/agreements.md")" = "$before" ]

  rmdir "$BANK/.agreements.lock" 2>/dev/null || rm -rf "$BANK/.agreements.lock"
}

# ═══════════════════════════════════════════════════════════════
# FINDING 1 (re-review of BLOCKER 2) — reclaim must be gated on the owner
# PID being confirmed DEAD, never on mtime/TTL alone. A live (or PID-reused)
# owner must never have its lock deleted out from under it.
# ═══════════════════════════════════════════════════════════════

@test "FINDING 1: a stale-looking lock whose owner PID is alive is NEVER reclaimed" {
  run_agree add "Before contention"
  [ "$status" -eq 0 ]
  local before; before="$(sha "$BANK/agreements.md")"

  # A well-formed PID-RANDOM token whose PID is genuinely alive right now
  # (the bats test process itself) — old enough mtime to look "stale" by
  # any TTL, which is exactly the point: mtime/TTL alone must NOT be
  # sufficient grounds to reclaim.
  mkdir "$BANK/.agreements.lock"
  printf '%s-1' "$$" >"$BANK/.agreements.lock/owner"
  python3 -c "import os,sys; os.utime(sys.argv[1], (int(sys.argv[2]), int(sys.argv[2])))" \
    "$BANK/.agreements.lock" "$(($(date +%s) - 3600))"

  export MB_AGREEMENTS_LOCK_TIMEOUT=3
  export MB_AGREEMENTS_LOCK_TTL=1
  run_agree add "Should never land while owner PID is alive"
  [ "$status" -ne 0 ]
  [ "$(sha "$BANK/agreements.md")" = "$before" ]
  # The lock directory itself must still exist — never reclaimed out from
  # under a live owner, regardless of how TTL-stale it looked.
  [ -d "$BANK/.agreements.lock" ]

  rm -rf "$BANK/.agreements.lock"
}

@test "FINDING 1: a stale lock whose owner PID is genuinely dead is safely reclaimed" {
  run_agree add "Before crash simulation"
  [ "$status" -eq 0 ]

  # Spawn and immediately reap a child so its PID is confirmed dead (not
  # merely "currently unused") by the time we use it.
  (exit 0) &
  local dead_pid=$!
  wait "$dead_pid" 2>/dev/null || true

  mkdir "$BANK/.agreements.lock"
  printf '%s-1' "$dead_pid" >"$BANK/.agreements.lock/owner"
  python3 -c "import os,sys; os.utime(sys.argv[1], (int(sys.argv[2]), int(sys.argv[2])))" \
    "$BANK/.agreements.lock" "$(($(date +%s) - 3600))"

  export MB_AGREEMENTS_LOCK_TIMEOUT=10
  run_agree add "After crash, reclaim should succeed"
  [ "$status" -eq 0 ]
  grep -qF "After crash, reclaim should succeed" "$BANK/agreements.md"
}

@test "NEW BUG A: LOCK_TIMEOUT is honored under contention, never silently replaced by LOCK_TTL (no busy-spin)" {
  run_agree add "Seed"
  [ "$status" -eq 0 ]

  mkdir "$BANK/.agreements.lock"
  printf '%s-1' "$$" >"$BANK/.agreements.lock/owner"
  python3 -c "import os,sys; os.utime(sys.argv[1], (int(sys.argv[2]), int(sys.argv[2])))" \
    "$BANK/.agreements.lock" "$(($(date +%s) - 3600))"

  export MB_AGREEMENTS_LOCK_TIMEOUT=3
  export MB_AGREEMENTS_LOCK_TTL=100
  local start end elapsed
  start="$(date +%s)"
  run_agree add "Should time out promptly, not hang near TTL"
  end="$(date +%s)"
  elapsed=$((end - start))
  [ "$status" -ne 0 ]
  # Close to LOCK_TIMEOUT (3s) — nowhere near LOCK_TTL (100s), and not
  # instantaneous either (a plain busy-spin bug would exit ~0s once it
  # gave up some other way, or hang until TTL).
  [ "$elapsed" -ge 2 ]
  [ "$elapsed" -le 15 ]

  rm -rf "$BANK/.agreements.lock"
}

# ═══════════════════════════════════════════════════════════════
# Usage / misc
# ═══════════════════════════════════════════════════════════════

@test "unknown subcommand exits 2 with usage" {
  run_agree bogus-command
  [ "$status" -eq 2 ]
}

@test "add without a statement exits 2 with usage" {
  run_agree add
  [ "$status" -eq 2 ]
}

# ═══════════════════════════════════════════════════════════════
# Codex review fixes — BLOCKER 1, BLOCKER 2 (above), MAJOR 3, 4, 5
# ═══════════════════════════════════════════════════════════════

@test "BLOCKER 1: a statement containing the mb-agreements end marker is rejected, zero writes" {
  run_agree add "breaks --> the block"
  [ "$status" -eq 2 ]
  [ ! -f "$BANK/agreements.md" ]
}

@test "BLOCKER 1: a statement containing the mb-agreements start marker is rejected, zero writes" {
  run_agree add "sneaky <!-- mb-agreements:start --> injection"
  [ "$status" -eq 2 ]
  [ ! -f "$BANK/agreements.md" ]
}

@test "BLOCKER 1: question text containing marker syntax is rejected, zero writes" {
  run_agree question "sneaky <!-- mb-agreements:end --> text"
  [ "$status" -eq 2 ]
  [ ! -f "$BANK/agreements.md" ]
}

@test "BLOCKER 1: a bare --> in a statement is rejected (any HTML-comment-close is unsafe)" {
  run_agree add "some markdown --> arrow"
  [ "$status" -eq 2 ]
  [ ! -f "$BANK/agreements.md" ]
}

@test "MAJOR 3: mentioning an AGR id inside statement text does not poison the next AGR id" {
  run_agree add "text about AGR-999, ignore it"
  [ "$status" -eq 0 ]
  run_agree add "normal decision"
  [ "$status" -eq 0 ]
  grep -qE '^- AGR-002 ' "$BANK/agreements.md"
  ! grep -qE '^- AGR-1000 ' "$BANK/agreements.md"
}

@test "MAJOR 3: mentioning a Q id inside question text does not poison the next Q id" {
  run_agree question "what about Q-500, is that real?"
  [ "$status" -eq 0 ]
  run_agree question "second question"
  [ "$status" -eq 0 ]
  grep -qE '^- Q-002: ' "$BANK/agreements.md"
}

@test "MAJOR 4: supersede of a non-existent target on a bank with no agreements.md creates nothing" {
  [ ! -f "$BANK/agreements.md" ]
  run_agree add "x" --supersedes 999
  [ "$status" -ne 0 ]
  [ ! -f "$BANK/agreements.md" ]
  [ ! -f "$PROJECT_ROOT/AGENTS.md" ]
  [ ! -f "$PROJECT_ROOT/CLAUDE.md" ]
}

@test "MAJOR 5: a damaged sync target aborts BEFORE the registry mutation commits (add)" {
  run_agree add "Seed decision"
  [ "$status" -eq 0 ]
  local before; before="$(sha "$BANK/agreements.md")"

  # AGENTS.md is healthy; CLAUDE.md is damaged (start marker, no end marker).
  printf 'above\n%s\nbroken\n' "$MARKER_START" >"$PROJECT_ROOT/CLAUDE.md"

  run_agree add "Should never land"
  [ "$status" -ne 0 ]
  [ "$(sha "$BANK/agreements.md")" = "$before" ]
  [[ "$(cat "$BANK/agreements.md")" != *"Should never land"* ]]
}

@test "MAJOR 5: a damaged sync target aborts BEFORE the registry mutation commits (defer)" {
  run_agree add "Deferrable decision"
  [ "$status" -eq 0 ]
  local id; id="$(extract_num "$output")"
  local before; before="$(sha "$BANK/agreements.md")"

  printf 'above\n%s\nbroken\n' "$MARKER_START" >"$PROJECT_ROOT/CLAUDE.md"

  run_agree defer "$id"
  [ "$status" -ne 0 ]
  [ "$(sha "$BANK/agreements.md")" = "$before" ]
}
