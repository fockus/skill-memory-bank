#!/usr/bin/env bats
# scripts/mb-roadmap-sync.sh — bootstrap transfer of manual Group blocks, fence
# well-formedness and atomic write (S4 review findings 1/4/5/6).
#
# Split out of test_mb_roadmap_sync_group.bats to keep both files under the
# 400-line project gate (finding 11).
#
# Red-anchor: every test name starts with `roadmap_sync_bootstrap: `.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SYNC="$REPO_ROOT/scripts/mb-roadmap-sync.sh"
  GROUP="grp"

  TMPROOT="$(mktemp -d)"
  BANK="$TMPROOT/.memory-bank"
  mkdir -p "$BANK/plans" "$BANK/specs" "$BANK/context"

  printf -- '# Roadmap\n\nIntro that must stay byte-identical.\n\n<!-- mb-roadmap-auto -->\n<!-- /mb-roadmap-auto -->\n\nTrailing that must stay byte-identical.\n' > "$BANK/roadmap.md"
}

teardown() {
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

# mkspec <topic> <group> <ice-value|""> <blocked_by-csv|""> <confirmed|""> <status> <checked> <total> <created-dd>
mkspec() {
  local topic="$1" group="$2" ice="$3" blk="$4" conf="$5" status="$6" checked="${7:-0}" total="${8:-0}" dd="${9:-1}"
  local d="$BANK/specs/$topic"
  mkdir -p "$d"
  {
    printf '%s\n' '---'
    printf 'topic: %s\n' "$topic"
    printf 'group: %s\n' "$group"
    [ -n "$ice" ] && printf 'ice: %s\n' "$ice"
    [ -n "$conf" ] && printf 'ice_confirmed: %s\n' "$conf"
    printf 'blocked_by: [%s]\n' "$blk"
    printf 'status: %s\n' "$status"
    printf '%s\n' '---'
    printf '# Requirements: %s\n' "$topic"
  } > "$d/requirements.md"
  printf -- '---\ntopic: %s\ncreated: 2026-01-%02d\n---\n# ctx\n' "$topic" "$dd" > "$BANK/context/$topic.md"
  local i box
  : > "$d/tasks.md"
  printf '# Tasks\n\n' >> "$d/tasks.md"
  i=1
  while [ "$i" -le "$total" ]; do
    if [ "$i" -le "$checked" ]; then box="x"; else box=" "; fi
    printf -- '<!-- mb-task:%s -->\n## Task %s\n\n**DoD:**\n- [%s] item\n<!-- /mb-task:%s -->\n\n' "$i" "$i" "$box" "$i" >> "$d/tasks.md"
    i=$((i + 1))
  done
}

# ═══════════════════════════════════════════════════════════════
# Bootstrap transfer of a manual out-of-fence Group block (Task 6)
# ═══════════════════════════════════════════════════════════════

@test "roadmap_sync_bootstrap: removes a plain manual out-of-fence Group block once (idempotent)" {
  printf -- '# Roadmap\n\n<!-- mb-roadmap-auto -->\n<!-- /mb-roadmap-auto -->\n\n## Group: sdd-vision-pipeline\nhand-written legacy bootstrap body\nmore manual lines\n' > "$BANK/roadmap.md"
  mkspec childspec sdd-vision-pipeline "{impact: 8, confidence: 9, ease: 7}" "" true ready 0 1 1
  run bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  # exactly one header, and it is inside the fence; manual body gone
  [ "$(grep -c '^## Group: sdd-vision-pipeline$' "$BANK/roadmap.md")" -eq 1 ]
  gh=$(grep -n '^## Group: sdd-vision-pipeline$' "$BANK/roadmap.md" | head -1 | cut -d: -f1)
  fc=$(grep -n '^<!-- /mb-roadmap-auto -->$' "$BANK/roadmap.md" | head -1 | cut -d: -f1)
  [ "$gh" -lt "$fc" ]                     # header sits INSIDE the fence
  ! grep -qF 'hand-written legacy bootstrap body' "$BANK/roadmap.md"
  ! grep -qF 'more manual lines' "$BANK/roadmap.md"
  # idempotent second run
  cp "$BANK/roadmap.md" "$TMPROOT/once.md"
  run bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  diff "$TMPROOT/once.md" "$BANK/roadmap.md"
}

@test "roadmap_sync_bootstrap: removes a DECORATED legacy Group header block (finding 1)" {
  # The real .memory-bank/roadmap.md carries the manual header in the decorated
  # form `## <emoji> Group: <slug> (<date>, AGR-NNN) — <prose>`, NOT the bare
  # `## Group: <slug>`. Recognizing only the bare form leaves the legacy block
  # outside the fence and the roadmap ends up with TWO headers for one group.
  printf -- '# Roadmap\n\n<!-- mb-roadmap-auto -->\n<!-- /mb-roadmap-auto -->\n\n## \360\237\247\255 Group: sdd-vision-pipeline (2026-07-17, AGR-017) \342\200\224 main track\n\nUmbrella prose that is manual bootstrap.\n\n### Members of the group\n\n| # | slice | ICE |\n|---|---|---|\n| S1 | one | 504 |\n\n## Track 2 — a different H2 that MUST survive\n\nkeep me\n' > "$BANK/roadmap.md"
  mkspec childspec sdd-vision-pipeline "{impact: 8, confidence: 9, ease: 7}" "" true ready 0 1 1
  run bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  # only ONE header mentioning this group survives, and it is the generated one
  [ "$(grep -c 'Group: sdd-vision-pipeline' "$BANK/roadmap.md")" -eq 1 ]
  grep -qxF '## Group: sdd-vision-pipeline' "$BANK/roadmap.md"
  # the whole legacy H2 block is gone, including its nested H3 and table
  ! grep -qF 'Umbrella prose that is manual bootstrap.' "$BANK/roadmap.md"
  ! grep -qF '### Members of the group' "$BANK/roadmap.md"
  ! grep -qF '| S1 | one | 504 |' "$BANK/roadmap.md"
  # the NEXT unrelated H2 and its body must survive untouched
  grep -qF '## Track 2 — a different H2 that MUST survive' "$BANK/roadmap.md"
  grep -qxF 'keep me' "$BANK/roadmap.md"
  # idempotent
  cp "$BANK/roadmap.md" "$TMPROOT/once.md"
  run bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  diff "$TMPROOT/once.md" "$BANK/roadmap.md"
}

@test "roadmap_sync_bootstrap: a manual ## Group for a NON-discovered slug is never touched" {
  printf -- '# Roadmap\n\n<!-- mb-roadmap-auto -->\n<!-- /mb-roadmap-auto -->\n\n## Group: manual-note\nhand-written, not registry data\n' > "$BANK/roadmap.md"
  mkspec a "$GROUP" "{impact: 8, confidence: 9, ease: 7}" "" true ready 0 1 1
  run --separate-stderr bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  [[ "$stderr" != *"orphan_group"* ]]
  grep -qF 'hand-written, not registry data' "$BANK/roadmap.md"
}

@test "roadmap_sync_bootstrap: a decorated ## Group for a NON-discovered slug is never touched" {
  printf -- '# Roadmap\n\n<!-- mb-roadmap-auto -->\n<!-- /mb-roadmap-auto -->\n\n## \360\237\247\255 Group: manual-note (2026-01-01) \342\200\224 prose\nhand-written, not registry data\n' > "$BANK/roadmap.md"
  mkspec a "$GROUP" "{impact: 8, confidence: 9, ease: 7}" "" true ready 0 1 1
  run bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  grep -qF 'hand-written, not registry data' "$BANK/roadmap.md"
  grep -qF 'Group: manual-note' "$BANK/roadmap.md"
}

# ═══════════════════════════════════════════════════════════════
# Out-of-fence text is byte-identical (finding 5)
# ═══════════════════════════════════════════════════════════════

@test "roadmap_sync_bootstrap: blank-line runs outside the fence are preserved byte-for-byte" {
  # A user section with 4 consecutive blank lines must survive untouched: the
  # DoD promises byte-identical content outside the fence, so a global
  # `\n{3,}` -> `\n\n` collapse is a defect.
  printf -- '# Roadmap\n\n<!-- mb-roadmap-auto -->\n<!-- /mb-roadmap-auto -->\n\n## Notes\n\n\n\n\nspaced out on purpose\n' > "$BANK/roadmap.md"
  mkspec a "$GROUP" "{impact: 8, confidence: 9, ease: 7}" "" true ready 0 1 1
  outside_before=$(awk 'BEGIN{p=1} /<!-- mb-roadmap-auto -->/{p=0} p; /<!-- \/mb-roadmap-auto -->/{p=1}' "$BANK/roadmap.md")
  run bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  outside_after=$(awk 'BEGIN{p=1} /<!-- mb-roadmap-auto -->/{p=0} p; /<!-- \/mb-roadmap-auto -->/{p=1}' "$BANK/roadmap.md")
  [ "$outside_before" = "$outside_after" ]
  # explicit byte check on the 4-blank-line run
  run python3 -c 'import sys;print("YES" if "## Notes\n\n\n\n\nspaced out on purpose\n" in open(sys.argv[1],encoding="utf-8").read() else "NO")' "$BANK/roadmap.md"
  [ "$output" = "YES" ]
}

@test "roadmap_sync_bootstrap: blank-line runs survive even when a bootstrap block IS removed" {
  printf -- '# Roadmap\n\n<!-- mb-roadmap-auto -->\n<!-- /mb-roadmap-auto -->\n\n## Group: sdd-vision-pipeline\nmanual body\n\n## Notes\n\n\n\n\nspaced out on purpose\n' > "$BANK/roadmap.md"
  mkspec childspec sdd-vision-pipeline "{impact: 8, confidence: 9, ease: 7}" "" true ready 0 1 1
  run bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  ! grep -qxF 'manual body' "$BANK/roadmap.md"
  run python3 -c 'import sys;print("YES" if "## Notes\n\n\n\n\nspaced out on purpose\n" in open(sys.argv[1],encoding="utf-8").read() else "NO")' "$BANK/roadmap.md"
  [ "$output" = "YES" ]
}

# ═══════════════════════════════════════════════════════════════
# Fence well-formedness (finding 6)
# ═══════════════════════════════════════════════════════════════

@test "roadmap_sync_bootstrap: close-before-open fence is rejected (exit 2, no write)" {
  printf -- '# Roadmap\n\n<!-- /mb-roadmap-auto -->\nstray\n<!-- mb-roadmap-auto -->\n' > "$BANK/roadmap.md"
  mkspec a "$GROUP" "{impact: 8, confidence: 9, ease: 7}" "" true ready 0 1 1
  before="$(cat "$BANK/roadmap.md")"
  run --separate-stderr bash "$SYNC" "$BANK"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"malformed_fence"* ]]
  [ "$before" = "$(cat "$BANK/roadmap.md")" ]
}

@test "roadmap_sync_bootstrap: --check on a close-before-open fence exits 2, not 0" {
  printf -- '# Roadmap\n\n<!-- /mb-roadmap-auto -->\nstray\n<!-- mb-roadmap-auto -->\n' > "$BANK/roadmap.md"
  mkspec a "$GROUP" "{impact: 8, confidence: 9, ease: 7}" "" true ready 0 1 1
  run --separate-stderr bash "$SYNC" --check "$BANK"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"malformed_fence"* ]]
}

@test "roadmap_sync_bootstrap: a duplicate opening marker is rejected (exit 2, no write)" {
  printf -- '# Roadmap\n\n<!-- mb-roadmap-auto -->\n<!-- mb-roadmap-auto -->\n<!-- /mb-roadmap-auto -->\n' > "$BANK/roadmap.md"
  mkspec a "$GROUP" "{impact: 8, confidence: 9, ease: 7}" "" true ready 0 1 1
  before="$(cat "$BANK/roadmap.md")"
  run --separate-stderr bash "$SYNC" "$BANK"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"malformed_fence"* ]]
  [ "$before" = "$(cat "$BANK/roadmap.md")" ]
}

@test "roadmap_sync_bootstrap: a stray extra closing marker is rejected (exit 2, no write)" {
  printf -- '# Roadmap\n\n<!-- mb-roadmap-auto -->\n<!-- /mb-roadmap-auto -->\n\ntext\n\n<!-- /mb-roadmap-auto -->\n' > "$BANK/roadmap.md"
  mkspec a "$GROUP" "{impact: 8, confidence: 9, ease: 7}" "" true ready 0 1 1
  before="$(cat "$BANK/roadmap.md")"
  run --separate-stderr bash "$SYNC" "$BANK"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"malformed_fence"* ]]
  [ "$before" = "$(cat "$BANK/roadmap.md")" ]
}

@test "roadmap_sync_bootstrap: a single well-formed fence pair is still accepted" {
  mkspec a "$GROUP" "{impact: 8, confidence: 9, ease: 7}" "" true ready 0 1 1
  run bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^<!-- mb-roadmap-auto -->$' "$BANK/roadmap.md")" -eq 1 ]
  [ "$(grep -c '^<!-- /mb-roadmap-auto -->$' "$BANK/roadmap.md")" -eq 1 ]
}

# ═══════════════════════════════════════════════════════════════
# Atomic write (finding 4)
# ═══════════════════════════════════════════════════════════════

@test "roadmap_sync_bootstrap: roadmap is replaced atomically (rename, never truncate-in-place)" {
  # An atomic writer publishes through a fresh sibling temp + os.replace, so the
  # target inode CHANGES. A truncating `write_text` keeps the inode and leaves a
  # window where the roadmap is empty/partial on disk.
  mkspec a "$GROUP" "{impact: 8, confidence: 9, ease: 7}" "" true ready 0 1 1
  ino_before=$(ls -i "$BANK/roadmap.md" | awk '{print $1}')
  run bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  ino_after=$(ls -i "$BANK/roadmap.md" | awk '{print $1}')
  [ "$ino_before" != "$ino_after" ]
}

@test "roadmap_sync_bootstrap: a write failure leaves the previous roadmap fully intact" {
  # Fault injection: make os.replace fail. The original file must survive with
  # its original bytes -- not be truncated to empty or partial.
  mkspec a "$GROUP" "{impact: 8, confidence: 9, ease: 7}" "" true ready 0 1 1
  before="$(cat "$BANK/roadmap.md")"
  # Inject by running the sync with a sitecustomize that breaks os.replace.
  mkdir -p "$TMPROOT/site"
  cat > "$TMPROOT/site/sitecustomize.py" <<'PY'
import os
def boom(src, dst, *a, **k):
    raise OSError(28, "No space left on device")
os.replace = boom
PY
  PYTHONPATH="$TMPROOT/site" run bash "$SYNC" "$BANK"
  [ "$status" -ne 0 ]
  [ "$before" = "$(cat "$BANK/roadmap.md")" ]
  # and no temp turd left behind next to the roadmap
  [ -z "$(find "$BANK" -maxdepth 1 -name 'roadmap.md.*' -print -quit)" ]
}

# ═══════════════════════════════════════════════════════════════
# tasks.md parse errors are loud, not silently 0% (finding 7)
# ═══════════════════════════════════════════════════════════════

@test "roadmap_sync_bootstrap: a MISSING tasks.md is still a legitimate 0% (not an error)" {
  mkdir -p "$BANK/specs/nofile"
  printf -- '---\ntopic: nofile\ngroup: %s\nice: {impact: 8, confidence: 9, ease: 7}\nice_confirmed: true\nblocked_by: []\nstatus: draft\n---\n# R\n' "$GROUP" > "$BANK/specs/nofile/requirements.md"
  printf -- '---\ntopic: nofile\ncreated: 2026-01-01\n---\n# ctx\n' > "$BANK/context/nofile.md"
  run bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  grep -qE '^nofile — .* progress=0% tasks\(done=0,in_progress=0,planned=0,total=0\) — ' "$BANK/roadmap.md"
}

@test "roadmap_sync_bootstrap: mixed stage/task markers fail loudly instead of publishing 0%" {
  # A tasks.md with BOTH mb-stage and mb-task markers is a hard parse error in
  # mb_work_items.parse_work_items. Swallowing it publishes a confident 0% over
  # possibly-finished work and hides a partial write (REQ-012).
  mkdir -p "$BANK/specs/mixed"
  printf -- '---\ntopic: mixed\ngroup: %s\nice: {impact: 8, confidence: 9, ease: 7}\nice_confirmed: true\nblocked_by: []\nstatus: ready\n---\n# R\n' "$GROUP" > "$BANK/specs/mixed/requirements.md"
  printf -- '---\ntopic: mixed\ncreated: 2026-01-01\n---\n# ctx\n' > "$BANK/context/mixed.md"
  printf -- '# Tasks\n\n<!-- mb-task:1 -->\n## Task 1\n\n**DoD:**\n- [x] a\n<!-- /mb-task:1 -->\n\n<!-- mb-stage:2 -->\n## Stage 2\n\n**DoD:**\n- [ ] b\n<!-- /mb-stage:2 -->\n' > "$BANK/specs/mixed/tasks.md"
  before="$(cat "$BANK/roadmap.md")"
  run --separate-stderr bash "$SYNC" "$BANK"
  [ "$status" -eq 4 ]
  [[ "$stderr" == *"code=progress_parse_error"* ]]
  [[ "$stderr" == *"mixed"* ]]
  # roadmap must NOT have been written with the bogus 0%
  [ "$before" = "$(cat "$BANK/roadmap.md")" ]
}

@test "roadmap_sync_bootstrap: an unreadable tasks.md fails loudly instead of publishing 0%" {
  mkdir -p "$BANK/specs/noperm"
  printf -- '---\ntopic: noperm\ngroup: %s\nice: {impact: 8, confidence: 9, ease: 7}\nice_confirmed: true\nblocked_by: []\nstatus: ready\n---\n# R\n' "$GROUP" > "$BANK/specs/noperm/requirements.md"
  printf -- '---\ntopic: noperm\ncreated: 2026-01-01\n---\n# ctx\n' > "$BANK/context/noperm.md"
  printf -- '# Tasks\n\n<!-- mb-task:1 -->\n## Task 1\n\n**DoD:**\n- [x] a\n<!-- /mb-task:1 -->\n' > "$BANK/specs/noperm/tasks.md"
  chmod 000 "$BANK/specs/noperm/tasks.md"
  if [ -r "$BANK/specs/noperm/tasks.md" ]; then
    chmod 644 "$BANK/specs/noperm/tasks.md"
    skip "running as a user that bypasses file permissions"
  fi
  run --separate-stderr bash "$SYNC" "$BANK"
  chmod 644 "$BANK/specs/noperm/tasks.md"
  [ "$status" -eq 4 ]
  [[ "$stderr" == *"code=progress_parse_error"* ]]
}

@test "roadmap_sync_bootstrap: --check also surfaces a tasks.md parse error (exit 4)" {
  mkdir -p "$BANK/specs/mixed"
  printf -- '---\ntopic: mixed\ngroup: %s\nice: {impact: 8, confidence: 9, ease: 7}\nice_confirmed: true\nblocked_by: []\nstatus: ready\n---\n# R\n' "$GROUP" > "$BANK/specs/mixed/requirements.md"
  printf -- '---\ntopic: mixed\ncreated: 2026-01-01\n---\n# ctx\n' > "$BANK/context/mixed.md"
  printf -- '# Tasks\n\n<!-- mb-task:1 -->\n## T\n\n**DoD:**\n- [x] a\n<!-- /mb-task:1 -->\n\n<!-- mb-stage:2 -->\n## S\n\n**DoD:**\n- [ ] b\n<!-- /mb-stage:2 -->\n' > "$BANK/specs/mixed/tasks.md"
  run --separate-stderr bash "$SYNC" --check "$BANK"
  [ "$status" -eq 4 ]
  [[ "$stderr" == *"code=progress_parse_error"* ]]
}

@test "roadmap_sync_bootstrap: works when the bank path contains spaces" {
  SPACED="$TMPROOT/with space/.memory-bank"
  mkdir -p "$SPACED/specs" "$SPACED/context" "$SPACED/plans"
  printf -- '# Roadmap\n\n<!-- mb-roadmap-auto -->\n<!-- /mb-roadmap-auto -->\n' > "$SPACED/roadmap.md"
  local d="$SPACED/specs/a"
  mkdir -p "$d"
  printf -- '---\ntopic: a\ngroup: g\nice: {impact: 8, confidence: 9, ease: 7}\nice_confirmed: true\nblocked_by: []\nstatus: ready\n---\n# R\n' > "$d/requirements.md"
  printf -- '---\ntopic: a\ncreated: 2026-01-01\n---\n# ctx\n' > "$SPACED/context/a.md"
  printf -- '# Tasks\n\n<!-- mb-task:1 -->\n## Task 1\n\n**DoD:**\n- [x] item\n<!-- /mb-task:1 -->\n' > "$d/tasks.md"
  run bash "$SYNC" "$SPACED"
  [ "$status" -eq 0 ]
  grep -qE '^## Group: g$' "$SPACED/roadmap.md"
}
