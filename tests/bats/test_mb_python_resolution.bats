#!/usr/bin/env bats
# A19 (CDX-I6): hardcoded `python3` in hot paths breaks pipx/venv installs
# where a bare `python3` either isn't on PATH or resolves to the wrong
# interpreter (not the one that owns the memory_bank_skill package). Every
# hot-path invocation must honor `${MB_PYTHON:-python3}` instead.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="$REPO_ROOT/scripts/_lib.sh"
  INIT_BANK="$REPO_ROOT/scripts/mb-init-bank.sh"
  PI_EXT="$REPO_ROOT/adapters/pi_graph_rag_extension.ts"
  TMPDIR="$(mktemp -d)"

  [ -f "$LIB" ] || skip "scripts/_lib.sh not implemented yet (TDD red)"
  # shellcheck source=/dev/null
  source "$LIB"
}

teardown() {
  [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ] && rm -rf "$TMPDIR"
}

# ═══ Grep invariant — regression guard ═══

# Every line mentioning "python3" in these hot-path files must either be a
# prose comment about the fallback, OR contain "MB_PYTHON" on the same line
# (i.e. the `${MB_PYTHON:-python3}` idiom or an explicit "python3" fallback
# invocation of it) — never a bare, unparameterized `python3` command.
_assert_no_bare_python3() {
  local file="$1" line trimmed
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    trimmed="${line#"${line%%[![:space:]]*}"}"  # lstrip
    case "$trimmed" in
      '#'*) continue ;;                 # prose comment line
    esac
    case "$line" in
      *MB_PYTHON*) continue ;;          # already parameterized (or documents it)
    esac
    echo "bare python3 found in $file: $line" >&2
    return 1
  done < <(grep -n 'python3' "$file" | cut -d: -f2-)
  return 0
}

@test "invariant: scripts/_lib.sh has no bare python3 outside \${MB_PYTHON:-python3}" {
  run _assert_no_bare_python3 "$LIB"
  [ "$status" -eq 0 ]
}

@test "invariant: scripts/mb-init-bank.sh has no bare python3 outside \${MB_PYTHON:-python3}" {
  run _assert_no_bare_python3 "$INIT_BANK"
  [ "$status" -eq 0 ]
}

# ═══ Functional — MB_PYTHON is actually honored, not just grep-shaped ═══

_make_marker_python() {
  local marker="$1" wrapper="$TMPDIR/mb-python-marker.sh"
  cat > "$wrapper" <<EOF
#!/usr/bin/env bash
touch "$marker"
exec python3 "\$@"
EOF
  chmod +x "$wrapper"
  printf '%s' "$wrapper"
}

@test "mb_normalize_path routes through \$MB_PYTHON when set" {
  local marker="$TMPDIR/normalize.used"
  local fake_py
  fake_py="$(_make_marker_python "$marker")"

  run env MB_PYTHON="$fake_py" bash -c "
    source '$LIB'
    mb_normalize_path '$TMPDIR/../$(basename "$TMPDIR")'
  "
  [ "$status" -eq 0 ]
  [ -f "$marker" ]
}

@test "mb_resolve_real_path routes through \$MB_PYTHON when set" {
  local marker="$TMPDIR/realpath.used"
  local fake_py
  fake_py="$(_make_marker_python "$marker")"

  run env MB_PYTHON="$fake_py" bash -c "
    source '$LIB'
    mb_resolve_real_path '$TMPDIR'
  "
  [ "$status" -eq 0 ]
  [ -f "$marker" ]
  # macOS: $TMPDIR itself may be a /tmp -> /private/tmp symlink, so compare
  # against the shell's own realpath resolution rather than the raw string.
  [ "$output" = "$(cd "$TMPDIR" && pwd -P)" ]
}

@test "mb_project_id routes through \$MB_PYTHON when set (sha256 hash step)" {
  local marker="$TMPDIR/project_id.used"
  local fake_py
  fake_py="$(_make_marker_python "$marker")"

  mkdir -p "$TMPDIR/proj"
  run env MB_PYTHON="$fake_py" bash -c "
    source '$LIB'
    mb_project_id '$TMPDIR/proj'
  "
  [ "$status" -eq 0 ]
  [ -f "$marker" ]
}

# ═══ pi_graph_rag_extension.ts — no TS compiler available here; assert the
# source-level contract (env-read with fallback, never a bare hardcoded
# "python3" exec target) instead of executing the extension. ═══

@test "pi_graph_rag_extension.ts reads MB_PYTHON from the environment, not a bare python3" {
  [ -f "$PI_EXT" ]
  grep -q 'process\.env\.MB_PYTHON' "$PI_EXT"
  ! grep -q 'execFileAsync("python3"' "$PI_EXT"
}
