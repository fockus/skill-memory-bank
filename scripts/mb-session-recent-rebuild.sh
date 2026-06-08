#!/usr/bin/env bash
# mb-session-recent-rebuild.sh — regenerate session/_recent.md from existing
# session/*.md files. Keeps the newest MB_RECENT_KEEP (default 5) sessions that
# carry a `## Summary`; skips empty / summary-less ones. Deterministic & idempotent.
# Usage: mb-session-recent-rebuild.sh [mb_path]
set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

MB_PATH=$(mb_resolve_path "${1:-}")
SDIR="$MB_PATH/session"
KEEP="${MB_RECENT_KEEP:-5}"

[ -d "$SDIR" ] || { echo "no session dir: $SDIR" >&2; exit 0; }

RECENT="$SDIR/_recent.md"
tmp="$RECENT.tmp.$$"
: > "$tmp"
count=0

# newest first: filenames start with YYYY-MM-DD_HHMM_ so reverse lexical = newest first.
while IFS= read -r f; do
  [ "$count" -ge "$KEEP" ] && break
  # Body of the `## Summary` section: lines after the header until the next `## ` heading.
  summary="$(awk '/^## Summary$/{f=1;next} f&&/^## /{f=0} f' "$f")"
  # trim leading/trailing blank lines
  summary="$(printf '%s\n' "$summary" | sed -e '/./,$!d' | awk 'NF{p=NR} {a[NR]=$0} END{for(i=1;i<=p;i++)print a[i]}')"
  [ -n "$summary" ] || continue

  base="$(basename "$f" .md)"
  if [[ "$base" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})_([0-9]{2})([0-9]{2})_([0-9a-f]+)$ ]]; then
    date="${BASH_REMATCH[1]}"; hh="${BASH_REMATCH[2]}"; mm="${BASH_REMATCH[3]}"; sid8="${BASH_REMATCH[4]}"
  else
    continue
  fi

  branch="$(awk 'NR==1&&/^---$/{i=1;next} i&&/^---$/{exit} i{p=index($0,":"); if(p>0){k=substr($0,1,p-1); gsub(/^[ \t]+|[ \t]+$/,"",k); if(k=="branch"){v=substr($0,p+1); gsub(/^[ \t]+|[ \t]+$/,"",v); print v; exit}}}' "$f")"
  [ -n "$branch" ] || branch="-"

  printf '## %s %s:%s (%s) — %s\n%s\n\n' "$date" "$hh" "$mm" "$branch" "$sid8" "$summary" >> "$tmp"
  count=$((count + 1))
done < <(find "$SDIR" -maxdepth 1 -name '*.md' ! -name '_recent.md' 2>/dev/null | sort -r)

mv "$tmp" "$RECENT"
echo "$RECENT ($count entries)"
