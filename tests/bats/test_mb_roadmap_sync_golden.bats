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

# Apply the finding-2 slug normalization (strip a `specs/` prefix, keep the
# first path component, drop the resulting duplicates) to the `## Linked Specs
# (active)` rows of a frozen golden. Only that section is touched; every other
# byte passes through unchanged.
normalize_linked_specs() {
  awk '
    /^## Linked Specs \(active\)$/ { inls = 1; print; next }
    /^(## |<!-- )/               { inls = 0; delete seen }
    {
      if (inls && $0 ~ /^- /) {
        slug = substr($0, 3)
        sub(/^specs\//, "", slug)
        sub(/\/.*$/, "", slug)
        if (slug in seen) next
        seen[slug] = 1
        print "- " slug
        next
      }
      print
    }
  ' "$1"
}

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
  # The golden froze the pre-S4 Linked Specs rows VERBATIM, i.e. one row per raw
  # linked_specs spelling (`foo`, `specs/foo`, `specs/foo/design.md`). Finding 2
  # made the script normalize every spelling to its topic slug and dedupe them,
  # because only the bare slug ever resolved to a real tasks.md. Applying the
  # same normalization to the golden keeps this fixture doing the one job it
  # exists for — proving the ORDERING is unchanged — instead of re-freezing the
  # defect it happened to capture.
  normalize_linked_specs "$golden/roadmap.md" > "$TMPROOT/golden.normalized"
  diff "$TMPROOT/golden.normalized" "$TMPROOT/roadmap.stripped"
  # Same reason as above: the frozen `specs=<N>` counted raw linked_specs
  # entries, and normalization dedupes the spellings of one spec into one row.
  # Diff every other field verbatim, then assert the count is self-consistent
  # with the rows actually rendered (a stronger check than the frozen number).
  sed -E 's/ specs=[0-9]+$//' "$golden/stdout" > "$TMPROOT/golden.stdout.n"
  sed -E 's/ specs=[0-9]+$//' "$TMPROOT/o" > "$TMPROOT/o.n"
  diff "$TMPROOT/golden.stdout.n" "$TMPROOT/o.n"
  local reported rendered
  reported=$(sed -E 's/.* specs=([0-9]+)$/\1/' "$TMPROOT/o")
  rendered=$(awk '/^## Linked Specs \(active\)$/{f=1;next} /^(## |<!-- )/{f=0} f && /^- /{n++} END{print n+0}' "$bank/roadmap.md")
  [ "$reported" = "$rendered" ]
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
# Frozen-golden parity across roadmap fence styles
# ═══════════════════════════════════════════════════════════════

@test "roadmap_sync_ice: full corpus byte-identical to the frozen legacy golden (one fence)" {
  compare_style_vs_golden one
}

@test "roadmap_sync_ice: byte-identical to the frozen legacy golden when the fence is missing (injected)" {
  compare_style_vs_golden none
}

@test "roadmap_sync_ice: multiple fence pairs are now REJECTED (exit 2, nothing written)" {
  # Superseded contract (S4 review finding 6). The pre-S4 script regenerated the
  # FIRST pair and silently ignored the rest, so a stray or duplicated marker
  # left the roadmap half-generated while `--check` still reported "up to date".
  # An ambiguous fence makes generated bytes indistinguishable from hand-written
  # ones, so the file is now refused untouched. The frozen `golden/multi/`
  # fixture is retained as the pre-S4 record of the old behaviour.
  local corpus="$TMPROOT/corpus-multi"
  mkdir -p "$corpus/plans"
  cp "$FIX/corpus/plans/"*.md "$corpus/plans/"
  cp "$FIX/roadmap/multi.md" "$corpus/roadmap.md"
  local bank="$TMPROOT/multi/.memory-bank"
  mkdir -p "$bank/plans"
  cp "$corpus/plans/"*.md "$bank/plans/"
  cp "$corpus/roadmap.md" "$bank/roadmap.md"
  before="$(cat "$bank/roadmap.md")"

  run --separate-stderr bash "$SYNC" "$bank"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"code=malformed_fence"* ]]
  [ "$before" = "$(cat "$bank/roadmap.md")" ]
}

@test "roadmap_sync_ice: full 18-plan HEAD corpus byte-identical to the frozen legacy golden" {
  compare_candidate_vs_golden "$FIX/real_corpus" "$FIX/real_corpus/golden"
}
