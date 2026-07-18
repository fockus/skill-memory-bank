#!/usr/bin/env bats
# Attribution contract (umbrella sdd-vision-pipeline Task 1, REQ-038):
# README.md and commands/discuss.md must each carry a credits/source block that
# co-locates the mattpocock/skills repo link with its MIT attribution *inside the
# same block* (a bounded line window), not merely somewhere in the file. The
# README block must also credit the Karpathy LLM-wiki gist as the source of the
# future `/mb docs` rules.
#
# Test-name convention: every @test description starts with `attribution: ` — it
# is the Eval red-anchor (`not ok [0-9]+ attribution: `). `bats` on a missing
# file emits `not ok 1 bats-gather-tests` (same exit 1), so an exit-only anchor
# would misread "file absent" as red; the positive named prefix is the only
# ERE-safe signature (no negative lookahead).

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  README="$REPO_ROOT/README.md"
  DISCUSS="$REPO_ROOT/commands/discuss.md"
  MATTPOCOCK='https://github.com/mattpocock/skills'
  # Window (lines each side of the anchor) that still counts as "the same block".
  # Tight enough that the pre-existing README MIT badge (:18) and license line
  # (:704) never fall inside a fresh credits block placed elsewhere.
  WINDOW=5
}

# cooccur_within_window <file> <anchor-ere> <needle-ere> <window>
# Exit 0 iff some line matching <anchor-ere> has a line matching <needle-ere>
# within <window> lines above or below it (inclusive). Deterministic, awk-only.
cooccur_within_window() {
  awk -v anchor="$2" -v needle="$3" -v w="$4" '
    { lines[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) {
        if (lines[i] ~ anchor) {
          lo = i - w; if (lo < 1) lo = 1
          hi = i + w; if (hi > NR) hi = NR
          for (j = lo; j <= hi; j++) {
            if (lines[j] ~ needle) { found = 1 }
          }
        }
      }
      if (found) { exit 0 }
      exit 1
    }
  ' "$1"
}

@test "attribution: README links the mattpocock/skills repo" {
  run grep -F "$MATTPOCOCK" "$README"
  [ "$status" -eq 0 ]
}

@test "attribution: README credits block co-locates the repo link and MIT" {
  run cooccur_within_window "$README" "$MATTPOCOCK" 'MIT' "$WINDOW"
  [ "$status" -eq 0 ]
}

@test "attribution: README credits block mentions the Karpathy LLM-wiki gist" {
  run cooccur_within_window "$README" "$MATTPOCOCK" '[Kk]arpathy' "$WINDOW"
  [ "$status" -eq 0 ]
  run grep -iE 'karpathy.*(wiki|gist)|llm.wiki' "$README"
  [ "$status" -eq 0 ]
}

@test "attribution: commands/discuss.md links the mattpocock/skills source" {
  run grep -F "$MATTPOCOCK" "$DISCUSS"
  [ "$status" -eq 0 ]
}

@test "attribution: commands/discuss.md co-locates the source link and MIT near grilling rules" {
  run cooccur_within_window "$DISCUSS" "$MATTPOCOCK" 'MIT' "$WINDOW"
  [ "$status" -eq 0 ]
}

# ─── Negative half (mandatory): a bare link, or MIT far away, must NOT pass ───

@test "attribution: bare repo link without MIT nearby fails the block check" {
  local f="$BATS_TEST_TMPDIR/bare_link.md"
  printf '# doc\n\nSee %s for patterns.\n\nUnrelated body line.\n' "$MATTPOCOCK" > "$f"
  run cooccur_within_window "$f" "$MATTPOCOCK" 'MIT' "$WINDOW"
  [ "$status" -ne 0 ]
}

@test "attribution: MIT elsewhere in the file (outside the window) fails the block check" {
  local f="$BATS_TEST_TMPDIR/mit_far_away.md"
  {
    printf 'Licensed under MIT.\n'
    for _ in $(seq 1 40); do printf 'filler line\n'; done
    printf 'Credits: %s\n' "$MATTPOCOCK"
    for _ in $(seq 1 40); do printf 'filler line\n'; done
  } > "$f"
  run cooccur_within_window "$f" "$MATTPOCOCK" 'MIT' "$WINDOW"
  [ "$status" -ne 0 ]
}

@test "attribution: a proper credits block (link + MIT + Karpathy in-window) passes" {
  local f="$BATS_TEST_TMPDIR/good_block.md"
  {
    printf '## Credits\n\n'
    printf 'Grilling patterns adapted from %s (MIT).\n' "$MATTPOCOCK"
    printf 'Karpathy LLM-wiki gist informs the future /mb docs rules.\n'
  } > "$f"
  run cooccur_within_window "$f" "$MATTPOCOCK" 'MIT' "$WINDOW"
  [ "$status" -eq 0 ]
  run cooccur_within_window "$f" "$MATTPOCOCK" '[Kk]arpathy' "$WINDOW"
  [ "$status" -eq 0 ]
}
