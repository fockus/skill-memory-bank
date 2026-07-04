#!/usr/bin/env bats
# B1 — mb-freshness.sh: deterministic MB-vs-code freshness (behind/dirty), drift-gated Stop
# nudge + SessionStart banner. Always exit 0, fail-safe outside git.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-freshness.sh"
  TMP="$(mktemp -d)"; DIR="$TMP/repo"; MB="$DIR/.memory-bank"
  mkdir -p "$MB/notes" "$DIR/src"
  for c in status roadmap checklist progress; do printf '# %s\n' "$c" > "$MB/$c.md"; done
  git -C "$DIR" init -q
  git -C "$DIR" config user.email t@t.t
  git -C "$DIR" config user.name t
  git -C "$DIR" add -A
  git -C "$DIR" commit -qm "init: bank + skeleton"   # last MB commit == HEAD, clean
}
teardown() { [ -n "${TMP:-}" ] && rm -rf "$TMP"; }

_code_commit() {  # a commit that does NOT touch .memory-bank/
  printf '%s\n' "$2" > "$DIR/src/$1"
  git -C "$DIR" add "src/$1"
  git -C "$DIR" commit -qm "code $1"
}

@test "B1: --porcelain reports commits behind the last bank commit" {
  _code_commit a.py "one"
  _code_commit b.py "two"
  run bash "$SCRIPT" --porcelain "$DIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'behind=2'
}

@test "B1: --porcelain counts dirty + untracked bank changes" {
  printf 'changed\n' >> "$MB/status.md"          # tracked, modified
  printf 'new note\n' > "$MB/notes/fresh.md"      # untracked
  run bash "$SCRIPT" --porcelain "$DIR"
  [ "$status" -eq 0 ]
  dirty="$(echo "$output" | sed -n 's/.*dirty=//p')"
  [ "$dirty" -ge 2 ]
}

@test "B1: --stop-nudge is silent when the bank is fresh" {
  run bash "$SCRIPT" --stop-nudge "$DIR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "B1: --stop-nudge fires over threshold with the number + remediation command" {
  _code_commit a.py "one"
  _code_commit b.py "two"
  run env MB_DRIFT_WARN_COMMITS=1 bash "$SCRIPT" --stop-nudge "$DIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '2'
  echo "$output" | grep -q 'mb-auto-commit.sh --force'
}

@test "B1: --banner is empty when fresh, populated over threshold" {
  run bash "$SCRIPT" --banner "$DIR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  _code_commit a.py "one"
  run env MB_DRIFT_WARN_COMMITS=1 bash "$SCRIPT" --banner "$DIR"
  echo "$output" | grep -q 'Memory Bank freshness'
}

@test "B1: fail-safe outside a git repo → exit 0, no output" {
  nogit="$TMP/nogit"; mkdir -p "$nogit/.memory-bank"
  run bash "$SCRIPT" --porcelain "$nogit"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
