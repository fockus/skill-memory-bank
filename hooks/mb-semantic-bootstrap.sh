#!/usr/bin/env bash
# mb-semantic-bootstrap.sh — create .venv and install fastembed+numpy (semantic search)
# plus the code-graph extra: tree-sitter grammars + networkx (AGR-053). Idempotent.
# Safe to run repeatedly; exits 0 if already present. Never required at query time.
set -u
HOOK_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || exit 0
# shellcheck source=lib/venv-requirements.sh
. "$HOOK_DIR/lib/venv-requirements.sh" 2>/dev/null || { echo "venv-requirements.sh missing"; exit 0; }
# venv sits beside the installed CLI/hooks (global ~/.claude/hooks/.venv, or a project
# bin/.venv). Override with MB_SEMANTIC_VENV. sc_semantic_py resolves the same precedence.
VENV="${MB_SEMANTIC_VENV:-$HOOK_DIR/.venv}"
PY="${PYTHON:-python3}"
read -r -a PKGS <<< "$MB_VENV_SEMANTIC_PKGS $MB_VENV_CODEGRAPH_PKGS"
# Import names of the requirements the venv does not satisfy — absent, not
# importable, or installed outside the pinned version (AGR-054). Every package
# is part of "ready": a venv made before AGR-053 has fastembed only, and one made
# before the pin may hold a networkx minor that clusters differently. A checker
# that cannot run reports everything unmet rather than a false "ready".
unmet_mods() {
  local out req mod
  out="$("$VENV/bin/python" "$HOOK_DIR/lib/venv_unmet.py" "${PKGS[@]}" 2>/dev/null)" \
    || out="$(printf '%s\n' "${PKGS[@]}")"
  for req in $out; do
    mod="${req%%[<>=!~]*}"
    printf ' %s' "${mod//-/_}"
  done
}
if [ -x "$VENV/bin/python" ] && [ -z "$(unmet_mods)" ]; then
  echo "mb-semantic venv ready"; exit 0
fi
if [ ! -x "$VENV/bin/python" ]; then
  command -v "$PY" >/dev/null 2>&1 || { echo "no python3"; exit 0; }
  "$PY" -m venv "$VENV" 2>/dev/null || { echo "venv create failed"; exit 0; }
fi
"$VENV/bin/python" -m pip install --quiet --upgrade pip >/dev/null 2>&1
# One resolve on the happy path; package by package when it fails, so one
# unavailable wheel does not cost the others.
if ! "$VENV/bin/python" -m pip install --quiet "${PKGS[@]}" >/dev/null 2>&1; then
  for pkg in "${PKGS[@]}"; do
    "$VENV/bin/python" -m pip install --quiet "$pkg" >/dev/null 2>&1
  done
fi
missing="$(unmet_mods)"
if [ -z "$missing" ]; then
  echo "mb-semantic deps installed"
else
  echo "deps install incomplete, missing:$missing (no fastembed: semantic search falls back to lexical; no networkx/tree_sitter*: graph builds without clusters/PageRank or those languages)"
fi
exit 0
