#!/usr/bin/env bats
# mb_resolve_path must not invent a nested bank when run from inside a bank.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  T="$(mktemp -d)"
  BANK="$T/proj/.memory-bank"
  mkdir -p "$BANK/reports/topic"
  : > "$BANK/status.md"
  unset MB_PATH MB_AGENT
}

teardown() { rm -rf "$T"; }

@test "mb-coord append from the bank dir lands in that bank" {
  cd "$BANK"
  run bash "$REPO_ROOT/scripts/mb-coord.sh" append --type STATUS --title "from bank"
  [ "$status" -eq 0 ]
  [ ! -e "$BANK/.memory-bank" ]
  grep -q "from bank" "$BANK/COORDINATION.md"
}

@test "mb-coord append from a bank subdir lands in that bank" {
  cd "$BANK/reports/topic"
  run bash "$REPO_ROOT/scripts/mb-coord.sh" append --type STATUS --title "from subdir"
  [ "$status" -eq 0 ]
  [ ! -e "$BANK/reports/topic/.memory-bank" ]
  [ ! -e "$BANK/.memory-bank" ]
  grep -q "from subdir" "$BANK/COORDINATION.md"
}

@test "mb-work-progress-append from the bank dir does not nest a bank" {
  cd "$BANK"
  run bash "$REPO_ROOT/scripts/mb-work-progress-append.sh" --text "nested probe"
  [ "$status" -eq 0 ]
  [ ! -e "$BANK/.memory-bank" ]
  grep -q "nested probe" "$BANK/progress.md"
}

@test "ordinary project dir still resolves relative .memory-bank" {
  mkdir -p "$T/proj/src"
  cd "$T/proj/src"
  run bash -c "source '$REPO_ROOT/scripts/_lib.sh'; mb_resolve_path"
  [ "$output" = ".memory-bank" ]
}
