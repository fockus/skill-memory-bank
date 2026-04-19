#!/usr/bin/env bats
# Tests for scripts/mb-tags-normalize.sh + kebab-case в mb-index-json.py.
#
# Contract:
#   mb-tags-normalize.sh [--dry-run|--apply] [--auto-merge] [mb_path]
#
# Logic:
#   - Load vocabulary from <mb>/tags-vocabulary.md (one tag per line, bullets OK)
#     ИЛИ default из references/tags-vocabulary.md если банковского нет
#   - Scan notes/*.md frontmatter, collect actual_tags set
#   - Detect synonyms: pairs (a, b) где Levenshtein(a, b) ≤ 2 → propose merge to
#     vocabulary-form (preferred) или shorter
#   - --auto-merge: применяет только high-confidence (distance ≤ 1)
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
  # Должна быть предложенная пара в output
  [[ "$output" == *"sqlite_vec"* ]]
  [[ "$output" == *"sqlite-vec"* ]]
}

@test "normalize: --auto-merge applies distance ≤ 1 merges" {
  write_vocab
  write_note "a.md" "sqlite-vec"
  write_note "b.md" "sqlite_vec"
  run_normalize --apply --auto-merge
  [ "$status" -eq 0 ]
  # b.md должен теперь содержать sqlite-vec (из vocabulary)
  grep -q "sqlite-vec" "$MB/notes/b.md"
  ! grep -q "sqlite_vec" "$MB/notes/b.md"
}

@test "normalize: distance=2 НЕ авто-мержится при --auto-merge" {
  write_vocab
  write_note "a.md" "test"
  write_note "b.md" "teest2"    # distance=2 от test (вставка 'e' + '2')
  run_normalize --apply --auto-merge
  # Unknown tag (no close match) → exit 2 допустимо
  [ "$status" -eq 0 ] || [ "$status" -eq 2 ]
  # teest2 остаётся (distance=2 не auto-merged)
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
  # Нет $MB/tags-vocabulary.md
  write_note "a.md" "auth, bug, test"
  run_normalize --dry-run
  [ "$status" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════════
# --apply mechanics
# ═══════════════════════════════════════════════════════════════

@test "normalize: --apply без --auto-merge НЕ меняет файлы (interactive mode требует stdin)" {
  write_vocab
  write_note "a.md" "sqlite_vec"
  local before
  before=$(cat "$MB/notes/a.md")
  run_normalize --apply
  # Без --auto-merge interactive ↔ в тесте stdin closed → skip
  local after
  after=$(cat "$MB/notes/a.md")
  [ "$before" = "$after" ]
}

@test "normalize: --apply --auto-merge idempotent (2 run подряд)" {
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
# kebab-case в mb-index-json.py
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
