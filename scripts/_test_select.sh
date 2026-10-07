#!/usr/bin/env bash
# _test_select.sh — targeted test selection for mb-test-run.sh.
#
# Sourced, functions only. Reads the caller's globals DIR, CHANGED_SINCE,
# FILES_ARG; select_tests sets SELECTION, SELECT_REASON and the
# per-stack arrays SEL_BATS / SEL_PY / SEL_GO.
#
# A changed file maps to: itself when it is a test; tests by naming convention
# (foo.py -> test_foo*.py / foo_test.py, x.sh -> test_x*.bats, x.go -> its
# package dir); tests from a fresh code graph (mb-graph-query.py tests --file).

# shellcheck disable=SC2034  # SELECTION / SELECT_REASON / SEL_* are read by the caller
_TEST_SELECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Test stacks present in DIR, in run order. One candidate runs as before; with
# several, python/go join only when they have test files (mixed repos run all).
detect_test_stacks() {
  local -a cands=()
  local has_py=0 has_go=0
  [[ -n "$(find_bats_files)" ]] && cands+=(bats)
  if [[ "$STACK" == "python" ]]; then has_py=1; fi
  if [[ "$STACK" == "go" ]]; then has_go=1; fi
  if [[ "$STACK" == "multi" ]]; then
    if [[ -f "$DIR/pyproject.toml" || -f "$DIR/requirements.txt" || -f "$DIR/setup.py" ]]; then has_py=1; fi
    if [[ -f "$DIR/go.mod" ]]; then has_go=1; fi
  fi
  (( has_py )) && cands+=(python)
  (( has_go )) && cands+=(go)
  if (( ${#cands[@]} > 1 )); then
    local c
    for c in "${cands[@]}"; do
      case "$c" in
        python) [[ -n "$(find_named_tests 'test_*.py')$(find_named_tests '*_test.py')" ]] || continue ;;
        go) [[ -n "$(find_named_tests '*_test.go')" ]] || continue ;;
      esac
      printf '%s\n' "$c"
    done
  elif (( ${#cands[@]} == 1 )); then
    printf '%s\n' "${cands[0]}"
  fi
}

# Changed paths relative to DIR, one per line. Returns 1 on an invalid ref.
list_changed_files() {
  local f dir_abs
  dir_abs="$(cd "$DIR" 2>/dev/null && pwd -P || printf '%s' "$DIR")"
  if [[ -n "$CHANGED_SINCE" ]]; then
    git -C "$DIR" rev-parse --verify --quiet "${CHANGED_SINCE}^{commit}" >/dev/null 2>&1 || return 1
    git -C "$DIR" diff --name-only --relative "$CHANGED_SINCE" -- 2>/dev/null || return 1
    git -C "$DIR" ls-files --others --exclude-standard 2>/dev/null || true
  fi
  if [[ -n "$FILES_ARG" ]]; then
    printf '%s\n' "$FILES_ARG" | tr ',' '\n' | while IFS= read -r f; do
      f="${f#./}"
      f="${f#"$dir_abs"/}"
      [ -n "$f" ] && printf '%s\n' "$f"
    done
  fi
  return 0
}

# Shared test infrastructure: a change here can affect any test.
is_test_infra() {
  case "$1" in
    tests/lib/*|tests/*/lib/*|*/tests/lib/*|*/tests/*/lib/*) return 0 ;;
    tests/*helpers*|*/tests/*helpers*) return 0 ;;
  esac
  case "${1##*/}" in
    conftest.py|pytest.ini|pyproject.toml|setup.cfg|setup.py|tox.ini) return 0 ;;
    requirements*.txt|poetry.lock|uv.lock|Pipfile|Pipfile.lock) return 0 ;;
    package.json|package-lock.json|yarn.lock|pnpm-lock.yaml|go.mod|go.sum) return 0 ;;
  esac
  return 1
}

is_runnable_test() {
  case "${1##*/}" in
    test_*.py|*_test.py|*.bats|*_test.go) return 0 ;;
  esac
  return 1
}

# find(1) over DIR for test files named like $1 (glob), vendored dirs pruned.
find_named_tests() {
  local f
  find "$DIR" \( -name .git -o -name .venv -o -name venv -o -name node_modules \
    -o -name .memory-bank -o -name fixtures \) -prune -o -type f -name "$1" -print 2>/dev/null |
    while IFS= read -r f; do printf '%s\n' "${f#"$DIR"/}"; done
}

# Candidate tests for one changed path (relative to DIR), one per line.
# $2 = 1 when the code graph is fresh.
map_changed_file() {
  local path="$1" graph_fresh="$2" base stem s dir
  if is_runnable_test "$path"; then
    [ -f "$DIR/$path" ] && printf '%s\n' "$path"
    return 0
  fi
  base="${path##*/}"
  stem="${base%.*}"
  for s in "$stem" "${stem//-/_}"; do
    case "$base" in
      *.py) find_named_tests "test_${s}*.py"; find_named_tests "${s}_test.py" ;;
      *.sh|*.bash) find_named_tests "test_${s}*.bats" ;;
    esac
  done
  case "$base" in
    *.go)
      dir="$(dirname "$path")"
      if compgen -G "$DIR/$dir/*_test.go" >/dev/null; then printf '%s\n' "$dir"; fi
      ;;
  esac
  if [[ "$graph_fresh" == "1" ]]; then
    python3 "$_TEST_SELECT_DIR/mb-graph-query.py" tests --graph "$DIR/.memory-bank/codebase/graph.json" \
      --file "$path" --json 2>/dev/null |
      python3 -c 'import json,sys
try: print("\n".join(json.load(sys.stdin).get("test_files") or []))
except ValueError: pass' 2>/dev/null |
      while IFS= read -r s; do
        is_runnable_test "$s" && [ -f "$DIR/$s" ] && printf '%s\n' "$s"
      done
  fi
  return 0
}

# select_tests <stacks> — fill SEL_BATS / SEL_PY / SEL_GO from the changed
# files, keeping only stacks listed in <stacks> (output of detect_test_stacks).
# SELECTION=targeted when any array is non-empty; otherwise SELECTION=full and
# SELECT_REASON says why (the caller then runs the full suite).
select_tests() {
  local stacks="$1" changed f candidates graph="$DIR/.memory-bank/codebase/graph.json" fresh=0
  SELECTION="full"
  SEL_BATS=(); SEL_PY=(); SEL_GO=()
  if ! changed="$(list_changed_files)"; then
    SELECT_REASON="invalid ref: $CHANGED_SINCE"
    return 0
  fi
  changed="$(printf '%s\n' "$changed" | sed '/^$/d' | sort -u)"
  if [[ -z "$changed" ]]; then
    SELECT_REASON="no changed files"
    return 0
  fi
  while IFS= read -r f; do
    if is_test_infra "$f"; then
      SELECT_REASON="shared test infrastructure changed: $f"
      return 0
    fi
  done <<< "$changed"
  if [[ -f "$graph" ]] && python3 "$_TEST_SELECT_DIR/mb-graph-query.py" status --graph "$graph" \
      --src-root "$DIR" --json 2>/dev/null | grep -q '"stale": false'; then
    fresh=1
  fi
  candidates="$(while IFS= read -r f; do map_changed_file "$f" "$fresh"; done <<< "$changed" | sort -u)"
  while IFS= read -r f; do
    case "$f" in
      "") ;;
      *.bats) if [[ "$stacks" == *bats* ]]; then SEL_BATS+=("$f"); fi ;;
      *.py) if [[ "$stacks" == *python* ]]; then SEL_PY+=("$f"); fi ;;
      *) if [[ "$stacks" == *go* && -d "$DIR/$f" ]]; then SEL_GO+=("./$f"); fi ;;
    esac
  done <<< "$candidates"
  if (( ${#SEL_BATS[@]} + ${#SEL_PY[@]} + ${#SEL_GO[@]} == 0 )); then
    SELECT_REASON="no tests mapped to changed files"
    return 0
  fi
  SELECTION="targeted"
}
