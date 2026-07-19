#!/usr/bin/env bats
# Tests for scripts/mb-roadmap-sync.sh — S4 Task 1: legacy/priority ordering
# modes + ICE-component parsing (spec svp-roadmap-backlog-db, design.md C1/C2).
#
# Red-anchor convention (norm X-05): EVERY test name starts with
# `roadmap_sync_ice: ` so the gated Eval anchor `not ok [0-9]+ roadmap_sync_ice: `
# distinguishes a real failure from a missing-file `not ok 1 bats-gather-tests`.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SYNC="$REPO_ROOT/scripts/mb-roadmap-sync.sh"
  FIX="$REPO_ROOT/tests/fixtures/roadmap_sync_legacy"

  TMPROOT="$(mktemp -d)"
  BANK="$TMPROOT/.memory-bank"
  mkdir -p "$BANK/plans"

  cat > "$BANK/roadmap.md" <<'EOF'
# Roadmap

Intro prose that must stay byte-identical.

<!-- mb-roadmap-auto -->
<!-- /mb-roadmap-auto -->

Trailing prose that must stay byte-identical.
EOF
}

teardown() {
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

# Write a plan file. $1=filename $2=topic $3=frontmatter-extra-lines(newline sep)
mkplan() {
  local fname="$1" topic="$2" extra="$3"
  {
    printf '%s\n' '---'
    printf 'topic: %s\n' "$topic"
    printf 'status: queued\n'
    printf 'parallel_safe: false\n'
    printf '%b' "$extra"
    printf '%s\n' '---'
    printf '# Feature: %s\n' "$topic"
  } > "$BANK/plans/$fname"
}

# Emit the lines of the Next section (between its heading and the next `## `).
next_section() {
  awk '
    /^## Next \(strict order/ { inside=1; next }
    inside && /^## / { inside=0 }
    inside { print }
  ' "$BANK/roadmap.md"
}

# ── Immutable legacy regression (no ice/pin ⇒ must stay byte-identical) ───────
# The byte-identical legacy contract is proven against FROZEN GOLDENS generated
# ONCE by the pre-S4 script + pre-S4 _lib.sh (see tests/fixtures/roadmap_sync_
# legacy/{corpus,roadmap,golden,real_corpus}/). A moving `git show HEAD` oracle
# was rejected (post-commit it imports mb_roadmap_order but the extractor only
# copied the script + _lib.sh ⇒ ModuleNotFoundError, and HEAD is not immutable).
# The synthetic corpus covers every section/warning branch: in_progress,
# Next-with-deps, parallel-safe, parallel_safe-with-deps (routed to Next),
# paused, cancelled, linked_specs(+singular linked_spec), block-style list
# warning, a no-frontmatter skip, and a dependency cycle. real_corpus/ is the
# full 18-plan snapshot of HEAD:.memory-bank/plans/*.md.

# Run ONLY the candidate against a frozen corpus + roadmap style and assert its
# ORDERING + section structure is byte-identical to the frozen pre-S4 legacy
# golden. The pre-S4 golden captures the legacy DFS ordering only; Task 6 layers
# an additive `— progress=<N>% stages(...)/tasks(...)` column onto every plan /
# spec row, so we strip exactly that column before diffing (proving the ordering
# is unchanged) and separately assert progress IS present (REQ-002).
# $1 = corpus dir (holds plans/ + roadmap.md), $2 = golden dir.
compare_candidate_vs_golden() {
  local corpus="$1" golden="$2"
  local bank="$TMPROOT/cand/.memory-bank"
  mkdir -p "$bank/plans"
  cp "$corpus/plans/"*.md "$bank/plans/"
  cp "$corpus/roadmap.md" "$bank/roadmap.md"

  local rc=0
  bash "$SYNC" "$bank" >"$TMPROOT/o" 2>"$TMPROOT/e.raw" || rc=$?
  [ "$rc" -eq 0 ]

  # Every plan row carries progress+counters (Task 6 / REQ-002) …
  grep -qE ' — progress=[0-9]+% stages\(done=[0-9]+,in_progress=[0-9]+,planned=[0-9]+,total=[0-9]+\)$' "$bank/roadmap.md"
  # … then strip the additive progress column and prove the ORDERING + section
  # structure is byte-identical to the frozen pre-S4 legacy golden.
  sed -E 's/ — progress=[0-9]+% (stages|tasks)\([^)]*\)//' "$bank/roadmap.md" > "$TMPROOT/roadmap.stripped"
  diff "$golden/roadmap.md" "$TMPROOT/roadmap.stripped"
  diff "$golden/stdout" "$TMPROOT/o"
  # stderr warnings embed the (bank-specific) plan path — normalize before diff.
  sed "s#$bank#BANK#g" "$TMPROOT/e.raw" > "$TMPROOT/e.n"
  diff "$golden/stderr" "$TMPROOT/e.n"
}

# For the synthetic corpus the roadmap style varies (one/none/multi); assemble a
# per-style corpus dir from the shared plans + the chosen roadmap fixture.
compare_style_vs_golden() {
  local style="$1"
  local corpus="$TMPROOT/corpus-$style"
  mkdir -p "$corpus/plans"
  cp "$FIX/corpus/plans/"*.md "$corpus/plans/"
  cp "$FIX/roadmap/$style.md" "$corpus/roadmap.md"
  compare_candidate_vs_golden "$corpus" "$FIX/golden/$style"
}

# ═══════════════════════════════════════════════════════════════
# Legacy mode — no ice/pin anywhere ⇒ today's DFS dependency_order()
# ═══════════════════════════════════════════════════════════════

@test "roadmap_sync_ice: legacy mode preserves DFS order C,A,B on A->C graph" {
  # File order A/B/C; A depends_on C. Today's DFS yields C, A, B (NOT B,C,A).
  mkplan "plan-a.md" "a" "depends_on: [plan-c.md]\n"
  mkplan "plan-b.md" "b" "depends_on: []\n"
  mkplan "plan-c.md" "c" "depends_on: []\n"

  run bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]

  next_section > "$TMPROOT/next.txt"
  # Expect order c, a, b
  order=$(grep -oE '\[(a|b|c)\]' "$TMPROOT/next.txt" | tr -d '[]' | tr '\n' ' ')
  [ "$order" = "c a b " ]
}

@test "roadmap_sync_ice: full corpus byte-identical to the frozen legacy golden (one fence)" {
  compare_style_vs_golden one
}

@test "roadmap_sync_ice: byte-identical to the frozen legacy golden when the fence is missing (injected)" {
  compare_style_vs_golden none
}

@test "roadmap_sync_ice: byte-identical to the frozen legacy golden with multiple fences (only first regenerated)" {
  compare_style_vs_golden multi
}

@test "roadmap_sync_ice: full 18-plan HEAD corpus byte-identical to the frozen legacy golden" {
  compare_candidate_vs_golden "$FIX/real_corpus" "$FIX/real_corpus/golden"
}

@test "roadmap_sync_ice: outside-fence content is byte-identical and idempotent" {
  mkplan "plan-a.md" "a" "depends_on: []\n"
  before_head=$(sed -n '1,4p' "$BANK/roadmap.md")
  bash "$SYNC" "$BANK" >/dev/null
  cp "$BANK/roadmap.md" "$TMPROOT/once.txt"
  bash "$SYNC" "$BANK" >/dev/null
  diff "$TMPROOT/once.txt" "$BANK/roadmap.md"
  after_head=$(sed -n '1,4p' "$BANK/roadmap.md")
  [ "$before_head" = "$after_head" ]
  grep -q "Trailing prose that must stay byte-identical." "$BANK/roadmap.md"
}

@test "roadmap_sync_ice: a section with only invalid ice stays in legacy mode" {
  # Only a plain-int (invalid) ice present → NOT priority mode → DFS order.
  mkplan "plan-a.md" "a" "depends_on: [plan-c.md]\nice: 432\n"
  mkplan "plan-b.md" "b" "depends_on: []\n"
  mkplan "plan-c.md" "c" "depends_on: []\n"

  run bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  next_section > "$TMPROOT/next.txt"
  order=$(grep -oE '\[(a|b|c)\]' "$TMPROOT/next.txt" | tr -d '[]' | tr '\n' ' ')
  [ "$order" = "c a b " ]
}

# ═══════════════════════════════════════════════════════════════
# Priority mode — valid ice OR pin present ⇒ round-based Kahn + comparator
# ═══════════════════════════════════════════════════════════════

@test "roadmap_sync_ice: orders by computed score I*C*E descending" {
  mkplan "plan-x.md" "x" "depends_on: []\nice: {impact: 8, confidence: 9, ease: 7}\n" # 504
  mkplan "plan-y.md" "y" "depends_on: []\nice: {impact: 8, confidence: 9, ease: 6}\n" # 432
  mkplan "plan-z.md" "z" "depends_on: []\nice: {impact: 10, confidence: 8, ease: 5}\n" # 400

  run bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  next_section > "$TMPROOT/next.txt"
  order=$(grep -oE '\[(x|y|z)\]' "$TMPROOT/next.txt" | tr -d '[]' | tr '\n' ' ')
  [ "$order" = "x y z " ]
}

@test "roadmap_sync_ice: pin overrides score (pinned item first)" {
  mkplan "plan-x.md" "x" "depends_on: []\nice: {impact: 8, confidence: 9, ease: 7}\n" # 504
  mkplan "plan-y.md" "y" "depends_on: []\nice: {impact: 8, confidence: 9, ease: 6}\n" # 432
  mkplan "plan-z.md" "z" "depends_on: []\nice: {impact: 10, confidence: 8, ease: 5}\npin: 1\n" # 400 pinned

  run bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  next_section > "$TMPROOT/next.txt"
  order=$(grep -oE '\[(x|y|z)\]' "$TMPROOT/next.txt" | tr -d '[]' | tr '\n' ' ')
  [ "$order" = "z x y " ]
}

@test "roadmap_sync_ice: duplicate pin does not crash, order is deterministic by score" {
  mkplan "plan-x.md" "x" "depends_on: []\nice: {impact: 5, confidence: 6, ease: 10}\npin: 1\n" # 300 pin1
  mkplan "plan-y.md" "y" "depends_on: []\nice: {impact: 10, confidence: 10, ease: 5}\npin: 1\n" # 500 pin1

  run bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  next_section > "$TMPROOT/next.txt"
  order=$(grep -oE '\[(x|y)\]' "$TMPROOT/next.txt" | tr -d '[]' | tr '\n' ' ')
  # Same pin ⇒ decided by score desc ⇒ y (500) before x (300)
  [ "$order" = "y x " ]
}

@test "roadmap_sync_ice: no-ice items sink to the tail behind scored items" {
  mkplan "plan-x.md" "x" "depends_on: []\nice: {impact: 8, confidence: 9, ease: 6}\n" # 432
  mkplan "plan-n.md" "n" "depends_on: []\n" # no ice

  run bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  next_section > "$TMPROOT/next.txt"
  order=$(grep -oE '\[(x|n)\]' "$TMPROOT/next.txt" | tr -d '[]' | tr '\n' ' ')
  [ "$order" = "x n " ]
}

@test "roadmap_sync_ice: equal score tie-breaks by created date ascending" {
  # created for plans = the YYYY-MM-DD prefix in the filename.
  mkplan "2026-02-01_feature_late.md"  "late"  "depends_on: []\nice: {impact: 8, confidence: 10, ease: 5}\n" # 400
  mkplan "2026-01-01_feature_early.md" "early" "depends_on: []\nice: {impact: 10, confidence: 8, ease: 5}\n" # 400

  run bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  next_section > "$TMPROOT/next.txt"
  order=$(grep -oE '\[(early|late)\]' "$TMPROOT/next.txt" | tr -d '[]' | tr '\n' ' ')
  [ "$order" = "early late " ]
}

@test "roadmap_sync_ice: dependency cycle prints the exact literal warning line" {
  mkplan "plan-a.md" "a" "depends_on: [plan-b.md]\nice: {impact: 8, confidence: 9, ease: 6}\n"
  mkplan "plan-b.md" "b" "depends_on: [plan-a.md]\nice: {impact: 8, confidence: 9, ease: 7}\n"

  run --separate-stderr bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  # Exact contract string (not a substring): grammar + first-remaining path.name.
  [[ "$stderr" == *"[warn] dependency cycle while sorting roadmap near plan-a.md; keeping stable order"* ]]
  # And assert the FULL line is present verbatim (no extra tokens spliced in).
  printf '%s\n' "$stderr" | grep -qxF "[warn] dependency cycle while sorting roadmap near plan-a.md; keeping stable order"
}

@test "roadmap_sync_ice: pin-only section (no valid ice anywhere) still enters priority mode" {
  # Through the production boundary: no ice at all — only pins. If mode selection
  # ignored `pin`, the section would fall to legacy file-order (a,b); priority
  # mode reorders by pin↑ (b,a). Guards the shell mode-choice, not just the module.
  mkplan "plan-a.md" "a" "depends_on: []\npin: 2\n"
  mkplan "plan-b.md" "b" "depends_on: []\npin: 1\n"
  run bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  next_section > "$TMPROOT/next.txt"
  order=$(grep -oE '\[(a|b)\]' "$TMPROOT/next.txt" | tr -d '[]' | tr '\n' ' ')
  [ "$order" = "b a " ]
}

@test "roadmap_sync_ice: ice_confirmed never changes order (pair equal but for confirmation)" {
  # Same score; only ice_confirmed differs. Confirmation must NOT reorder — the
  # tie breaks on topic↑ (early<later), even though the CONFIRMED item is the one
  # that would jump ahead if confirmation wrongly influenced ordering.
  mkplan "plan-1.md" "later" "depends_on: []\nice: {impact: 8, confidence: 9, ease: 7}\nice_confirmed: true\n"
  mkplan "plan-2.md" "early" "depends_on: []\nice: {impact: 8, confidence: 9, ease: 7}\nice_confirmed: false\n"
  run --separate-stderr bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  next_section > "$TMPROOT/next.txt"
  order=$(grep -oE '\[(early|later)\]' "$TMPROOT/next.txt" | tr -d '[]' | tr '\n' ' ')
  [ "$order" = "early later " ]
}

# ═══════════════════════════════════════════════════════════════
# ICE grammar degradation — every malformed shape sinks to the tail
# ═══════════════════════════════════════════════════════════════

@test "roadmap_sync_ice: block-style ice warns and degrades to tail" {
  mkplan "plan-x.md" "x" "depends_on: []\nice: {impact: 8, confidence: 9, ease: 6}\n"
  {
    printf '%s\n' '---'
    printf 'topic: bs\n'
    printf 'status: queued\n'
    printf 'parallel_safe: false\n'
    printf 'depends_on: []\n'
    printf 'ice:\n'
    printf '  impact: 8\n'
    printf '  confidence: 9\n'
    printf '  ease: 7\n'
    printf '%s\n' '---'
    printf '# Feature: bs\n'
  } > "$BANK/plans/plan-bs.md"

  run --separate-stderr bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  # exact design-C1 grammar for the block-style ice warning
  [[ "$stderr" == *"ice uses block-style mapping; use flow-style {impact: N, confidence: N, ease: N}"* ]]
  next_section > "$TMPROOT/next.txt"
  order=$(grep -oE '\[(x|bs)\]' "$TMPROOT/next.txt" | tr -d '[]' | tr '\n' ' ')
  [ "$order" = "x bs " ]
}

@test "roadmap_sync_ice: malformed/plain-int/empty/list ice all degrade to tail with a warning" {
  local extra
  for shape in \
    "ice: 432" \
    "ice:" \
    "ice: [8, 9, 7]" \
    "ice: {impact: 8, confidence: 9}" \
    "ice: {impact: 8, confidence: 9, ease: 7, extra: 2}" \
    "ice: {impact: 8, impact: 9, ease: 7}" \
    "ice: {impact: 0, confidence: 9, ease: 7}" \
    "ice: {impact: 11, confidence: 9, ease: 7}" \
    "ice: {impact: 8.5, confidence: 9, ease: 7}" ; do
    rm -f "$BANK/plans"/*.md
    mkplan "plan-good.md" "good" "depends_on: []\nice: {impact: 8, confidence: 9, ease: 6}\n"
    extra="depends_on: []\n${shape}\n"
    mkplan "plan-bad.md" "bad" "$extra"
    run --separate-stderr bash "$SYNC" "$BANK"
    [ "$status" -eq 0 ]
    # every invalid ice emits a mandatory stderr warning naming the bad plan
    [[ "$stderr" == *"plan plans/plan-bad.md: ice"* ]]
    next_section > "$TMPROOT/next.txt"
    order=$(grep -oE '\[(good|bad)\]' "$TMPROOT/next.txt" | tr -d '[]' | tr '\n' ' ')
    [ "$order" = "good bad " ]
  done
}

@test "roadmap_sync_ice: oversized ice component degrades to tail without crashing sync" {
  # 5000-digit component exceeds CPython int_max_str_digits ⇒ must be treated as
  # invalid ice (no-ice tail) + warning, NOT crash roadmap-sync (C1).
  local big; big=$(printf '5%.0s' {1..5000})
  mkplan "plan-good.md" "good" "depends_on: []\nice: {impact: 8, confidence: 9, ease: 6}\n"
  mkplan "plan-big.md" "big" "depends_on: []\nice: {impact: $big, confidence: 9, ease: 7}\n"
  run --separate-stderr bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"plan plans/plan-big.md: ice"* ]]
  next_section > "$TMPROOT/next.txt"
  order=$(grep -oE '\[(good|big)\]' "$TMPROOT/next.txt" | tr -d '[]' | tr '\n' ' ')
  [ "$order" = "good big " ]
}

@test "roadmap_sync_ice: oversized pin is treated as invalid without crashing sync" {
  local big; big=$(printf '5%.0s' {1..5000})
  mkplan "plan-x.md" "x" "depends_on: []\nice: {impact: 8, confidence: 9, ease: 6}\n"
  mkplan "plan-p.md" "p" "depends_on: []\npin: $big\n"
  run bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  # oversized pin invalid ⇒ p has neither valid ice nor pin ⇒ sinks to no-ice tail
  next_section > "$TMPROOT/next.txt"
  order=$(grep -oE '\[(x|p)\]' "$TMPROOT/next.txt" | tr -d '[]' | tr '\n' ' ')
  [ "$order" = "x p " ]
}

@test "roadmap_sync_ice: priority mode leaves content outside the fence byte-identical" {
  mkplan "plan-x.md" "x" "depends_on: []\nice: {impact: 8, confidence: 9, ease: 6}\n"
  mkplan "plan-y.md" "y" "depends_on: []\nice: {impact: 8, confidence: 9, ease: 7}\n"
  head_before=$(awk '/<!-- mb-roadmap-auto -->/{exit} {print}' "$BANK/roadmap.md")
  tail_before=$(awk 'f{print} /<!-- \/mb-roadmap-auto -->/{f=1}' "$BANK/roadmap.md")
  bash "$SYNC" "$BANK" >/dev/null
  head_after=$(awk '/<!-- mb-roadmap-auto -->/{exit} {print}' "$BANK/roadmap.md")
  tail_after=$(awk 'f{print} /<!-- \/mb-roadmap-auto -->/{f=1}' "$BANK/roadmap.md")
  [ "$head_before" = "$head_after" ]
  [ "$tail_before" = "$tail_after" ]
}

@test "roadmap_sync_ice: evil topics/titles (pipes, brackets, quotes) do not break priority ordering" {
  mkplan "plan-1.md" 'a|b' "depends_on: []\nice: {impact: 8, confidence: 9, ease: 6}\n"
  mkplan "plan-2.md" 'c[d]"e"' "depends_on: []\nice: {impact: 8, confidence: 9, ease: 7}\n"
  run bash "$SYNC" "$BANK"
  [ "$status" -eq 0 ]
  grep -qF 'a|b' "$BANK/roadmap.md"
  grep -qF 'c[d]"e"' "$BANK/roadmap.md"
}

# ═══════════════════════════════════════════════════════════════
# Portability
# ═══════════════════════════════════════════════════════════════

@test "roadmap_sync_ice: works when the bank path contains spaces" {
  SPACED="$TMPROOT/with space/.memory-bank"
  mkdir -p "$SPACED/plans"
  cat > "$SPACED/roadmap.md" <<'EOF'
# Roadmap

<!-- mb-roadmap-auto -->
<!-- /mb-roadmap-auto -->
EOF
  {
    printf '%s\n' '---'
    printf 'topic: s\nstatus: queued\nparallel_safe: false\ndepends_on: []\n'
    printf 'ice: {impact: 8, confidence: 9, ease: 6}\n'
    printf '%s\n' '---'
    printf '# Feature: s\n'
  } > "$SPACED/plans/plan-s.md"
  run bash "$SYNC" "$SPACED"
  [ "$status" -eq 0 ]
}
