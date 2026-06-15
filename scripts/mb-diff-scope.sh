#!/usr/bin/env bash
# mb-diff-scope.sh — L5 diff-scope backstop runner (REQ-DF-042, ADR-4).
#
# Compares the set of changed files (`git diff --name-only`, tracked + staged)
# against an ALLOWED glob scope and reports any change that falls outside it.
# This is the deterministic backstop the design's ADR-4 references: a surgical
# arch diff that slips past route-choice still trips here if it touches a path
# outside the declared scope.
#
# Per ADR-3 this is a CHECK RUNNER, not the firewall: it ALWAYS exits 0 and
# reports pass/fail/skip ONLY through the JSON `ok` field.
#
# Usage:
#   mb-diff-scope.sh [--repo <path>] [--allow "<comma-separated globs>"]
#                    [--scope-file <path>]
#     --repo       <path> : git repo to diff (default: cwd).
#     --allow      <csv>  : comma-separated allowed globs (e.g. "src/*,docs/*").
#     --scope-file <path> : file with one allowed glob per line (# comments ok).
#     (neither --allow nor --scope-file): no scope → ok=null (skip).
#
# Glob semantics: a changed path is in-scope when it matches ANY allowed glob
# using shell `case` pattern matching (so `src/*` matches `src/app.py` and
# `src/a/b.py` alike, since `*` spans `/` in case-globs — intentionally
# permissive at the directory root).
#
# Output (stdout, always exit 0):
#   {"name":"diff_scope","ok":true|false|null,"findings":[ "<out-of-scope file>" ]}
#     ok=true   → every changed file matches an allowed glob (or no changes).
#     ok=false  → >=1 changed file is out of scope; findings list each one.
#     ok=null   → no allowed scope provided (nothing to enforce).

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

REPO="."
ALLOW_CSV=""
SCOPE_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)       REPO="${2:-.}";       shift 2 ;;
    --allow)      ALLOW_CSV="${2:-}";   shift 2 ;;
    --scope-file) SCOPE_FILE="${2:-}";  shift 2 ;;
    --help|-h)
      sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# ---- helpers ----------------------------------------------------------------

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '"%s"' "$s"
}

emit() {
  local ok="$1"; shift
  printf '{"name":"diff_scope","ok":%s,"findings":[' "$ok"
  local i=0 f
  for f in "$@"; do
    (( i > 0 )) && printf ','
    json_escape "$f"
    i=$((i + 1))
  done
  printf ']}\n'
  exit 0
}

# ---- assemble the allowed-glob list -----------------------------------------

ALLOW=()
if [[ -n "$ALLOW_CSV" ]]; then
  # Split on commas WITHOUT pathname expansion: a glob like `docs/*` must stay
  # literal, otherwise it would expand against the cwd (e.g. an existing docs/
  # dir) and corrupt the allow-list. `read -ra` with IFS=, never globs.
  IFS=',' read -r -a _allow_parts <<<"$ALLOW_CSV"
  for p in "${_allow_parts[@]}"; do
    [[ -n "$p" ]] && ALLOW+=("$p")
  done
fi

if [[ -n "$SCOPE_FILE" && -f "$SCOPE_FILE" ]]; then
  while IFS= read -r line; do
    # Strip surrounding whitespace; skip blanks and # comments.
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    ALLOW+=("$line")
  done < "$SCOPE_FILE"
fi

# No scope at all → skip.
if [[ "${#ALLOW[@]}" -eq 0 ]]; then
  echo "[diff_scope] no allowed scope provided — skipping (ok=null)" >&2
  emit null
fi

# ---- gather changed files ---------------------------------------------------

CHANGED=()
if command -v git >/dev/null 2>&1; then
  while IFS= read -r f; do
    [[ -n "$f" ]] && CHANGED+=("$f")
  done < <(
    {
      git -C "$REPO" diff --name-only 2>/dev/null
      git -C "$REPO" diff --name-only --cached 2>/dev/null
    } | sort -u
  )
else
  echo "[diff_scope] git not available — skipping (ok=null)" >&2
  emit null
fi

# No changes → vacuously in scope.
if [[ "${#CHANGED[@]}" -eq 0 ]]; then
  emit true
fi

# ---- compare ----------------------------------------------------------------

in_scope() {
  local file="$1" glob
  for glob in "${ALLOW[@]}"; do
    # shellcheck disable=SC2254
    case "$file" in
      $glob) return 0 ;;
    esac
  done
  return 1
}

OUT_OF_SCOPE=()
for file in "${CHANGED[@]}"; do
  in_scope "$file" || OUT_OF_SCOPE+=("$file")
done

if [[ "${#OUT_OF_SCOPE[@]}" -eq 0 ]]; then
  emit true
fi

emit false "${OUT_OF_SCOPE[@]}"
