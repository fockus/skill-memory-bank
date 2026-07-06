#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  # shellcheck source=/dev/null
  source "$REPO_ROOT/scripts/_lib.sh"
  PROJECT="$(mktemp -d)"
  TESTFILE="$PROJECT/sample.txt"
  printf 'x\n' > "$TESTFILE"
}

teardown() {
  [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && rm -rf "$PROJECT"
}

@test "mb_mtime: existing file returns numeric epoch > 0" {
  run mb_mtime "$TESTFILE"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+$ ]]
  [ "$output" -gt 0 ]
}

@test "mb_mtime: missing file returns 0" {
  run mb_mtime "$PROJECT/no-such-file"
  [ "$status" -eq 0 ]
  [ "$output" -eq 0 ]
}

_make_gnu_stat_shim() {
  local shimdir="$PROJECT/gnu-shim"
  mkdir -p "$shimdir"
  cat > "$shimdir/stat" <<'SHIM'
#!/usr/bin/env bash
if [ "${1:-}" = "-f" ] && [ "${2:-}" = "%m" ]; then
  printf '?\n'
  exit 0
fi
if [ "${1:-}" = "-c" ] && [ "${2:-}" = "%Y" ]; then
  python3 -c 'import os,sys; print(int(os.path.getmtime(sys.argv[1])))' "${3:-}"
  exit $?
fi
exit 1
SHIM
  chmod +x "$shimdir/stat"
  printf '%s' "$shimdir"
}

_make_bsd_stat_shim() {
  local shimdir="$PROJECT/bsd-shim"
  mkdir -p "$shimdir"
  cat > "$shimdir/stat" <<'SHIM'
#!/usr/bin/env bash
if [ "${1:-}" = "-c" ] && [ "${2:-}" = "%Y" ]; then
  exit 1
fi
if [ "${1:-}" = "-f" ] && [ "${2:-}" = "%m" ]; then
  python3 -c 'import os,sys; print(int(os.path.getmtime(sys.argv[1])))' "${3:-}"
  exit $?
fi
exit 1
SHIM
  chmod +x "$shimdir/stat"
  printf '%s' "$shimdir"
}

@test "mb_mtime: GNU stat shim (-f non-numeric) still returns epoch via -c %Y" {
  local shim
  shim="$(_make_gnu_stat_shim)"
  run env PATH="$shim:$PATH" bash -c "source '$REPO_ROOT/scripts/_lib.sh'; mb_mtime '$TESTFILE'"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+$ ]]
  [ "$output" -gt 0 ]
}

@test "mb_mtime: BSD stat shim (-c unsupported) returns epoch via -f %m" {
  local shim
  shim="$(_make_bsd_stat_shim)"
  run env PATH="$shim:$PATH" bash -c "source '$REPO_ROOT/scripts/_lib.sh'; mb_mtime '$TESTFILE'"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+$ ]]
  [ "$output" -gt 0 ]
}

@test "mb_mtime: handoff lock TTL survives GNU stat shim (no arithmetic error)" {
  local shim mb handoff lock
  shim="$(_make_gnu_stat_shim)"
  mb="$PROJECT/.memory-bank"
  handoff="$REPO_ROOT/scripts/mb-handoff.sh"
  mkdir -p "$mb/handoff"
  printf '# p\n' > "$mb/progress.md"
  lock="$mb/handoff/.lock"
  mkdir -p "$lock"
  touch -t 202001010000 "$lock"
  run env PATH="$shim:$PATH" MB_HANDOFF_LOCK_TTL=1 bash "$handoff" --actualize "$mb" 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" != *"integer expression expected"* ]]
}
