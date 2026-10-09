#!/usr/bin/env bats
# The portable LLM boundary preserves byte input and releases its timer.
setup() {
  LIB="$BATS_TEST_DIRNAME/../lib/session-common.sh"
  TMP="$(mktemp -d)"
}
teardown() { rm -rf "$TMP"; }

@test "bounded command receives the exact piped stdin bytes" {
  printf 'SENTINEL\000tail\n\n' > "$TMP/input"
  run bash -c '. "$1"; cat "$2/input" | sc_run_bounded 2 cat > "$2/output"; cmp "$2/input" "$2/output"' _ "$LIB" "$TMP"
  [ "$status" -eq 0 ]
}

@test "bounded command preserves output and a nonzero command exit" {
  run bash -c '. "$1"; sc_run_bounded 2 bash -c '\''printf partial; exit 23'\''' _ "$LIB"
  [ "$status" -eq 23 ]
  [ "$output" = partial ]
}

@test "bounded command times out with exit 124" {
  run bash -c '. "$1"; sc_run_bounded 0.1 bash -c '\''while :; do :; done'\''' _ "$LIB"
  [ "$status" -eq 124 ]
}

@test "completed command stops and reaps its watchdog timer" {
  mkdir "$TMP/bin"
  cat > "$TMP/bin/sleep" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$$" > "$MB_TEST_SLEEP_PID"
exec /bin/sleep "$@"
EOF
  chmod +x "$TMP/bin/sleep"
  run env PATH="$TMP/bin:$PATH" MB_TEST_SLEEP_PID="$TMP/timer" bash -c '
    . "$1"
    sc_run_bounded 2 bash -c '\''while [ ! -f "$MB_TEST_SLEEP_PID" ]; do :; done; printf ready'\''
    pid="$(cat "$MB_TEST_SLEEP_PID")"
    if kill -0 "$pid" 2>/dev/null; then exit 1; fi
  ' _ "$LIB"
  [ "$status" -eq 0 ]
  [ "$output" = ready ]
}
