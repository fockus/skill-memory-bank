#!/usr/bin/env bash
# mb-lint-run.sh — L5 lint runner (REQ-DF-042).
#
# Detects the project stack via scripts/mb-metrics.sh (exactly like
# mb-test-run.sh), maps it to a linter, runs the linter, and reports findings.
# Supported in v1: python (`ruff check`), shell (`shellcheck` over *.sh).
# Any other / unknown stack — or a missing linter binary — is a SKIP (ok=null)
# with a stderr WARN, never a failure.
#
# Per ADR-3 this is a CHECK RUNNER, not the firewall: it ALWAYS exits 0 and
# reports pass/fail/skip ONLY through the JSON `ok` field. The L5 fan-out
# (mb-flow-verify.sh) owns exit codes.
#
# Usage:
#   mb-lint-run.sh [--dir <path>] [--stack <name>] [--max-findings <N>]
#     --dir          <path> : project dir to lint (default: cwd).
#     --stack        <name> : force the linter stack (python|shell), bypassing
#                             auto-detection (e.g. shell repos have no manifest).
#     --max-findings <N>    : cap findings emitted (default: 50).
#
# Output (stdout, always exit 0):
#   {"name":"lint","ok":true|false|null,"findings":[ "<message>" ]}
#     ok=true  → linter ran clean (no findings).
#     ok=false → linter reported >=1 finding; findings list them (capped).
#     ok=null  → no supported linter for this stack / linter not installed.

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

DIR="."
FORCE_STACK=""
MAX_FINDINGS=50

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)          DIR="${2:-.}";          shift 2 ;;
    --stack)        FORCE_STACK="${2:-}";   shift 2 ;;
    --max-findings) MAX_FINDINGS="${2:-50}"; shift 2 ;;
    --help|-h)
      sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
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
  printf '{"name":"lint","ok":%s,"findings":[' "$ok"
  local i=0 f
  for f in "$@"; do
    (( i > 0 )) && printf ','
    json_escape "$f"
    i=$((i + 1))
  done
  printf ']}\n'
  exit 0
}

# Cap an array of finding lines to MAX_FINDINGS and emit ok=false.
emit_findings() {
  local -a capped=()
  local n=0 line
  for line in "$@"; do
    [[ -z "$line" ]] && continue
    capped+=("$line")
    n=$((n + 1))
    (( n >= MAX_FINDINGS )) && break
  done
  emit false "${capped[@]+"${capped[@]}"}"
}

# ---- stack detection --------------------------------------------------------

if [[ -n "$FORCE_STACK" ]]; then
  STACK="$FORCE_STACK"
else
  METRICS_OUT="$(bash "$(dirname "$0")/mb-metrics.sh" "$DIR" 2>/dev/null || true)"
  STACK="$(printf '%s\n' "$METRICS_OUT" | awk -F= '$1=="stack"{print $2; exit}')"
  [[ -z "$STACK" ]] && STACK="unknown"
fi

# ---- per-stack runners ------------------------------------------------------

run_python() {
  command -v ruff >/dev/null 2>&1 || {
    echo "[lint] ruff not in PATH — skipping python lint (ok=null)" >&2
    emit null
  }
  local log
  log="$(mktemp)"
  # `ruff check` exits 1 when findings exist; capture both and never let the
  # non-zero rc bubble out (ADR-3 — only the JSON carries the verdict).
  (cd "$DIR" && ruff check . --output-format concise) >"$log" 2>&1 || true
  local -a findings=()
  while IFS= read -r line; do
    # Keep diagnostic lines that look like "path:line:col: CODE message".
    [[ "$line" =~ :[0-9]+:[0-9]+: ]] || continue
    findings+=("$line")
  done < "$log"
  rm -f "$log"
  if [[ "${#findings[@]}" -eq 0 ]]; then
    emit true
  fi
  emit_findings "${findings[@]}"
}

run_shell() {
  command -v shellcheck >/dev/null 2>&1 || {
    echo "[lint] shellcheck not in PATH — skipping shell lint (ok=null)" >&2
    emit null
  }
  # Collect *.sh under DIR (excluding hidden + vendor-ish paths).
  local -a sh_files=()
  while IFS= read -r f; do
    [[ -n "$f" ]] && sh_files+=("$f")
  done < <(find "$DIR" -type f -name '*.sh' \
              -not -path '*/.*' \
              -not -path '*/node_modules/*' \
              2>/dev/null | sort || true)
  if [[ "${#sh_files[@]}" -eq 0 ]]; then
    echo "[lint] no *.sh files under $DIR — skipping shell lint (ok=null)" >&2
    emit null
  fi
  local log
  log="$(mktemp)"
  # GCC format → one "file:line:col: level: message" per finding line.
  shellcheck --format=gcc "${sh_files[@]}" >"$log" 2>&1 || true
  local -a findings=()
  while IFS= read -r line; do
    [[ "$line" =~ :[0-9]+:[0-9]+: ]] || continue
    findings+=("$line")
  done < "$log"
  rm -f "$log"
  if [[ "${#findings[@]}" -eq 0 ]]; then
    emit true
  fi
  emit_findings "${findings[@]}"
}

case "$STACK" in
  python) run_python ;;
  shell)  run_shell ;;
  *)
    echo "[lint] stack=$STACK has no supported linter in mb-lint-run.sh v1 — skipping (ok=null)" >&2
    emit null
    ;;
esac
