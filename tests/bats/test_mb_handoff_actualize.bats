#!/usr/bin/env bats
# Stage 1 (handoff-v2) — scripts/mb-handoff.sh capsule manager.
#
# Subcommands under test:
#   --actualize : build handoff/latest.md (frontmatter + 5 sections), archiving a
#                 pre-existing latest.md into handoff/archive/<ISO>.md first.
#   --read      : print latest.md to stdout (exit 1 if absent).
#   --rotate N  : prune handoff/archive/ to the N newest files by mtime (default 10).
#
# Portability note: the single-writer lock is mkdir-based (macOS has no flock), so a
# held lock dir blocks a concurrent --actualize. Tests drive the bank path positionally
# so each case runs in its own mktemp sandbox.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-handoff.sh"
  TMP="$(mktemp -d)"
  MB="$TMP/.memory-bank"
  mkdir -p "$MB/plans"
  _seed_bank
}
teardown() { [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"; }

# Seed a realistic-but-small bank: roadmap active-plans block, progress entries,
# unchecked checklist items, HIGH backlog items, status.md.
_seed_bank() {
  cat > "$MB/roadmap.md" <<'EOF'
# Project — Plan

## Active plans

<!-- mb-active-plans -->
- [2026-05-23] [plans/2026-05-23_feature_handoff-v2.md](plans/2026-05-23_feature_handoff-v2.md) — feature — Handoff 2.0
- [2026-05-23] [plans/2026-05-23_feature_reviewer-v2.md](plans/2026-05-23_feature_reviewer-v2.md) — feature — Reviewer 2.0
<!-- /mb-active-plans -->
EOF

  cat > "$MB/progress.md" <<'EOF'
# Progress

## 2026-06-10

### Entry one — alpha
alpha line 1
alpha line 2
alpha line 3 should not appear

### Entry two — beta
beta line 1
beta line 2

### Entry three — gamma
gamma line 1
gamma line 2

### Entry four — delta
delta line 1
delta line 2

### Entry five — epsilon
epsilon line 1
epsilon line 2

### Entry six — zeta
zeta line 1
zeta line 2
EOF

  cat > "$MB/checklist.md" <<'EOF'
# Checklist

- [x] already done item
- [ ] first unchecked item
- [ ] second unchecked item
- [ ] third unchecked item
EOF

  cat > "$MB/backlog.md" <<'EOF'
# Backlog

### I-061 — Cursor compatibility remediation [HIGH, PLANNED, 2026-05-24]
body
### I-070 — Some medium thing [MEDIUM, NEW, 2026-05-24]
body
### I-001 — Benchmarks [HIGH, DEFERRED, 2026-04-20]
body
### I-002 — sqlite-vec semantic search [HIGH, DEFERRED, 2026-04-20]
body
### I-003 — Fourth high [HIGH, NEW, 2026-04-19]
body
EOF

  cat > "$MB/status.md" <<'EOF'
# Status
Current focus: handoff capsule.
EOF
}

@test "--actualize writes latest.md with all 5 sections + frontmatter keys" {
  run bash "$SCRIPT" --actualize "$MB"
  [ "$status" -eq 0 ]
  L="$MB/handoff/latest.md"
  [ -f "$L" ]
  # frontmatter keys
  grep -q '^capsule_version: 1$' "$L"
  grep -q '^created: ' "$L"
  grep -q '^trigger: ' "$L"
  grep -q '^session_id: ' "$L"
  grep -q '^active_plan: ' "$L"
  grep -q '^active_stage: ' "$L"
  # five section headings
  grep -q '^## Now' "$L"
  grep -q '^## Done since last capsule' "$L"
  grep -q '^## Open blockers' "$L"
  grep -q '^## Next concrete step' "$L"
  grep -q '^## Pointers' "$L"
}

@test "--actualize derives active_plan from roadmap mb-active-plans block" {
  run bash "$SCRIPT" --actualize "$MB"
  [ "$status" -eq 0 ]
  grep -q '^active_plan: plans/2026-05-23_feature_handoff-v2.md$' "$MB/handoff/latest.md"
}

@test "--actualize content draws from collected data (progress, checklist, backlog)" {
  run bash "$SCRIPT" --actualize "$MB"
  [ "$status" -eq 0 ]
  L="$MB/handoff/latest.md"
  # Done section reflects recent progress headings (newest 5, not the 6th-from-top)
  grep -q 'epsilon' "$L"
  # Next step is the first unchecked checklist item
  grep -q 'first unchecked item' "$L"
  # Blockers reflect a HIGH backlog item (not "None" here)
  grep -q 'I-061' "$L"
  # Pointers reference status.md + checklist.md
  grep -q 'status.md' "$L"
  grep -q 'checklist.md' "$L"
}

@test "--actualize archives a pre-existing latest.md into archive/" {
  printf 'OLD CAPSULE\n' > "$MB/handoff/latest.md" 2>/dev/null || { mkdir -p "$MB/handoff"; printf 'OLD CAPSULE\n' > "$MB/handoff/latest.md"; }
  run bash "$SCRIPT" --actualize "$MB"
  [ "$status" -eq 0 ]
  [ -d "$MB/handoff/archive" ]
  # exactly one archived file, and it carries the OLD content
  count="$(find "$MB/handoff/archive" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')"
  [ "$count" -eq 1 ]
  archived="$(find "$MB/handoff/archive" -maxdepth 1 -type f -name '*.md' | head -1)"
  grep -q 'OLD CAPSULE' "$archived"
  # new latest.md is freshly generated (not the old content)
  ! grep -q 'OLD CAPSULE' "$MB/handoff/latest.md"
}

@test "--rotate 10 prunes archive/ to 10 newest (seed 13)" {
  mkdir -p "$MB/handoff/archive"
  for i in $(seq 1 13); do
    f="$MB/handoff/archive/2026-06-15T0000$(printf '%02d' "$i")Z.md"
    printf 'cap %s\n' "$i" > "$f"
    touch -t "20260615$(printf '%02d' "$i")00" "$f"
  done
  [ "$(find "$MB/handoff/archive" -type f | wc -l | tr -d ' ')" -eq 13 ]
  run bash "$SCRIPT" --rotate 10 "$MB"
  [ "$status" -eq 0 ]
  [ "$(find "$MB/handoff/archive" -type f | wc -l | tr -d ' ')" -eq 10 ]
  # the 3 oldest (01,02,03) are gone; a newer one (13) survives
  [ ! -f "$MB/handoff/archive/2026-06-15T000001Z.md" ]
  [ -f "$MB/handoff/archive/2026-06-15T000013Z.md" ]
}

@test "--rotate default keeps 10" {
  mkdir -p "$MB/handoff/archive"
  for i in $(seq 1 12); do
    f="$MB/handoff/archive/2026-06-15T0000$(printf '%02d' "$i")Z.md"
    printf 'cap %s\n' "$i" > "$f"
    touch -t "20260615$(printf '%02d' "$i")00" "$f"
  done
  run bash "$SCRIPT" --rotate "$MB"
  [ "$status" -eq 0 ]
  [ "$(find "$MB/handoff/archive" -type f | wc -l | tr -d ' ')" -eq 10 ]
}

@test "mkdir-lock prevents concurrent --actualize" {
  mkdir -p "$MB/handoff"
  # Hold the lock dir as if another writer owns it.
  mkdir "$MB/handoff/.lock"
  # Short lock timeout so the test is fast; the held lock must cause non-zero exit.
  run env MB_HANDOFF_LOCK_TIMEOUT=1 bash "$SCRIPT" --actualize "$MB"
  [ "$status" -ne 0 ]
  rmdir "$MB/handoff/.lock"
}

@test "latest.md total char count is <= 1500" {
  run bash "$SCRIPT" --actualize "$MB"
  [ "$status" -eq 0 ]
  bytes="$(wc -c < "$MB/handoff/latest.md" | tr -d ' ')"
  [ "$bytes" -le 1500 ]
}

@test "1500-char cap holds even with oversized inputs (truncation ellipsis)" {
  # The capsule self-bounds item *counts* (top 10 checklist, last 5 progress, top 3
  # backlog), so overflow is driven by long *individual* entries, not item volume.
  pad() { printf '%*s' "$1" '' | tr ' ' "$2"; }
  : > "$MB/checklist.md"
  printf '# Checklist\n' >> "$MB/checklist.md"
  for i in $(seq 1 10); do
    printf -- '- [ ] %s\n' "$(pad 120 X)" >> "$MB/checklist.md"
  done
  : > "$MB/progress.md"
  printf '# Progress\n\n## 2026-06-15\n' >> "$MB/progress.md"
  for i in $(seq 1 5); do
    printf '\n### %s\n%s\n%s\n' "$(pad 80 H)" "$(pad 90 b)" "$(pad 90 c)" >> "$MB/progress.md"
  done
  : > "$MB/backlog.md"
  printf '# Backlog\n' >> "$MB/backlog.md"
  for i in $(seq 1 3); do
    printf '### I-%03d — %s [HIGH, NEW, 2026-01-01]\n' "$i" "$(pad 100 D)" >> "$MB/backlog.md"
  done
  run bash "$SCRIPT" --actualize "$MB"
  [ "$status" -eq 0 ]
  L="$MB/handoff/latest.md"
  bytes="$(wc -c < "$L" | tr -d ' ')"
  [ "$bytes" -le 1500 ]
  # MAJOR #1 / MINOR #7: all five required sections MUST survive truncation —
  # an over-long bullet must never evict a whole downstream section.
  sections="$(grep -c '^## ' "$L")"
  [ "$sections" -eq 5 ]
  grep -q '^## Now' "$L"
  grep -q '^## Done since last capsule' "$L"
  grep -q '^## Open blockers' "$L"
  grep -q '^## Next concrete step' "$L"
  grep -q '^## Pointers' "$L"
  # ellipsis marker present because content was actually clipped
  grep -q '\.\.\.' "$L"
  # valid UTF-8 (never cut a multibyte codepoint mid-sequence)
  python3 -c "import sys; sys.exit(0 if open('$L','rb').read().decode('utf-8') else 1)"
}

@test "1500 cap is byte-bounded for multi-byte (UTF-8) content" {
  # Multi-byte progress notes (Cyrillic) make char-count < byte-count; the cap must
  # hold in bytes so the verbatim injection never blows a byte/token budget.
  : > "$MB/progress.md"
  printf '# Progress\n\n## 2026-06-15\n' >> "$MB/progress.md"
  for i in $(seq 1 5); do
    printf '\n### Запись номер %s\n' "$i" >> "$MB/progress.md"
    printf 'Длинная многобайтовая строка прогресса с кириллицей номер %s и хвостом.\n' "$i" >> "$MB/progress.md"
    printf 'Вторая строка тела записи с дополнительным многобайтовым текстом %s.\n' "$i" >> "$MB/progress.md"
  done
  run bash "$SCRIPT" --actualize "$MB"
  [ "$status" -eq 0 ]
  bytes="$(wc -c < "$MB/handoff/latest.md" | tr -d ' ')"
  [ "$bytes" -le 1500 ]
}

@test "--read prints latest.md when present, exit 0" {
  bash "$SCRIPT" --actualize "$MB" >/dev/null
  run bash "$SCRIPT" --read "$MB"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^# Handoff capsule'
}

@test "--read exits 1 when latest.md absent" {
  run bash "$SCRIPT" --read "$MB"
  [ "$status" -eq 1 ]
}

@test "trigger defaults to manual_update and is overridable via positional arg" {
  run bash "$SCRIPT" --actualize "$MB"
  [ "$status" -eq 0 ]
  grep -q '^trigger: manual_update$' "$MB/handoff/latest.md"

  run bash "$SCRIPT" --actualize "$MB" pre_compact
  [ "$status" -eq 0 ]
  grep -q '^trigger: pre_compact$' "$MB/handoff/latest.md"
}

@test "trigger overridable via MB_HANDOFF_TRIGGER env" {
  run env MB_HANDOFF_TRIGGER=pre_compact bash "$SCRIPT" --actualize "$MB"
  [ "$status" -eq 0 ]
  grep -q '^trigger: pre_compact$' "$MB/handoff/latest.md"
}

# MAJOR #4 — archive filenames must be colon-free (design.md:107,128):
# <YYYY-MM-DDTHHMMSSZ>.md, never <...T12:34:56Z>.md (':' is illegal on some FS).
@test "archive filenames are colon-free (YYYY-MM-DDTHHMMSSZ)" {
  # Two actualize runs guarantee at least one archived (rotated) capsule.
  run bash "$SCRIPT" --actualize "$MB"
  [ "$status" -eq 0 ]
  run bash "$SCRIPT" --actualize "$MB"
  [ "$status" -eq 0 ]
  [ -d "$MB/handoff/archive" ]
  local found=0 f base
  while IFS= read -r f; do
    found=1
    base="$(basename "$f")"
    # No colon anywhere in the basename.
    case "$base" in *:*) printf 'colon in archive name: %s\n' "$base" >&2; return 1 ;; esac
    # Matches the colon-free design contract stamp.
    printf '%s' "$base" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{6}Z'
  done < <(find "$MB/handoff/archive" -maxdepth 1 -type f -name '*.md')
  [ "$found" -eq 1 ]
}

# MAJOR #5 — archive-before-write must be non-destructive: the OLD latest.md
# stays in place (copied to archive) until the NEW one is atomically installed.
@test "--actualize preserves old content and never loses latest.md" {
  mkdir -p "$MB/handoff"
  printf 'OLD UNIQUE MARKER 12345\n' > "$MB/handoff/latest.md"
  run bash "$SCRIPT" --actualize "$MB"
  [ "$status" -eq 0 ]
  # (a) latest.md exists with NEW content
  [ -f "$MB/handoff/latest.md" ]
  grep -q '^# Handoff capsule' "$MB/handoff/latest.md"
  ! grep -q 'OLD UNIQUE MARKER 12345' "$MB/handoff/latest.md"
  # (b) exactly one archive file, carrying the OLD content
  count="$(find "$MB/handoff/archive" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')"
  [ "$count" -eq 1 ]
  archived="$(find "$MB/handoff/archive" -maxdepth 1 -type f -name '*.md' | head -1)"
  grep -q 'OLD UNIQUE MARKER 12345' "$archived"
}

# MAJOR #6 — _lock_release must not delete a lock owned by a different process.
@test "_lock_release only removes a lock it still owns (owner token)" {
  # Source the script's functions without running main().
  MB_HANDOFF_SOURCE_ONLY=1 source "$SCRIPT"
  local lock="$MB/handoff/.lock"
  mkdir -p "$MB/handoff"
  # Acquire writes our owner token into $lock/owner.
  run _lock_acquire "$lock" 1 120
  [ "$status" -eq 0 ]
  local mine
  mine="$(cat "$lock/owner")"
  [ -n "$mine" ]
  # Simulate a NEW owner taking over the dir (different token).
  printf 'someone-else-9999' > "$lock/owner"
  # Releasing with OUR token must NOT remove the new owner's lock.
  _lock_release "$lock" "$mine"
  [ -d "$lock" ]
  grep -q 'someone-else-9999' "$lock/owner"
  # Releasing with the CURRENT token does remove it.
  _lock_release "$lock" "someone-else-9999"
  [ ! -d "$lock" ]
}
