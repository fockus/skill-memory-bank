#!/usr/bin/env bats
# A6 — mb-drift.sh terminology check must flag Cyrillic decomposition MARKERS
# (headings / table headers) but NOT incidental Russian prose or declined nouns.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-drift.sh"
  TMP="$(mktemp -d)"; DIR="$TMP"; MB="$DIR/.memory-bank"
  mkdir -p "$MB/plans/done"
  for c in status roadmap checklist research backlog progress lessons; do
    printf '# %s\n' "$c" > "$MB/$c.md"
  done
}
teardown() { [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"; }

@test "prose Cyrillic nouns / declensions → terminology ok" {
  printf -- '---\nstatus: queued\n---\n# Plan\n\nКаждый этап ≤5 мин. Эта фаза создаёт модуль; этапы атомарны.\n' > "$MB/plans/p.md"
  run bash "$SCRIPT" "$DIR"
  echo "$output" | grep -q 'drift_check_terminology=ok'
}

@test "Cyrillic decomposition heading → terminology warn" {
  printf -- '---\nstatus: queued\n---\n## Этап 1: сделать\n' > "$MB/plans/p.md"
  run bash "$SCRIPT" "$DIR"
  echo "$output" | grep -q 'drift_check_terminology=warn'
}

@test "Cyrillic table header → terminology warn" {
  printf -- '---\nstatus: queued\n---\n# Plan\n\n| Фаза | Задачи |\n|---|---|\n| a | b |\n' > "$MB/plans/p.md"
  run bash "$SCRIPT" "$DIR"
  echo "$output" | grep -q 'drift_check_terminology=warn'
}

@test "English heading with incidental Cyrillic prose → terminology ok" {
  printf -- '---\nstatus: queued\n---\n## Stage 1: do it\n\nКаждый этап атомарен.\n' > "$MB/plans/p.md"
  run bash "$SCRIPT" "$DIR"
  echo "$output" | grep -q 'drift_check_terminology=ok'
}
