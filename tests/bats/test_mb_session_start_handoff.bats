#!/usr/bin/env bats
# Tests for hooks/mb-session-start-context.sh — handoff-v2 SessionStart consumption.
#
# Contract (design.md §4 "SessionStart consumption"):
#   - At SessionStart the hook injects {additional_context: "..."}.
#   - NEW: if <bank>/handoff/latest.md exists AND its mtime is newer than the
#     timestamp of the most recent `## YYYY-MM-DD` heading in progress.md,
#     PREPEND the capsule body (truncated to ~1500 chars) as a
#     "## Handoff capsule" section and log "[mb] using fresh handoff capsule"
#     to stderr.
#   - "Most recent" = the MAX date across ALL headings (progress.md is oldest-first;
#     the newest entry is at the bottom).
#   - Otherwise (absent or stale) → unchanged existing behaviour (fallback).

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  HOOK="$REPO_ROOT/hooks/mb-session-start-context.sh"

  command -v jq >/dev/null 2>&1 || skip "jq not available"

  PROJECT="$(mktemp -d)"
  MB="$PROJECT/.memory-bank"
  mkdir -p "$MB/handoff"
  printf '# Status\n\nActive: building handoff-v2\n' > "$MB/status.md"
  printf -- '- [ ] open item one\n- [x] done item\n' > "$MB/checklist.md"
  # Single-heading progress: most recent = 2026-06-07.
  printf '## 2026-06-07 (seed)\n- did a thing\n' > "$MB/progress.md"

  JSON_INPUT="{\"workspace_roots\":[\"$PROJECT\"]}"
}

teardown() {
  [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && rm -rf "$PROJECT"
}

# Run hook → capture stdout (JSON), stderr, status.
run_hook_split() {
  local err_file out_file
  err_file="$(mktemp)"
  out_file="$(mktemp)"
  printf '%s' "$JSON_INPUT" | env "$@" bash "$HOOK" >"$out_file" 2>"$err_file"
  status=$?
  stdout_text="$(cat "$out_file")"
  stderr_text="$(cat "$err_file")"
  rm -f "$err_file" "$out_file"
}

# The injected context string (additional_context field of the JSON output).
injected_context() {
  printf '%s' "$stdout_text" | jq -r '.additional_context // empty'
}

write_capsule() {
  local body="$1"
  printf '%s' "$body" > "$MB/handoff/latest.md"
}

# Set latest.md mtime to a fixed wall-clock (YYYYMMDDhhmm).
set_capsule_mtime() {
  touch -t "$1" "$MB/handoff/latest.md"
}

CAPSULE_BODY='---
capsule_version: 1
created: 2026-06-14T10:00:00Z
trigger: pre_compact
---

# Handoff capsule — 2026-06-14 10:00 UTC

## Now (what is in progress right this minute)
- KNOWN_BODY_MARKER wiring the precompact hook

## Next concrete step
- finish session-start consumption'

# ═══════════════════════════════════════════════════════════════
# Fresh capsule → prepended
# ═══════════════════════════════════════════════════════════════

@test "session-start: latest.md newer than last progress entry → capsule prepended" {
  write_capsule "$CAPSULE_BODY"
  # 2026-06-14 is after the 2026-06-07 progress heading → fresh.
  set_capsule_mtime 202606141200
  run_hook_split
  [ "$status" -eq 0 ]
  local ctx
  ctx="$(injected_context)"
  [[ "$ctx" == *"Handoff capsule"* ]]
  [[ "$ctx" == *"KNOWN_BODY_MARKER"* ]]
  [[ "$stderr_text" == *"using fresh handoff capsule"* ]]
}

@test "session-start: capsule is PREPENDED ahead of status.md" {
  write_capsule "$CAPSULE_BODY"
  set_capsule_mtime 202606141200
  run_hook_split
  [ "$status" -eq 0 ]
  local ctx cap_byte status_byte
  ctx="$(injected_context)"
  # Use byte offsets (grep -abo) — immune to the literal \n sequences used
  # in the CONTEXT wrapper string where "Handoff capsule" header and the
  # "status.md" section header might appear on the same physical line from
  # grep -n's perspective.
  cap_byte=$(printf '%s' "$ctx" | grep -abo "Handoff capsule" | head -1 | cut -d: -f1)
  status_byte=$(printf '%s' "$ctx" | grep -abo "status\.md" | head -1 | cut -d: -f1)
  [ -n "$cap_byte" ] || { echo "Handoff capsule not found in context" >&2; false; }
  [ -n "$status_byte" ] || { echo "status.md section not found in context" >&2; false; }
  [ "$cap_byte" -lt "$status_byte" ]
}

# ═══════════════════════════════════════════════════════════════
# MAJOR #1 regression: oldest-first progress.md — MAX date, not first line
# ═══════════════════════════════════════════════════════════════

@test "session-start: multiple headings — capsule older than NEWEST (bottom) entry is NOT prepended" {
  # progress.md has an OLD first heading AND a NEWER bottom heading.
  # The capsule is dated between them (after first, before newest).
  # With a correct MAX-date implementation the capsule should be STALE (not prepended).
  # A broken head-1 implementation would compare against the OLD first heading and
  # incorrectly prepend the capsule.
  printf '## 2026-06-01 (old entry)\n- old work\n\n## 2026-06-14 (newer entry)\n- new work\n' \
    > "$MB/progress.md"
  write_capsule "$CAPSULE_BODY"
  # Capsule mtime: 2026-06-08 — AFTER old entry (2026-06-01) but BEFORE newest (2026-06-14).
  set_capsule_mtime 202606080000
  run_hook_split
  [ "$status" -eq 0 ]
  local ctx
  ctx="$(injected_context)"
  # Must NOT be prepended: the capsule is older than the bottom (newest) heading.
  [[ "$ctx" != *"Handoff capsule"* ]]
  [[ "$ctx" != *"KNOWN_BODY_MARKER"* ]]
  [[ "$stderr_text" != *"using fresh handoff capsule"* ]]
}

@test "session-start: multiple headings — capsule newer than ALL entries IS prepended" {
  # progress.md has OLD first and a more-recent bottom entry.
  # The capsule is newer than both → should be prepended.
  printf '## 2026-06-01 (old entry)\n- old work\n\n## 2026-06-10 (mid entry)\n- mid work\n' \
    > "$MB/progress.md"
  write_capsule "$CAPSULE_BODY"
  # Capsule mtime: 2026-06-14 — after ALL headings.
  set_capsule_mtime 202606141200
  run_hook_split
  [ "$status" -eq 0 ]
  local ctx
  ctx="$(injected_context)"
  [[ "$ctx" == *"Handoff capsule"* ]]
  [[ "$ctx" == *"KNOWN_BODY_MARKER"* ]]
  [[ "$stderr_text" == *"using fresh handoff capsule"* ]]
}

# ═══════════════════════════════════════════════════════════════
# MAJOR #2 regression: portable mtime must be numeric on GNU/Linux
# ═══════════════════════════════════════════════════════════════

@test "session-start: mtime still numeric when stat-f-format-m yields non-numeric (GNU Linux shim)" {
  # On GNU/Linux `stat -f %m file` may print '?' and exit 0 (format string used
  # as a *file* argument by GNU stat). The hook must fall through to `stat -c %Y`
  # and obtain a proper numeric epoch, not a literal '?'.
  # We simulate this with a shim that mirrors the GNU stat behavior.
  local shimdir="$PROJECT/shim"
  mkdir -p "$shimdir"
  # The shim mimics GNU stat behavior on a system where BSD stat is unavailable:
  # - `-f %m <file>` → prints "?" and exits 0  (GNU stat treats -f as a file arg,
  #   then fails to stat "%" and "%m" as files, printing "?" for unknown files).
  # - `-c %Y <file>` → returns the real numeric mtime using BSD stat internally
  #   (this is the GNU form that the hook's fallback path exercises).
  # By making only the `-f %m` form broken we isolate the exact failure mode
  # described in MAJOR #2: the `||` chain never ran because GNU `stat -f %m`
  # exits 0 with a non-numeric result.
  # We derive the real stat binary path at shim-creation time (before PATH override).
  local real_stat
  real_stat="$(command -v stat)"
  cat > "$shimdir/stat" <<SHIM
#!/usr/bin/env bash
# Shim: -f %m → non-numeric "?" (mimics GNU stat). -c %Y → real mtime via python3.
# Using python3 for -c %Y so the shim is portable on both macOS and Linux
# (avoids calling the real stat with BSD flags on a GNU-stat Linux system).
if [ "\${1:-}" = "-f" ] && [ "\${2:-}" = "%m" ]; then
  printf '?\n'
  exit 0
fi
# -c %Y: use python3 for portable numeric mtime (avoids BSD-vs-GNU stat flag conflict).
if [ "\${1:-}" = "-c" ] && [ "\${2:-}" = "%Y" ]; then
  python3 -c 'import os,sys; print(int(os.path.getmtime(sys.argv[1])))' "\${3:-}"
  exit \$?
fi
exec "$real_stat" "\$@"
SHIM
  chmod +x "$shimdir/stat"

  write_capsule "$CAPSULE_BODY"
  # Capsule mtime set to well after the progress entry (must still prepend if mtime parsing works).
  set_capsule_mtime 202606141200

  # Run with the shim stat first on PATH.
  PATH="$shimdir:$PATH" run_hook_split
  [ "$status" -eq 0 ]
  local ctx
  ctx="$(injected_context)"
  # If mtime was parsed as non-numeric, the hook would crash or skip; the capsule
  # would NOT appear. A correct implementation still prepends it.
  [[ "$ctx" == *"Handoff capsule"* ]]
  [[ "$ctx" == *"KNOWN_BODY_MARKER"* ]]
  [[ "$stderr_text" == *"using fresh handoff capsule"* ]]
}

# ═══════════════════════════════════════════════════════════════
# Stale / absent → fallback (existing behaviour unchanged)
# ═══════════════════════════════════════════════════════════════

@test "session-start: latest.md older than last progress entry → NOT prepended" {
  write_capsule "$CAPSULE_BODY"
  # 2026-06-01 is BEFORE the 2026-06-07 progress heading → stale.
  set_capsule_mtime 202606010000
  run_hook_split
  [ "$status" -eq 0 ]
  local ctx
  ctx="$(injected_context)"
  [[ "$ctx" != *"Handoff capsule"* ]]
  [[ "$ctx" != *"KNOWN_BODY_MARKER"* ]]
  # Existing behaviour preserved.
  [[ "$ctx" == *"status.md"* ]]
  [[ "$stderr_text" != *"using fresh handoff capsule"* ]]
}

@test "session-start: no latest.md → fallback, existing behaviour unchanged" {
  # No capsule file at all.
  rm -f "$MB/handoff/latest.md"
  run_hook_split
  [ "$status" -eq 0 ]
  local ctx
  ctx="$(injected_context)"
  [[ "$ctx" != *"Handoff capsule"* ]]
  [[ "$ctx" == *"status.md"* ]]
}

# ═══════════════════════════════════════════════════════════════
# Truncation
# ═══════════════════════════════════════════════════════════════

@test "session-start: oversized latest.md is truncated in the injected context" {
  # Build a capsule far larger than the ~1500-char cap.
  {
    printf '# Handoff capsule — oversized\n\n## Now\n'
    # ~6000 chars of filler.
    for _ in $(seq 1 200); do
      printf 'FILLER_LINE_0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ\n'
    done
  } > "$MB/handoff/latest.md"
  set_capsule_mtime 202606141200

  run_hook_split
  [ "$status" -eq 0 ]
  local ctx cap_section_len
  ctx="$(injected_context)"
  [[ "$ctx" == *"Handoff capsule"* ]]
  # The capsule portion (everything up to the status.md section) must be bounded.
  cap_section_len=$(printf '%s' "$ctx" | awk '/status.md/{exit} {n+=length($0)+1} END{print n+0}')
  [ "$cap_section_len" -le 1800 ]
}
