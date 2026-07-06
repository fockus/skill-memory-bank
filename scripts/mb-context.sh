#!/usr/bin/env bash
# mb-context.sh — collects current context from Memory Bank.
#
# Usage:
#   mb-context.sh [mb_path]          # standard context (core + plans + last note)
#   mb-context.sh --deep [mb_path]   # same + full `codebase/` Markdown docs
#
# Default: `.memory-bank/` in CWD (or external storage from `.claude-workspace`).
#
# Integration with `mb-codebase-mapper`:
#   If `.memory-bank/codebase/` exists with Markdown files, add a
#   "Codebase summary" section with a one-line summary for each doc (default)
#   or the full contents (`--deep`).

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

DEEP=0
if [[ "${1:-}" == "--deep" ]]; then
  DEEP=1
  shift
fi

MB_PATH=$(mb_resolve_path "${1:-}")

if [[ ! -d "$MB_PATH" ]]; then
  echo "[MEMORY BANK: INACTIVE] Directory $MB_PATH not found"
  exit 0
fi

echo "=== [MEMORY BANK: ACTIVE] ==="
echo ""

# Core files
for file in status.md roadmap.md checklist.md research.md; do
  filepath="$MB_PATH/$file"
  if [[ -L "$filepath" ]]; then
    echo "[context] skip symlink: $filepath" >&2
    continue
  fi
  if [[ -f "$filepath" ]]; then
    safe=$(mb_canonical_under "$MB_PATH" "$filepath") || {
      echo "[context] skip out-of-bank file: $filepath" >&2
      continue
    }
    echo "--- $file ---"
    cat "$safe"
    echo ""
  fi
done

# Active plans (not in `done/`)
if [[ -d "$MB_PATH/plans" ]]; then
  active_plans=$(find "$MB_PATH/plans" -maxdepth 1 -name "*.md" -type f ! -type l 2>/dev/null | sort -r | head -3)
  if [[ -n "$active_plans" ]]; then
    echo "--- Active plans ---"
    while IFS= read -r plan; do
      echo "  - $(basename "$plan")"
    done <<< "$active_plans"
    echo ""
  fi
fi

# Codebase summary (from `mb-codebase-mapper`)
if [[ -d "$MB_PATH/codebase" ]]; then
  codebase_mds=$(find "$MB_PATH/codebase" -maxdepth 1 -name "*.md" -type f 2>/dev/null | sort)
  if [[ -n "$codebase_mds" ]]; then
    echo "--- Codebase summary ---"
    while IFS= read -r md; do
      name=$(basename "$md")
      if [[ "$DEEP" -eq 1 ]]; then
        echo ""
        echo "### $name"
        cat "$md"
      else
        # First non-empty line that is not a Markdown heading
        summary=$(grep -vE '^(#|\s*$)' "$md" 2>/dev/null | head -1 || true)
        if [[ -n "$summary" ]]; then
          echo "  $name: $summary"
        else
          echo "  $name: (empty)"
        fi
      fi
    done <<< "$codebase_mds"
    echo ""
  fi
fi

# Code graph (freshness + counts + ready commands; never injects graph contents)
# Fail-open: any error skips the section without aborting mb-context.sh (set -e safe).
_graph_section() {
  local graph_json="$MB_PATH/codebase/graph.json"
  local gq
  gq="$(dirname "$0")/mb-graph-query.py"
  local build_cmd="python3 ~/.claude/skills/memory-bank/scripts/mb-codegraph.py --apply --docs $MB_PATH ."
  echo "--- Code graph ---"
  if [[ ! -f "$graph_json" ]]; then
    echo "  not built → build: $build_cmd"
    echo ""
    return 0
  fi
  local status_json=""
  if command -v python3 >/dev/null 2>&1 && [[ -f "$gq" ]]; then
    status_json=$(python3 "$gq" status --graph "$graph_json" --src-root . --json 2>/dev/null || true)
  fi
  if [[ -n "$status_json" ]]; then
    printf '%s' "$status_json" | python3 -c '
import sys, json
d = json.load(sys.stdin)
age = d.get("age_hours")
behind = d.get("commits_behind")
age_s = "age %.0fh" % age if isinstance(age, (int, float)) else "age n/a"
behind_s = "" if behind is None else ", %d commits behind" % behind
rebuild = "python3 ~/.claude/skills/memory-bank/scripts/mb-codegraph.py --apply --docs . ."
if d.get("stale"):
    print("  stale (%s%s) -> rebuild: %s" % (age_s, behind_s, rebuild))
else:
    print("  fresh (%s%s)" % (age_s, behind_s))
n = d.get("nodes")
e = d.get("edges")
n = "?" if n is None else n
e = "?" if e is None else e
print("  nodes=%s edges=%s" % (n, e))
' 2>/dev/null || echo "  (freshness parse unavailable)"
  else
    # Degrade to existence + mtime only (no python3 / no query script).
    echo "  present (freshness unavailable — needs python3); rebuild: $build_cmd"
    echo "  nodes=? edges=?"
  fi
  echo "  god-nodes: $MB_PATH/codebase/god-nodes.md"
  echo "  impact before refactor: python3 ~/.claude/skills/memory-bank/scripts/mb-graph-query.py impact --graph $graph_json --symbol <Name>"
  echo "  concept search: python3 ~/.claude/skills/memory-bank/scripts/mb-semantic-search.py \"<question>\" $MB_PATH --source-only"
  echo ""
}
if [[ -d "$MB_PATH/codebase" ]]; then
  _graph_section || true
fi

# Latest note
if [[ -d "$MB_PATH/notes" ]]; then
  latest_note=$(find "$MB_PATH/notes" -name "*.md" -type f 2>/dev/null | sort -r | head -1)
  if [[ -n "$latest_note" ]]; then
    echo "--- Latest note: $(basename "$latest_note") ---"
    cat "$latest_note"
    echo ""
  fi
fi
