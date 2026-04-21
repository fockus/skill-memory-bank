#!/usr/bin/env bats
# Tests for scripts/mb-tags-normalize.sh + kebab-case in mb-index-json.py.
#
# Contract:
#   mb-tags-normalize.sh [--dry-run|--apply] [--auto-merge] [mb_path]
#
# Logic:
#   - Load vocabulary from <mb>/tags-vocabulary.md (one tag per line, bullets OK)
#     OR default from references/tags-vocabulary.md if the bank one is absent
#   - Scan notes/*.md frontmatter, collect actual_tags set
#   - Detect synonyms: pairs (a, b) where Levenshtein(a, b) ≤ 2 → propose merge to
#     vocabulary-form (preferred) or shorter
#   - --auto-merge: applies only high-confidence merges (distance ≤ 1)
#   - --apply (default: --dry-run): rewrite frontmatter tags in affected files
#
# Exit: 0 success, 1 error, 2 unknown tags detected (drift signal).

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  NORMALIZE="$REPO_ROOT/scripts/mb-tags-normalize.sh"
  INDEX_PY="$REPO_ROOT/scripts/mb-index-json.py"

  PROJECT="$(mktemp -d)"
  MB="$PROJECT/.memory-bank"
  mkdir -p "$MB/notes"
  : > "$MB/STATUS.md"
}

teardown() {
  [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && rm -rf "$PROJECT"
}

run_normalize() {
  local raw
  raw=$(cd "$PROJECT" && bash "$NORMALIZE" "$@" 2>&1; printf '\n__EXIT__%s' "$?")
  status="${raw##*__EXIT__}"
  output="${raw%$'\n'__EXIT__*}"
}

write_vocab() {
  cat > "$MB/tags-vocabulary.md" <<EOF
# Tags vocabulary

- auth
- bug
- perf
- arch
- test
- refactor
- doc
- security
- sqlite-vec
EOF
}

write_note() {
  local name="$1" tags="$2"
  cat > "$MB/notes/$name" <<EOF
---
type: note
tags: [$tags]
importance: medium
---

Body of $name.
EOF
}

# ═══════════════════════════════════════════════════════════════
# Basic contract
# ═══════════════════════════════════════════════════════════════

@test "normalize: empty bank → no-op exit 0" {
  run_normalize --dry-run
  [ "$status" -eq 0 ]
}

@test "normalize: default --dry-run (no args) — 0 file changes" {
  write_vocab
  write_note "n1.md" "auth, bug"
  local before
  before=$(cat "$MB/notes/n1.md")
  run_normalize
  [ "$status" -eq 0 ]
  local after
  after=$(cat "$MB/notes/n1.md")
  [ "$before" = "$after" ]
}

# ═══════════════════════════════════════════════════════════════
# Levenshtein synonym detection
# ═══════════════════════════════════════════════════════════════

@test "normalize: detects synonym pair sqlite-vec vs sqlite_vec (distance=1)" {
  write_vocab
  write_note "a.md" "sqlite-vec"
  write_note "b.md" "sqlite_vec"
  run_normalize --dry-run
  [ "$status" -eq 0 ]
  # The suggested pair must appear in output
  [[ "$output" == *"sqlite_vec"* ]]
  [[ "$output" == *"sqlite-vec"* ]]
}

@test "normalize: --auto-merge applies distance ≤ 1 merges" {
  write_vocab
  write_note "a.md" "sqlite-vec"
  write_note "b.md" "sqlite_vec"
  run_normalize --apply --auto-merge
  [ "$status" -eq 0 ]
  # b.md must now contain sqlite-vec (from vocabulary)
  grep -q "sqlite-vec" "$MB/notes/b.md"
  ! grep -q "sqlite_vec" "$MB/notes/b.md"
}

@test "normalize: distance=2 is NOT auto-merged with --auto-merge" {
  write_vocab
  write_note "a.md" "test"
  write_note "b.md" "teest2"    # distance=2 from test (inserted 'e' + '2')
  run_normalize --apply --auto-merge
  # Unknown tag (no close match) → exit 2 is acceptable
  [ "$status" -eq 0 ] || [ "$status" -eq 2 ]
  # teest2 remains (distance=2 is not auto-merged)
  grep -q "teest2" "$MB/notes/b.md"
}

# ═══════════════════════════════════════════════════════════════
# Unknown tag detection
# ═══════════════════════════════════════════════════════════════

@test "normalize: unknown tag (not in vocab, no synonym) → warning" {
  write_vocab
  write_note "a.md" "completely-random-tag-xyz"
  run_normalize --dry-run
  # Unknown → non-zero exit (drift signal)
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown"* ]] || [[ "$output" == *"not in vocabulary"* ]]
  [[ "$output" == *"completely-random-tag-xyz"* ]]
}

@test "normalize: known vocabulary tag → no warning" {
  write_vocab
  write_note "a.md" "auth, bug"
  run_normalize --dry-run
  [ "$status" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════════
# Vocabulary loading
# ═══════════════════════════════════════════════════════════════

@test "normalize: uses .memory-bank/tags-vocabulary.md if present" {
  write_vocab
  write_note "a.md" "auth"
  run_normalize --dry-run
  [ "$status" -eq 0 ]
}

@test "normalize: falls back to default vocabulary if bank's is missing" {
  # No $MB/tags-vocabulary.md
  write_note "a.md" "auth, bug, test"
  run_normalize --dry-run
  [ "$status" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════════
# --apply mechanics
# ═══════════════════════════════════════════════════════════════

@test "normalize: --apply without --auto-merge does NOT change files (interactive mode needs stdin)" {
  write_vocab
  write_note "a.md" "sqlite_vec"
  local before
  before=$(cat "$MB/notes/a.md")
  run_normalize --apply
  # Without --auto-merge it is interactive; in tests stdin is closed → skip
  local after
  after=$(cat "$MB/notes/a.md")
  [ "$before" = "$after" ]
}

@test "normalize: --apply --auto-merge is idempotent (2 consecutive runs)" {
  write_vocab
  write_note "a.md" "sqlite_vec"
  run_normalize --apply --auto-merge
  local after_first
  after_first=$(cat "$MB/notes/a.md")
  run_normalize --apply --auto-merge
  local after_second
  after_second=$(cat "$MB/notes/a.md")
  [ "$after_first" = "$after_second" ]
}

# ═══════════════════════════════════════════════════════════════
# kebab-case in mb-index-json.py
# ═══════════════════════════════════════════════════════════════

@test "index-json: camelCase tag → kebab-case in index" {
  mkdir -p "$MB/notes"
  cat > "$MB/notes/n.md" <<EOF
---
type: note
tags: [FooBar, someThing]
---
body
EOF
  python3 "$INDEX_PY" "$MB" >/dev/null 2>&1
  [ -f "$MB/index.json" ]
  local tags_json
  tags_json=$(python3 -c "import json; d=json.load(open('$MB/index.json')); print(json.dumps(d['notes'][0]['tags']))")
  [[ "$tags_json" == *"foo-bar"* ]]
  [[ "$tags_json" == *"some-thing"* ]]
}

@test "index-json: lowercase preserved if already kebab-case" {
  mkdir -p "$MB/notes"
  cat > "$MB/notes/n.md" <<EOF
---
type: note
tags: [my-tag, another-one]
---
body
EOF
  python3 "$INDEX_PY" "$MB" >/dev/null 2>&1
  local tags_json
  tags_json=$(python3 -c "import json; d=json.load(open('$MB/index.json')); print(json.dumps(d['notes'][0]['tags']))")
  [[ "$tags_json" == *"my-tag"* ]]
  [[ "$tags_json" == *"another-one"* ]]
}

@test "index-json: uppercase tag → lowercase" {
  mkdir -p "$MB/notes"
  cat > "$MB/notes/n.md" <<EOF
---
type: note
tags: [AUTH, BUG]
---
body
EOF
  python3 "$INDEX_PY" "$MB" >/dev/null 2>&1
  local tags_json
  tags_json=$(python3 -c "import json; d=json.load(open('$MB/index.json')); print(json.dumps(d['notes'][0]['tags']))")
  [[ "$tags_json" == *"auth"* ]]
  [[ "$tags_json" == *"bug"* ]]
  [[ "$tags_json" != *"AUTH"* ]]
}
