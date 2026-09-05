#!/usr/bin/env bash
# mb-context.sh — collects current context from Memory Bank.
#
# Usage:
#   mb-context.sh [mb_path]          # standard context (core + plans + last note)
#   mb-context.sh --deep [mb_path]   # same + full `codebase/` Markdown docs
#   mb-context.sh --full [mb_path]   # same, without the per-file output budget
#
# Default: `.memory-bank/` in CWD (or external storage from `.claude-workspace`).
#
# Output budget:
#   Each core file is trimmed to a byte cap resolved as `MB_CONTEXT_MAX_BYTES`
#   -> `<bank>/.mb-config` `context_max_bytes=` -> 12288. `0` or `--full`
#   disables it. Trimming keeps whole units (`## ` sections in `status.md`,
#   unfinished items in `checklist.md`) and never cuts mid-line.
#
# Integration with `mb-codebase-mapper`:
#   If `.memory-bank/codebase/` exists with Markdown files, add a
#   "Codebase summary" section with a one-line summary for each doc (default)
#   or the full contents (`--deep`).

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

DEEP=0
FULL=0
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --deep) DEEP=1; shift ;;
    --full) FULL=1; shift ;;
    *) break ;;
  esac
done

MB_PATH=$(mb_resolve_path "${1:-}")

if [[ ! -d "$MB_PATH" ]]; then
  echo "[MEMORY BANK: INACTIVE] Directory $MB_PATH not found"
  exit 0
fi

# Per-file byte cap: env -> `<bank>/.mb-config` -> default. Invalid values fall
# back to the default; `0` (and `--full`) means unbounded.
CONTEXT_CAP_DEFAULT=12288
_resolve_cap() {
  local raw=""
  if [[ "$FULL" -eq 1 ]]; then
    printf '0\n'
    return 0
  fi
  if [[ -n "${MB_CONTEXT_MAX_BYTES:-}" ]]; then
    raw="$MB_CONTEXT_MAX_BYTES"
  elif [[ -f "$MB_PATH/.mb-config" && ! -L "$MB_PATH/.mb-config" ]]; then
    raw=$(grep -E '^context_max_bytes=' "$MB_PATH/.mb-config" 2>/dev/null | tail -1 | cut -d= -f2- || true)
  fi
  if [[ "$raw" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$raw"
  else
    printf '%s\n' "$CONTEXT_CAP_DEFAULT"
  fi
}
CONTEXT_CAP=$(_resolve_cap)

# Print one core file, trimmed to $CONTEXT_CAP. Fail-open: no python3, an
# unreadable file or any trimming error prints the file whole, as before.
_emit_core_file() {
  local name="$1" path="$2"
  if [[ "$CONTEXT_CAP" -le 0 ]] || ! command -v python3 >/dev/null 2>&1; then
    cat "$path"
    return 0
  fi
  MB_CTX_NAME="$name" MB_CTX_FILE="$path" MB_CTX_CAP="$CONTEXT_CAP" python3 - <<'PY' || cat "$path"
import os
import sys

name = os.environ["MB_CTX_NAME"]
path = os.environ["MB_CTX_FILE"]
cap = int(os.environ["MB_CTX_CAP"])

with open(path, encoding="utf-8", errors="surrogateescape") as fh:
    lines = fh.read().splitlines(keepends=True)


def size(chunk):
    return sum(len(ln.encode("utf-8", "surrogateescape")) for ln in chunk)


def head(chunk):
    kept, used = [], 0
    for ln in chunk:
        used += len(ln.encode("utf-8", "surrogateescape"))
        if used > cap:
            break
        kept.append(ln)
    return kept


total = len(lines)
if size(lines) <= cap:
    sys.stdout.write("".join(lines))
    sys.exit(0)

if name == "status.md":
    # Whole `## ` sections top-down; the preamble alone may already overflow.
    starts = [i for i, ln in enumerate(lines) if ln.startswith("## ")]
    if starts:
        bounds = starts + [total]
        kept = lines[: starts[0]]
        for a, b in zip(bounds, bounds[1:]):
            if size(kept) + size(lines[a:b]) > cap:
                break
            kept.extend(lines[a:b])
        if size(kept) > cap:
            kept = head(lines)
    else:
        kept = head(lines)
elif name == "checklist.md":
    # Done items are the cheapest thing to lose.
    kept = [ln for ln in lines if "\u2705" not in ln]
    if size(kept) > cap:
        kept = head(kept)
else:
    kept = head(lines)

out = "".join(kept)
if out and not out.endswith("\n"):
    out += "\n"
sys.stdout.write(out)
sys.stdout.write(
    "[context] %s: shown %d of %d lines \u2014 full: %s or --full\n"
    % (name, len(kept), total, path)
)
PY
}

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
    _emit_core_file "$file" "$safe"
    echo ""
  fi
done

# Glossary pointer (C10): one line iff `<bank>/glossary.md` is a regular file.
# Read-only: the file content is never concatenated (NFR-001 token economy);
# symlinks are skipped like the core files above.
glossary_path="$MB_PATH/glossary.md"
if [[ -f "$glossary_path" && ! -L "$glossary_path" ]]; then
  if mb_canonical_under "$MB_PATH" "$glossary_path" >/dev/null; then
    echo "Glossary: glossary.md"
  fi
fi

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
