#!/usr/bin/env bash
# mb-recall.sh — progressive-disclosure recall over Memory Bank session/ + notes/.
#
# Default output is a COMPACT INDEX — one line per hit `id · age · summary · source`
# (no chunk bodies; ~15 tokens/line). Semantic + lexical hits are fused via RRF when
# the semantic backend is available (fail-open to lexical-only otherwise).
#
# Usage:
#   mb-recall.sh <query...>                 # compact index (default)
#   mb-recall.sh --expand <id> <query...>   # full chunk for one id (non-zero if unknown)
#   mb-recall.sh --full <query...>          # legacy full bodies
#   mb-recall.sh -k N <query...>            # cap results (default 10)
set -u

HOOK_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || exit 0
# shellcheck source=lib/session-common.sh
. "$HOOK_DIR/lib/session-common.sh"

MODE="compact"
EXPAND_ID=""
LIMIT="${MB_RECALL_LIMIT:-10}"
ARGS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --expand) MODE="expand"; EXPAND_ID="${2:-}"; shift 2 || shift ;;
    --full) MODE="full"; shift ;;
    -k|--top-k) LIMIT="${2:-10}"; shift 2 || shift ;;
    --) shift; while [ "$#" -gt 0 ]; do ARGS+=("$1"); shift; done ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

QUERY="${ARGS[*]:-}"
if [ -z "$QUERY" ] && [ "$MODE" != "expand" ]; then
  echo "usage: mb-recall <query> [--expand <id>] [--full] [-k N]"
  exit 0
fi

CWD="${CLAUDE_PROJECT_DIR:-$PWD}"
MB="$(sc_resolve_mb "$CWD")"
if [ -z "$MB" ]; then
  echo "no Memory Bank found"
  exit 0
fi

targets=()
[ -d "$MB/session" ] && targets+=("$MB/session")
[ -d "$MB/notes" ] && targets+=("$MB/notes")
if [ "${#targets[@]}" -eq 0 ]; then
  echo "no session/ or notes/ to search"
  exit 0
fi

JQ="${JQ:-jq}"
PY="$(sc_semantic_py "$HOOK_DIR" "$MB")"
command -v "$PY" >/dev/null 2>&1 || PY="python3"

# --- semantic hits (best-effort; empty JSON array when unavailable) -------------
SEM="[]"
if [ "${MB_SEMANTIC:-auto}" != "off" ] && command -v "$JQ" >/dev/null 2>&1; then
  raw="$(MB_ROOT="$MB" "$PY" "$HOOK_DIR/mb-semantic.py" search "$QUERY" \
         --top-k "$LIMIT" --min-score "${MB_SEMANTIC_MIN_SCORE:-0.3}" \
         --timeout "${MB_SEMANTIC_TIMEOUT:-5}" --json 2>/dev/null || true)"
  if [ -n "$raw" ] && printf '%s' "$raw" | "$JQ" -e 'type=="array"' >/dev/null 2>&1; then
    SEM="$raw"
  fi
fi

# --- lexical hits: ripgrep/grep → relative-path JSON objects ---------------------
RG="${RG:-rg}"
if command -v "$RG" >/dev/null 2>&1; then
  lex_raw="$("$RG" -n --no-heading --color=never -i -- "$QUERY" "${targets[@]}" 2>/dev/null || true)"
else
  lex_raw="$(grep -rni -- "$QUERY" "${targets[@]}" 2>/dev/null || true)"
fi

# Convert `path:line:text` rows into JSON objects with paths RELATIVE to $MB
# (so the bridge can stat/read them and derive stable ids).
LEX="$(MB="$MB" "$PY" - "$lex_raw" <<'PY' 2>/dev/null || echo '[]'
import json, os, sys
mb = os.environ.get("MB", "")
out = []
for line in (sys.argv[1] if len(sys.argv) > 1 else "").splitlines():
    if not line.strip():
        continue
    parts = line.split(":", 2)
    if len(parts) < 3:
        continue
    path, lineno, text = parts
    rel = os.path.relpath(path, mb) if mb else path
    try:
        lineno = int(lineno)
    except ValueError:
        lineno = 0
    out.append({"source": rel, "line": lineno, "text": text})
print(json.dumps(out, ensure_ascii=False))
PY
)"
[ -n "$LEX" ] || LEX="[]"

# --- build request + render via the recall-index bridge -------------------------
emit_request() {
  if command -v "$JQ" >/dev/null 2>&1; then
    # shellcheck disable=SC2016 # $q/$mb/... are jq variables bound via --arg/--argjson.
    "$JQ" -n \
      --arg q "$QUERY" --arg mb "$MB" --arg mode "$MODE" \
      --arg eid "$EXPAND_ID" --argjson limit "$LIMIT" \
      --argjson sem "$SEM" --argjson lex "$LEX" \
      '{query:$q, mb:$mb, mode:$mode, expand_id:$eid, limit:$limit, semantic:$sem, lexical:$lex}'
  else
    MB="$MB" QUERY="$QUERY" MODE="$MODE" EXPAND_ID="$EXPAND_ID" LIMIT="$LIMIT" \
    SEM="$SEM" LEX="$LEX" "$PY" - <<'PY'
import json, os
print(json.dumps({
    "query": os.environ["QUERY"], "mb": os.environ["MB"],
    "mode": os.environ["MODE"], "expand_id": os.environ["EXPAND_ID"],
    "limit": int(os.environ["LIMIT"]),
    "semantic": json.loads(os.environ["SEM"]), "lexical": json.loads(os.environ["LEX"]),
}))
PY
  fi
}

REQ="$(emit_request)"
OUT="$(printf '%s' "$REQ" | "$PY" "$HOOK_DIR/lib/recall_index.py" 2>/tmp/mb-recall-err.$$)"
CODE=$?
ERR="$(cat "/tmp/mb-recall-err.$$" 2>/dev/null || true)"; rm -f "/tmp/mb-recall-err.$$" 2>/dev/null

if [ "$MODE" = "expand" ]; then
  if [ "$CODE" -ne 0 ]; then
    [ -n "$ERR" ] && printf '%s\n' "$ERR" >&2
    exit "$CODE"
  fi
  printf '%s\n' "$OUT"
  exit 0
fi

if [ "$CODE" -eq 0 ] && [ -n "$OUT" ]; then
  printf '%s\n' "$OUT"
else
  echo "no matches for: $QUERY"
fi
exit 0
