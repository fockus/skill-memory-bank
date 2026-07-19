#!/usr/bin/env bats
# scripts/mb-roadmap-sync.sh — S4 Task 6: progress + Group sections + --check +
# unconfirmed_ice + orphan_group + bootstrap (design.md C2; REQ-002/003/012/013).
#
# Red-anchor: every test name starts with `roadmap_sync_group: `.

bats_require_minimum_version 1.5.0

load lib/s4_assert

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

group_block() {  # lines from `## Group:` region inside the fence
  awk '/<!-- \/mb-roadmap-auto -->/{f=0} f; /## Linked Specs/{f=1}' "$BANK/roadmap.md"
}

# ═══════════════════════════════════════════════════════════════
# Progress (REQ-002/REQ-012)
# ═══════════════════════════════════════════════════════════════

@test "roadmap_sync_group: member line carries percentage AND task counters (REQ-002)" {
  # REQ-002 (ubiquitous): "The roadmap-sync script shall render per-spec and
  # per-plan progress — percentage PLUS COUNTERS of stages/tasks planned, in
  # progress and done". A spec that exists only inside a Group block gets its
  # counters nowhere else, so the member line must carry them.
  mkspec alpha "$GROUP" "{impact: 8, confidence: 9, ease: 7}" "" true ready 2 4 1
  run bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  grep -qxF 'alpha — ice=504 — ready — progress=50% tasks(done=2,in_progress=0,planned=2,total=4) — blocked_by=none' "$BANK/roadmap.md"
}

@test "roadmap_sync_group: spec with no DoD tasks renders progress=0% with zero counters" {
  mkspec alpha "$GROUP" "{impact: 8, confidence: 9, ease: 7}" "" true draft 0 0 1
  run bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  grep -qxF 'alpha — ice=504 — draft — progress=0% tasks(done=0,in_progress=0,planned=0,total=0) — blocked_by=none' "$BANK/roadmap.md"
}

@test "roadmap_sync_group: a group-only spec (no plan links it) still gets counters" {
  # Regression guard for the actual REQ-002 gap: this spec appears in NO plan's
  # linked_specs, so the Group member line is its ONLY row in the roadmap.
  mkspec lonely "$GROUP" "{impact: 8, confidence: 9, ease: 7}" "" true ready 1 3 1
  run bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  refute_grep -qE '^- lonely —' "$BANK/roadmap.md"      # not in Linked Specs
  grep -qE '^lonely — .* tasks\(done=1,in_progress=0,planned=2,total=3\) — blocked_by=none$' "$BANK/roadmap.md"
}

# ═══════════════════════════════════════════════════════════════
# Group member rendering (REQ-003); intra-group ORDER lives in
# test_mb_roadmap_sync_group_order.bats
# ═══════════════════════════════════════════════════════════════

@test "roadmap_sync_group: unconfirmed ICE gets the (unconfirmed) member suffix" {
  mkspec a "$GROUP" "{impact: 8, confidence: 9, ease: 7}" "" false ready 0 1 1
  run bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  grep -qE 'a — ice=504 \(unconfirmed\) — ' "$BANK/roadmap.md"
}

@test "roadmap_sync_group: run is idempotent (bootstrap transfer happens once)" {
  mkspec a "$GROUP" "{impact: 8, confidence: 9, ease: 7}" "" true ready 1 2 1
  bash "$SYNC" "$BANK" >/dev/null
  cp "$BANK/roadmap.md" "$TMPROOT/once.md"
  bash "$SYNC" "$BANK" >/dev/null
  diff "$TMPROOT/once.md" "$BANK/roadmap.md"
}

# ═══════════════════════════════════════════════════════════════
# unconfirmed_ice escalation signal (REQ-013, AGR-021)
# ═══════════════════════════════════════════════════════════════

@test "roadmap_sync_group: unconfirmed_ice signal is exactly one literal line, order unchanged" {
  mkspec a "$GROUP" "{impact: 9, confidence: 8, ease: 7}" "" false ready 0 1 1  # 504 unconfirmed
  mkspec b "$GROUP" "{impact: 9, confidence: 8, ease: 7}" "" true  ready 0 1 2  # 504 confirmed
  run --separate-stderr bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  # exact literal single line (not a substring), and exactly one such line
  printf '%s\n' "$stderr" | grep -qxF 'unconfirmed_ice=a'
  [ "$(printf '%s\n' "$stderr" | grep -c '^unconfirmed_ice=')" -eq 1 ]
}

@test "roadmap_sync_group: flipping ice_confirmed to true drops the signal and (unconfirmed)" {
  mkspec a "$GROUP" "{impact: 9, confidence: 8, ease: 7}" "" false ready 0 1 1
  run --separate-stderr bash "$SYNC" "$BANK"
  [[ "$stderr" == *"unconfirmed_ice=a"* ]]
  # orchestrator flips the confirmation in the spec frontmatter
  sed -i.bak 's/ice_confirmed: false/ice_confirmed: true/' "$BANK/specs/a/requirements.md"
  run --separate-stderr bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  [[ "$stderr" != *"unconfirmed_ice="* ]]
  refute_grep -qE '\(unconfirmed\)' "$BANK/roadmap.md"
}

@test "roadmap_sync_group: no unconfirmed_ice line when all ICE are confirmed" {
  mkspec a "$GROUP" "{impact: 9, confidence: 8, ease: 7}" "" true ready 0 1 1
  run --separate-stderr bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  [[ "$stderr" != *"unconfirmed_ice="* ]]
}

# ═══════════════════════════════════════════════════════════════
# orphan_group + manual ## Group outside fence (R2-006, S4-A-02)
# ═══════════════════════════════════════════════════════════════

@test "roadmap_sync_group: stale in-fence Group header without a spec warns orphan_group and is dropped" {
  # Pre-seed a fence that already carries a Group header for a now-deleted spec.
  printf -- '# Roadmap\n\n<!-- mb-roadmap-auto -->\n## Linked Specs (active)\n\n_None._\n\n## Group: ghost\nprogress=0%%\n<!-- /mb-roadmap-auto -->\n' > "$BANK/roadmap.md"
  mkspec a "$GROUP" "{impact: 8, confidence: 9, ease: 7}" "" true ready 0 1 1
  run --separate-stderr bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"orphan_group"* ]]
  refute_grep -qE '^## Group: ghost$' "$BANK/roadmap.md"
  grep -qE "^## Group: $GROUP$" "$BANK/roadmap.md"
}

# ═══════════════════════════════════════════════════════════════
# --check (read-only, F-008)
# ═══════════════════════════════════════════════════════════════

@test "roadmap_sync_group: --check exits 0 when up to date, 1 when stale, never writes" {
  mkspec a "$GROUP" "{impact: 8, confidence: 9, ease: 7}" "" true ready 1 2 1
  bash "$SYNC" "$BANK" >/dev/null
  run bash "$SYNC" --check "$BANK"
  [ "$status" -eq 0 ]
  # make it stale by checking another task
  sed -i.bak 's/- \[ \] item/- [x] item/' "$BANK/specs/a/tasks.md"
  snapshot "$BANK/roadmap.md" "$BATS_TEST_TMPDIR/before.snap"
  run bash "$SYNC" --check "$BANK"
  [ "$status" -eq 1 ]
  assert_unchanged "$BANK/roadmap.md" "$BATS_TEST_TMPDIR/before.snap"   # --check never mutates
}

# ═══════════════════════════════════════════════════════════════
# Progress for ordinary plan / ungrouped-spec rows (REQ-002/Task 6)
# ═══════════════════════════════════════════════════════════════

@test "roadmap_sync_group: plain plan and ungrouped linked spec both carry progress+counters" {
  # REQ-002: every plan row and every (ungrouped) linked-spec row shows
  # progress=<N>% with per-item counters — not only Group member lines.
  mkdir -p "$BANK/specs/linkedspec"
  printf -- '---\ntopic: pln\nstatus: queued\nparallel_safe: false\ndepends_on: []\nlinked_specs: [linkedspec]\n---\n# Feature: pln\n\n<!-- mb-stage:1 -->\n## Stage 1\n\n**DoD:**\n- [x] a\n- [ ] b\n<!-- /mb-stage:1 -->\n' > "$BANK/plans/2026-02-01_feature_pln.md"
  printf -- '---\ntopic: linkedspec\nstatus: ready\n---\n# R\n' > "$BANK/specs/linkedspec/requirements.md"
  printf -- '# Tasks\n\n<!-- mb-task:1 -->\n## Task 1\n\n**DoD:**\n- [x] a\n- [ ] b\n<!-- /mb-task:1 -->\n' > "$BANK/specs/linkedspec/tasks.md"
  run bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  grep -qE '\[pln\]\(plans/2026-02-01_feature_pln.md\) — pln — progress=50% stages\(done=0,in_progress=1,planned=0,total=1\)$' "$BANK/roadmap.md"
  grep -qxF -- '- linkedspec — progress=50% tasks(done=0,in_progress=1,planned=0,total=1)' "$BANK/roadmap.md"
}

@test "roadmap_sync_group: legacy linked_specs forms all resolve to real tasks.md progress" {
  # The live bank carries THREE shapes of linked_specs entries:
  #   `foo`  ·  `specs/foo`  ·  `specs/foo/design.md`
  # Only the bare slug resolved before; the other two built specs/specs/foo/...
  # and silently rendered progress=0% total=0 for finished work (REQ-002).
  for slug in bare withprefix withfile; do
    mkdir -p "$BANK/specs/$slug"
    printf -- '---\ntopic: %s\nstatus: ready\n---\n# R\n' "$slug" > "$BANK/specs/$slug/requirements.md"
    printf -- '# Tasks\n\n<!-- mb-task:1 -->\n## Task 1\n\n**DoD:**\n- [x] a\n- [ ] b\n<!-- /mb-task:1 -->\n' > "$BANK/specs/$slug/tasks.md"
    printf -- '# Design\n' > "$BANK/specs/$slug/design.md"
  done
  printf -- '---\ntopic: pln\nstatus: queued\nparallel_safe: false\ndepends_on: []\nlinked_specs: [bare, specs/withprefix, "specs/withfile/design.md"]\n---\n# Feature: pln\n' > "$BANK/plans/2026-02-01_feature_pln.md"
  run bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  # every form normalizes to the topic slug and reports the SAME real progress
  grep -qxF -- '- bare — progress=50% tasks(done=0,in_progress=1,planned=0,total=1)' "$BANK/roadmap.md"
  grep -qxF -- '- withprefix — progress=50% tasks(done=0,in_progress=1,planned=0,total=1)' "$BANK/roadmap.md"
  grep -qxF -- '- withfile — progress=50% tasks(done=0,in_progress=1,planned=0,total=1)' "$BANK/roadmap.md"
  # and no un-normalized `specs/...` slug leaks into the Linked Specs rows
  refute_grep -qE '^- specs/' "$BANK/roadmap.md"
}

@test "roadmap_sync_group: differently-spelled linked_specs for ONE spec dedupe to a single row" {
  mkdir -p "$BANK/specs/dup"
  printf -- '---\ntopic: dup\nstatus: ready\n---\n# R\n' > "$BANK/specs/dup/requirements.md"
  printf -- '# Tasks\n\n<!-- mb-task:1 -->\n## Task 1\n\n**DoD:**\n- [x] a\n<!-- /mb-task:1 -->\n' > "$BANK/specs/dup/tasks.md"
  printf -- '---\ntopic: pln\nstatus: queued\nparallel_safe: false\ndepends_on: []\nlinked_specs: [dup, specs/dup, "specs/dup/design.md"]\n---\n# Feature: pln\n' > "$BANK/plans/2026-02-01_feature_pln.md"
  run bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^- dup — ' "$BANK/roadmap.md")" -eq 1 ]
}

# ═══════════════════════════════════════════════════════════════
# Group discovery is specs-only; plans are never members (design C2)
# ═══════════════════════════════════════════════════════════════

@test "roadmap_sync_group: a plan carrying group: is NOT a group member (specs-only discovery)" {
  printf -- '---\ntopic: pln\nstatus: queued\nparallel_safe: false\ndepends_on: []\ngroup: forbidden-plan-group\nice: {impact: 8, confidence: 9, ease: 7}\n---\n# Feature: pln\n' > "$BANK/plans/2026-02-01_feature_pln.md"
  run bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  refute_grep -qE '^## Group: forbidden-plan-group$' "$BANK/roadmap.md"
  refute_grep -qE '^## Group: ' "$BANK/roadmap.md"
}

# ═══════════════════════════════════════════════════════════════
# Malformed member ordering fields — warning vs hard error (design C2)
# ═══════════════════════════════════════════════════════════════

# ═══════════════════════════════════════════════════════════════
# unconfirmed_ice scope — only ICE-ordered items escalate (design C2)
# ═══════════════════════════════════════════════════════════════

@test "roadmap_sync_group: unconfirmed_ice excludes cancelled/paused/in_progress plans" {
  printf -- '---\ntopic: arch\nstatus: cancelled\nice: {impact: 8, confidence: 9, ease: 7}\nice_confirmed: false\n---\n# Feature: arch\n' > "$BANK/plans/2026-02-01_feature_arch.md"
  printf -- '---\ntopic: pausd\nstatus: paused\nice: {impact: 8, confidence: 9, ease: 7}\nice_confirmed: false\n---\n# Feature: pausd\n' > "$BANK/plans/2026-02-02_feature_pausd.md"
  printf -- '---\ntopic: prog\nstatus: in_progress\nparallel_safe: false\nice: {impact: 8, confidence: 9, ease: 7}\nice_confirmed: false\n---\n# Feature: prog\n' > "$BANK/plans/2026-02-03_feature_prog.md"
  run --separate-stderr bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  [[ "$stderr" != *"unconfirmed_ice="* ]]
}

@test "roadmap_sync_group: unconfirmed_ice DOES escalate a queued (ICE-ordered) plan" {
  printf -- '---\ntopic: q\nstatus: queued\nparallel_safe: false\ndepends_on: []\nice: {impact: 8, confidence: 9, ease: 7}\nice_confirmed: false\n---\n# Feature: q\n' > "$BANK/plans/2026-02-04_feature_q.md"
  run --separate-stderr bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  printf '%s\n' "$stderr" | grep -qxF 'unconfirmed_ice=q'
}

# ═══════════════════════════════════════════════════════════════
# Bootstrap transfer of a manual out-of-fence Group block (Task 6)
# ═══════════════════════════════════════════════════════════════

# ═══════════════════════════════════════════════════════════════
# Shared ordering fixture through the S4 consumer (R2-003-R3)
# ═══════════════════════════════════════════════════════════════

# ═══════════════════════════════════════════════════════════════
# Portability
# ═══════════════════════════════════════════════════════════════

