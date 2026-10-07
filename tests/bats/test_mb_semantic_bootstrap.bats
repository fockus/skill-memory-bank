#!/usr/bin/env bats
# mb-semantic-bootstrap.sh delivers the code-graph extra (tree-sitter + grammars +
# networkx) next to fastembed (plan Stage 10, AGR-053). Existing users already have
# a fastembed venv, so the readiness check must cover every package — otherwise it
# says "ready" and the graph deps never arrive.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  HOOK="$REPO_ROOT/hooks/mb-semantic-bootstrap.sh"
  TMPD="$(mktemp -d)"
  export MB_SEMANTIC_VENV="$TMPD/venv"
  export HAVE="$TMPD/have" PIPLOG="$TMPD/pip.log" WRONG="$TMPD/wrong"
  mkdir -p "$MB_SEMANTIC_VENV/bin"
  : > "$HAVE"
  : > "$WRONG"
  # Fake venv python: hooks/lib/venv_unmet.py prints each requirement whose import
  # name is not in $HAVE or is in $WRONG (installed at a version outside the pin);
  # `-m pip install ...` logs argv and "installs" each requirement as its import
  # name (tree-sitter>=0.21 -> tree_sitter), at the pinned version, unless named
  # in $PIP_FAIL.
  cat > "$MB_SEMANTIC_VENV/bin/python" <<'EOF'
#!/usr/bin/env bash
if [ "${1##*/}" = "venv_unmet.py" ]; then
  shift
  for req in "$@"; do
    m="${req%%[<>=!~]*}"; m="${m//-/_}"
    if ! grep -qx "$m" "$HAVE" || grep -qx "$m" "$WRONG"; then echo "$req"; fi
  done
  exit 0
fi
if [ "$1" = "-c" ]; then
  mods="${2#import }"
  for m in ${mods//,/ }; do grep -qx "$m" "$HAVE" || exit 1; done
  exit 0
fi
if [ "$1" = "-m" ] && [ "$2" = "pip" ]; then
  echo "$*" >> "$PIPLOG"
  shift 3
  mods=()
  for a in "$@"; do
    case "$a" in -*) continue ;; esac
    m="${a%%[<>=]*}"; m="${m//-/_}"
    case " ${PIP_FAIL:-} " in *" $m "*) exit 1 ;; esac
    mods+=("$m")
  done
  [ "${#mods[@]}" -eq 0 ] || printf '%s\n' "${mods[@]}" >> "$HAVE"
  for m in "${mods[@]}"; do grep -vx "$m" "$WRONG" > "$WRONG.tmp"; mv "$WRONG.tmp" "$WRONG"; done
  exit 0
fi
exit 0
EOF
  chmod +x "$MB_SEMANTIC_VENV/bin/python"
  # A base python that must never rebuild the (existing) venv.
  export PYTHON="$TMPD/base-python"
  printf '#!/bin/sh\necho "$*" >> "%s/base.log"\nexit 0\n' "$TMPD" > "$PYTHON"
  chmod +x "$PYTHON"
}

teardown() { rm -rf "$TMPD"; }

@test "bootstrap: fastembed-only venv is not 'ready' and gets the code-graph extra" {
  printf 'fastembed\nnumpy\n' > "$HAVE"
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" != *"ready"* ]] || false
  grep -q "install.*networkx" "$PIPLOG"
  grep -q "install.*tree-sitter-typescript" "$PIPLOG"
  grep -qx networkx "$HAVE"
  grep -qx tree_sitter_java "$HAVE"
  [[ "$output" == *"mb-semantic deps installed"* ]] || false
}

@test "bootstrap: every package present -> ready, pip never called" {
  printf '%s\n' fastembed numpy networkx tree_sitter tree_sitter_python tree_sitter_go \
    tree_sitter_javascript tree_sitter_typescript tree_sitter_rust tree_sitter_java > "$HAVE"
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ "$output" = "mb-semantic venv ready" ]
  [ ! -e "$PIPLOG" ]
}

@test "bootstrap: a grammar missing from an otherwise full venv is not 'ready'" {
  printf '%s\n' fastembed numpy networkx tree_sitter tree_sitter_python > "$HAVE"
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" != *"ready"* ]] || false
  grep -qx tree_sitter_rust "$HAVE"
}

@test "bootstrap: networkx install fails -> names only what is missing, exit 0" {
  PIP_FAIL=networkx run bash "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"missing: networkx ("* ]] || false
  grep -qx fastembed "$HAVE"
  grep -qx tree_sitter_go "$HAVE"
}

@test "bootstrap: fastembed install fails, the rest lands -> names fastembed only, exit 0" {
  PIP_FAIL=fastembed run bash "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"missing: fastembed ("* ]] || false
  grep -qx numpy "$HAVE"
  grep -qx networkx "$HAVE"
}

@test "bootstrap: networkx outside the pin is not 'ready' and gets reinstalled at the pin" {
  printf '%s\n' fastembed numpy networkx tree_sitter tree_sitter_python tree_sitter_go \
    tree_sitter_javascript tree_sitter_typescript tree_sitter_rust tree_sitter_java > "$HAVE"
  echo networkx > "$WRONG"
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" != *"ready"* ]] || false
  grep -q 'install.*networkx>=3.6,<3.7' "$PIPLOG"
  [ ! -s "$WRONG" ]
  [[ "$output" == *"mb-semantic deps installed"* ]] || false
}
