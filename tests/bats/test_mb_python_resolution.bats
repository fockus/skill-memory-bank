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

@test "invariant: scripts/mb-progress-chain.sh has no bare python3 outside \${MB_PYTHON:-python3}" {
  run _assert_no_bare_python3 "$REPO_ROOT/scripts/mb-progress-chain.sh"
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

# ═══ Wheel installs (pipx / uv tool / pip into a venv) — scripts run directly ═══
# The bundle is shared-data at <prefix>/share/memory-bank-skill while the
# package lives in <prefix>'s site-packages. Agents run the scripts directly
# (no CLI, so no MB_PYTHON); a bare python3 cannot import memory_bank_skill.

# Build <prefix>/share/memory-bank-skill/scripts (copies of the named scripts,
# no memory_bank_skill package next to them) plus a <prefix>/bin/python3 that
# only records its argv — enough to prove which interpreter was chosen.
_make_wheel_layout() {
  local prefix="$TMPDIR/prefix" f
  mkdir -p "$prefix/share/memory-bank-skill/scripts" "$prefix/bin"
  for f in "$@"; do cp "$REPO_ROOT/scripts/$f" "$prefix/share/memory-bank-skill/scripts/"; done
  cat > "$prefix/bin/python3" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$TMPDIR/wheel-python.argv"
EOF
  chmod +x "$prefix/bin/python3"
  printf '%s' "$prefix"
}

@test "mb_resolve_python: MB_PYTHON wins over the wheel interpreter" {
  local prefix
  prefix="$(_make_wheel_layout)"
  run env MB_PYTHON=/custom/python bash -c "
    source '$LIB'
    mb_resolve_python '$prefix/share/memory-bank-skill'
  "
  [ "$status" -eq 0 ]
  [ "$output" = "/custom/python" ]
}

@test "mb_resolve_python: wheel layout resolves to <prefix>/bin/python3, also via a symlinked bundle" {
  local prefix
  prefix="$(_make_wheel_layout)"
  ln -s "$prefix/share/memory-bank-skill" "$TMPDIR/skill-link"
  run env -u MB_PYTHON bash -c "source '$LIB'; mb_resolve_python '$prefix/share/memory-bank-skill'"
  [ "$status" -eq 0 ]
  [ "$output" = "$(cd "$prefix" && pwd -P)/bin/python3" ]
  run env -u MB_PYTHON bash -c "source '$LIB'; mb_resolve_python '$TMPDIR/skill-link'"
  [ "$status" -eq 0 ]
  [ "$output" = "$(cd "$prefix" && pwd -P)/bin/python3" ]
}

@test "mb_resolve_python: source checkout and wheel layout without bin/python3 fall back to python3" {
  local prefix
  run env -u MB_PYTHON bash -c "source '$LIB'; mb_resolve_python '$REPO_ROOT'"
  [ "$status" -eq 0 ]
  [ "$output" = "python3" ]
  prefix="$(_make_wheel_layout)"
  rm "$prefix/bin/python3"
  run env -u MB_PYTHON bash -c "source '$LIB'; mb_resolve_python '$prefix/share/memory-bank-skill'"
  [ "$status" -eq 0 ]
  [ "$output" = "python3" ]
}

@test "mb-progress-chain.sh run directly from a wheel layout uses <prefix>/bin/python3" {
  local prefix bank="$TMPDIR/bank"
  prefix="$(_make_wheel_layout _lib.sh mb-progress-chain.sh)"
  mkdir -p "$bank" && printf '# Progress\n\n## 2026-01-01\n- entry\n' > "$bank/progress.md"
  run env -u MB_PYTHON bash "$prefix/share/memory-bank-skill/scripts/mb-progress-chain.sh" --verify "$bank"
  [ "$status" -eq 0 ]
  [ -f "$TMPDIR/wheel-python.argv" ]
  [ "$(sed -n '1,3p' "$TMPDIR/wheel-python.argv" | tr '\n' ' ')" = "-m memory_bank_skill.progress_chain --verify " ]
}

@test "mb-index-json.py run with a bare python3 from a wheel layout re-execs under <prefix>/bin/python3" {
  local prefix script
  prefix="$(_make_wheel_layout mb-index-json.py _mb_skill_python.py)"
  script="$(cd "$prefix" && pwd -P)/share/memory-bank-skill/scripts/mb-index-json.py"
  # -I -S: keep any dev-installed memory_bank_skill off sys.path so the
  # interpreter really cannot import the package (the wheel-install case).
  run env -u MB_PYTHON -u _MB_SKILL_PYTHON_REEXEC python3 -I -S "$script" "$TMPDIR/bank"
  [ "$status" -eq 0 ]
  [ -f "$TMPDIR/wheel-python.argv" ]
  [ "$(cat "$TMPDIR/wheel-python.argv")" = "$(printf '%s\n%s' "$script" "$TMPDIR/bank")" ]
}

@test "mb-index-json.py re-execs at most once (no loop), then fails loudly" {
  local prefix
  prefix="$(_make_wheel_layout mb-index-json.py _mb_skill_python.py)"
  run env -u MB_PYTHON _MB_SKILL_PYTHON_REEXEC=1 python3 -I -S \
    "$prefix/share/memory-bank-skill/scripts/mb-index-json.py" "$TMPDIR/bank"
  [ "$status" -ne 0 ]
  [ ! -f "$TMPDIR/wheel-python.argv" ]
  [[ "$output" == *"ModuleNotFoundError"* ]]
}

@test "every Python entry point run with a bare python3 from a wheel layout re-execs via _mb_skill_python.py" {
  local prefix script s
  for s in mb-codegraph.py mb-import.py mb-wiki.py mb-openspec.py mb-graph-query.py mb-code-context.py mb-semantic-search.py; do
    rm -rf "$TMPDIR/prefix" "$TMPDIR/wheel-python.argv"
    prefix="$(_make_wheel_layout "$s" _mb_skill_python.py)"
    script="$(cd "$prefix" && pwd -P)/share/memory-bank-skill/scripts/$s"
    run env -u MB_PYTHON -u _MB_SKILL_PYTHON_REEXEC python3 -I -S "$script" --probe-arg
    [ "$status" -eq 0 ] || { echo "$s: status=$status $output"; return 1; }
    [ "$(cat "$TMPDIR/wheel-python.argv")" = "$(printf '%s\n%s' "$script" --probe-arg)" ] || { echo "$s argv mismatch"; return 1; }
  done
}

@test "shell callers of memory_bank_skill (profile, consolidate) use <prefix>/bin/python3 from a wheel layout" {
  local prefix bank="$TMPDIR/bank"
  prefix="$(_make_wheel_layout _lib.sh mb-profile.sh mb-consolidate.sh)"
  mkdir -p "$bank" && printf '# Progress\n' > "$bank/progress.md"
  run env -u MB_PYTHON bash "$prefix/share/memory-bank-skill/scripts/mb-profile.sh" show
  [ "$(sed -n '1,2p' "$TMPDIR/wheel-python.argv" | tr '\n' ' ')" = "-m memory_bank_skill.rules_profile " ]
  rm -f "$TMPDIR/wheel-python.argv"
  run env -u MB_PYTHON bash "$prefix/share/memory-bank-skill/scripts/mb-consolidate.sh" "$bank"
  [ "$(sed -n '1,2p' "$TMPDIR/wheel-python.argv" | tr '\n' ' ')" = "-m memory_bank_skill.consolidate " ]
}
