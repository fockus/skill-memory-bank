#!/usr/bin/env bash
# mb-no-todo.sh — L5 residual-placeholder runner (REQ-DF-042).
#
# Scans target files for residual placeholder markers and reports any hit. The
# deny-set is the repo's canonical one from mb-rules-check.sh, extended with one
# extra marker for this runner. The
# heavy lifting REUSES scripts/mb_rules_check_lib.sh::scan_placeholders so the
# patterns, exemptions (tests/* paths, markdown/data files) and the
# `# mb-rules-check: allow-placeholder` line-pragma stay identical to the rest
# of the toolchain (DRY).
#
# Per ADR-3 this is a CHECK RUNNER, not the firewall: it ALWAYS exits 0 and
# reports pass/fail/skip ONLY through the JSON `ok` field.
#
# Usage:
#   mb-no-todo.sh [--dir <path>] [--files <csv>]
#     --dir   <path> : scan all regular files under <path> (recursively).
#     --files <csv>  : scan exactly these comma-separated files.
#     (default, neither given): scan `git diff --name-only` changed files.
#
# Output (stdout, always exit 0):
#   {"name":"no_todo","ok":true|false|null,"findings":[ "file:line: text" ]}
#     ok=false → >=1 unexempted placeholder found; findings list each hit.
#     ok=true  → at least one file scanned, none carried a placeholder.
#     ok=null  → nothing to scan (no files resolved) — skip / N/A.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
# shellcheck source=mb_rules_check_lib.sh
source "$SCRIPT_DIR/mb_rules_check_lib.sh"

DIR=""
FILES_CSV=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)   DIR="${2:-}";        shift 2 ;;
    --files) FILES_CSV="${2:-}";  shift 2 ;;
    --help|-h)
      sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Extend the repo's canonical deny-set with one extra marker for this runner.
# scan_placeholders reads MB_PLACEHOLDER_DENY when set, so this layers on the
# extra token without losing the shared list.
if [[ -z "${MB_PLACEHOLDER_DENY:-}" ]]; then
  export MB_PLACEHOLDER_DENY="${MB_PLACEHOLDER_DENY_DEFAULT},HACK"  # mb-rules-check: allow-placeholder
fi

# ---- resolve target files ---------------------------------------------------

FILES=()
# CHECKS_RUN is mutated by the sourced scan_placeholders (mb_rules_check_lib.sh);
# it must exist before that call under `set -u`. shellcheck can't see the
# cross-file write, hence the directive.
# shellcheck disable=SC2034
CHECKS_RUN=0
VIOLATIONS=()
PLACEHOLDER_HITS=0

if [[ -n "$DIR" ]]; then
  while IFS= read -r f; do
    [[ -n "$f" ]] && FILES+=("$f")
  done < <(find "$DIR" -type f 2>/dev/null | sort || true)
elif [[ -n "$FILES_CSV" ]]; then
  split_csv "$FILES_CSV" FILES
else
  # Default: changed files via git (tracked + staged). Best-effort; if git is
  # unavailable or this is not a repo, FILES stays empty → ok=null.
  if command -v git >/dev/null 2>&1; then
    while IFS= read -r f; do
      [[ -n "$f" && -f "$f" ]] && FILES+=("$f")
    done < <(git diff --name-only 2>/dev/null; git diff --name-only --cached 2>/dev/null)
  fi
fi

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
  printf '{"name":"no_todo","ok":%s,"findings":[' "$ok"
  local i=0 f
  for f in "$@"; do
    (( i > 0 )) && printf ','
    json_escape "$f"
    i=$((i + 1))
  done
  printf ']}\n'
  exit 0
}

# ---- scan -------------------------------------------------------------------

# Count resolved, readable files. ZERO files at all → skip (ok=null). Files
# that exist but are all exemptable (markdown, tests/, …) still count as a
# real scan: nothing unexempted is found → ok=true. This keeps the null/skip
# verdict reserved for "there was genuinely nothing to look at".
RESOLVED=0
for f in "${FILES[@]+"${FILES[@]}"}"; do
  [[ -f "$f" ]] && RESOLVED=$((RESOLVED + 1))
done

if [[ "$RESOLVED" -eq 0 ]]; then
  echo "[no_todo] no files resolved — skipping (ok=null)" >&2
  emit null
fi

# scan_placeholders populates VIOLATIONS[] (JSON objects) + PLACEHOLDER_HITS.
scan_placeholders

if [[ "$PLACEHOLDER_HITS" -eq 0 ]]; then
  emit true
fi

# Render each violation into a compact "<file>:<line>: <excerpt>" finding by
# parsing the JSON objects scan_placeholders produced (python3 is a hard dep).
FINDINGS=()
for v in "${VIOLATIONS[@]+"${VIOLATIONS[@]}"}"; do
  finding="$(printf '%s' "$v" | python3 -c '
import sys, json
o = json.loads(sys.stdin.read())
print("{}:{}: {}".format(o.get("file", ""), o.get("line", ""), o.get("excerpt", "").strip()))
')"
  FINDINGS+=("$finding")
done

emit false "${FINDINGS[@]+"${FINDINGS[@]}"}"
